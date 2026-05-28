package Koha::SearchEngine::Elasticsearch::Search::Patrons;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use base qw(Koha::SearchEngine::Elasticsearch::Search);

use C4::Context;
use Koha::Patrons;
use Koha::Patron::Attribute::Types;
use Koha::SearchEngine::Elasticsearch;
use Koha::SearchEngine::Elasticsearch::Indexer::Patrons;
use Koha::Exceptions::SearchEngine::Search;
use Koha::Exceptions::Elasticsearch;

use Try::Tiny qw( catch try );

use Readonly qw( Readonly );

=head1 NAME

Koha::SearchEngine::Elasticsearch::Search::Patrons - Patron search via ES

=head1 SYNOPSIS

    use Koha::SearchEngine::Elasticsearch::Search::Patrons;

    my $searcher = Koha::SearchEngine::Elasticsearch::Search::Patrons->new();
    my $results  = $searcher->search_patrons(
        query                => "smith",
        page                 => 1,
        per_page             => 20,
        order_by             => "-surname",
        filters              => { library_id => "CPL" },
        restricted_libraries => \@libraries_user_can_see,
    );

=cut

# Fields used for facet aggregations
Readonly my @FACET_FIELDS => qw( library_id category_id restricted );

=head2 new

    my $searcher = Koha::SearchEngine::Elasticsearch::Search::Patrons->new();

=cut

sub new {
    my ( $class, $params ) = @_;
    $params //= {};
    $params->{index} = $Koha::SearchEngine::Elasticsearch::PATRONS_INDEX;
    return $class->SUPER::new($params);
}

=head2 search_patrons

    my $results = $searcher->search_patrons(
        query                => $q,
        fields               => \@fields,       # optional, overrides default (validated against searchable set)
        page                 => $page,
        per_page             => $per_page,
        order_by             => $order_by,       # e.g. "-surname", "+ext_attr_DEPT"
        filters              => \%filters,       # facet filters (library_id, category_id, restricted, ext_attr_*)
        column_filters       => \%column_filters,# per-field filters
        restricted_libraries => \@library_ids,   # libraries the caller may see (scoping)
    );

Returns hashref: { total => $n, hits => \@patron_ids, facets => \%facets }

=cut

sub search_patrons {
    my ( $self, %args ) = @_;

    my $query_string         = $args{query};
    my $page                 = $args{page}     // 1;
    my $per_page             = $args{per_page} // 20;
    my $order_by             = $args{order_by};
    my $match                = $args{match}                // 'contains';
    my $column_filters       = $args{column_filters}       // {};
    my $filters              = $args{filters}              // {};
    my $restricted_libraries = $args{restricted_libraries} // [];
    my $fields               = $args{fields};

    # Security boundary: caller-supplied field names (search fields, filter keys
    # and sort keys) must all belong to the resolved searchable set. Without this
    # a caller with only list_borrowers could reach non-staff_searchable
    # attributes by naming them explicitly via fields/filters/_order_by.
    my %allowed = $self->_searchable_fields;

    if ( $fields && @$fields ) {
        $self->_assert_searchable( \%allowed, @$fields );
    }
    $self->_assert_searchable( \%allowed, keys %$filters )        if $filters        && %$filters;
    $self->_assert_searchable( \%allowed, keys %$column_filters ) if $column_filters && %$column_filters;
    $self->_assert_searchable( \%allowed, split /,/, $order_by ) if defined $order_by && $order_by ne '';

    # Resolve search fields
    my @search_fields = $fields ? @$fields : $self->_resolve_search_fields();

    # Build the query body
    my $body = $self->_build_query(
        query_string         => $query_string,
        search_fields        => \@search_fields,
        match                => $match,
        column_filters       => $column_filters,
        filters              => $filters,
        restricted_libraries => $restricted_libraries,
    );

    # Sorting
    if ($order_by) {
        $body->{sort} = $self->_build_sort($order_by);
    }

    # Pagination
    $body->{from} = ( $page - 1 ) * $per_page;
    $body->{size} = $per_page;

    # Return only computed fields from _source (rest hydrated from DB)
    $body->{_source} = [qw( checkouts_count account_balance library_name )];

    # Execute
    my $elasticsearch = $self->get_elasticsearch();
    my $response      = try {
        $elasticsearch->search(
            index            => $self->index_name,
            track_total_hits => \1,
            body             => $body,
        );
    } catch {

        # Surface ES query/transport errors as a domain exception so the
        # controller can return the documented 400 invalid_query instead of a
        # bare 500 (e.g. a match_phrase_prefix issued against a date field).
        Koha::Exceptions::Elasticsearch::BadResponse->throw(
            type    => ( ref $_ && $_->{type} ) // 'query_error',
            details => "$_",
        );
    };

    # Parse results
    my $total =
        ref $response->{hits}{total} eq 'HASH'
        ? $response->{hits}{total}{value}
        : $response->{hits}{total};

    my @patron_ids = map { $_->{_id} } @{ $response->{hits}{hits} };

    # Extract _source fields keyed by patron_id
    my %es_data;
    for my $hit ( @{ $response->{hits}{hits} } ) {
        $es_data{ $hit->{_id} } = $hit->{_source} // {};
    }

    my %facets;
    if ( my $aggs = $response->{aggregations} ) {
        for my $field (@FACET_FIELDS) {
            next unless $aggs->{$field};
            $facets{$field} =
                [ map { { value => $_->{key}, count => $_->{doc_count} } } @{ $aggs->{$field}{buckets} } ];
        }
    }

    return {
        total   => $total,
        hits    => \@patron_ids,
        es_data => \%es_data,
        facets  => \%facets,
    };
}

=head2 _resolve_search_fields

Returns the list of ES fields to search based on the caller's library.
Includes core fields + extended attribute fields visible to the library.

=cut

sub _resolve_search_fields {
    my ($self) = @_;

    # Honor DefaultPatronSearchFields syspref for the "Standard" field set.
    # The syspref is shared with the legacy DB-backed patron search and stores
    # borrowers *column* names (e.g. 'othernames', 'emailpro'), whereas the ES
    # index is built with API field names (e.g. 'other_name', 'secondary_email')
    # via Koha::Patron->to_api_mapping. Translate each token through the same
    # mapping so the fields resolve against the index; fields excluded from the
    # API (mapped to undef) are dropped.
    my $default_fields = C4::Context->preference('DefaultPatronSearchFields')
        || 'firstname|preferred_name|middle_name|surname|othernames|cardnumber|userid';

    my %api_field_map = %{ Koha::Patron->to_api_mapping() };
    my @fields;
    for my $token ( split /\|/, $default_fields ) {
        next unless defined $token && $token ne '';
        next if exists $api_field_map{$token} && !defined $api_field_map{$token};
        push @fields, $api_field_map{$token} // $token;
    }

    # Always include patron_name composite field for cross-field matching
    push @fields, 'patron_name' unless grep { $_ eq 'patron_name' } @fields;

    # Add only searched_by_default extended attribute fields to the default search
    my $attr_types_rs = Koha::Patron::Attribute::Types->search_with_library_limits(
        { staff_searchable => 1, searched_by_default => 1 },
        {}, undef
    );

    while ( my $type = $attr_types_rs->next ) {
        push @fields, "ext_attr_" . $type->code;

        # Include description field for AV-backed attributes
        push @fields, "ext_attr_" . $type->code . "_description"
            if $type->authorised_value_category;
    }

    return @fields;
}

=head2 _searchable_fields

    my %allowed = $self->_searchable_fields;

Returns the authoritative set of field names a caller is permitted to search,
filter or sort on, as a hash (field name => 1) for fast lookup. This is the
security boundary for staff-supplied C<fields>, C<filters> and C<_order_by>:
it comprises the core fields declared in the patron mappings plus the
C<ext_attr_E<lt>codeE<gt>> (and C<_description>) fields for extended attribute
types that are C<staff_searchable> and visible to the caller's library.

Attribute types that are not staff_searchable are deliberately excluded, so a
caller cannot reach them by naming the field explicitly.

=cut

sub _searchable_fields {
    my ($self) = @_;

    return %{ $self->{_searchable_fields_cache} } if $self->{_searchable_fields_cache};

    my %allowed;

    # Core fields: everything declared in the patron mappings (API field names).
    my $indexer  = Koha::SearchEngine::Elasticsearch::Indexer::Patrons->new();
    my $mappings = $indexer->get_elasticsearch_mappings();
    $allowed{$_} = 1 for keys %{ $mappings->{properties} // {} };

    # Extended attributes: only those flagged staff_searchable and visible to
    # the caller's library. Description sub-fields follow the same rule.
    my $attr_types_rs =
        Koha::Patron::Attribute::Types->search_with_library_limits( { staff_searchable => 1 }, {}, undef );
    while ( my $type = $attr_types_rs->next ) {
        $allowed{ "ext_attr_" . $type->code } = 1;
        $allowed{ "ext_attr_" . $type->code . "_description" } = 1
            if $type->authorised_value_category;
    }

    $self->{_searchable_fields_cache} = \%allowed;
    return %allowed;
}

=head2 _assert_searchable

    $self->_assert_searchable( \%allowed, @field_names );

Throws C<Koha::Exceptions::SearchEngine::Search::InvalidQuery> if any of the
given field names (composite C<a:b> keys are split on ':') is not part of the
allowed set. Used to validate caller-supplied fields, filter keys and sort keys.

=cut

sub _assert_searchable {
    my ( $self, $allowed, @names ) = @_;

    my @invalid;
    for my $name (@names) {
        next unless defined $name && $name ne '';
        for my $part ( split /:/, $name ) {
            $part =~ s/^[-+]//;        # strip sort direction markers
            $part =~ s/^\s+|\s+$//g;
            next if $part eq '';
            push @invalid, $part unless $allowed->{$part};
        }
    }

    Koha::Exceptions::SearchEngine::Search::InvalidQuery->throw(
        error          => "Invalid or non-searchable field(s): " . join( ', ', @invalid ),
        invalid_fields => \@invalid,
    ) if @invalid;

    return 1;
}

=head2 _build_query

Builds the ES query body with multi_match + filters + aggregations.

=cut

sub _build_query {
    my ( $self, %args ) = @_;

    my $query_string         = $args{query_string};
    my $search_fields        = $args{search_fields};
    my $match                = $args{match}          // 'contains';
    my $column_filters       = $args{column_filters} // {};
    my $filters              = $args{filters};
    my $restricted_libraries = $args{restricted_libraries} // [];

    # Main text query
    my $must;
    if ( !defined $query_string || $query_string eq '' ) {

        # Empty query: browse all patrons
        $must = { match_all => {} };
    } else {
        my $escaped = $query_string;
        $escaped =~ s/([\+\-\=\&\|\>\<\!\(\)\{\}\[\]\^"~\*\?\:\\\/])/\\$1/g;
        my $lc_query = lc($query_string);

        if ( $match eq 'starts_with' ) {

            # Prefix-only: match beginning of fields
            my @should = map { { prefix => { "$_.ci_raw" => $lc_query } } } @$search_fields;
            $must = { bool => { should => \@should, minimum_should_match => 1 } };
        } else {

            # Contains: wildcard + prefix fallback
            $must = {
                bool => {
                    should => [
                        {
                            query_string => {
                                query            => "*$escaped*",
                                fields           => $search_fields,
                                analyze_wildcard => \1,
                            },
                        },
                        { prefix => { 'cardnumber.ci_raw'  => $lc_query } },
                        { prefix => { 'patron_name.ci_raw' => $lc_query } },
                        { prefix => { 'email.ci_raw'       => $lc_query } },
                    ],
                    minimum_should_match => 1,
                },
            };
        }
    }

    # Filter clauses
    my @filter_clauses;

    # Facet filters from the request
    for my $field ( keys %$filters ) {
        next unless defined $filters->{$field};
        my $value = $filters->{$field};
        next if ref $value eq 'ARRAY' && !@$value;
        next if !ref $value           && $value eq '';

        my $es_field;
        if ( $field eq 'restricted' ) {
            $es_field = $field;
        } elsif ( $field =~ /^ext_attr_/ ) {
            $es_field = "${field}.raw";
        } else {
            $es_field = "${field}.facet";
        }

        if ( ref $value eq 'ARRAY' ) {
            push @filter_clauses, { terms => { $es_field => $value } };
        } else {
            push @filter_clauses, { term => { $es_field => $value } };
        }
    }

    # Library scoping
    if (@$restricted_libraries) {
        push @filter_clauses, { terms => { 'library_id.facet' => $restricted_libraries } };
    }

    # Column-level field filters (additive, each becomes a must clause)
    my @must_clauses;
    push @must_clauses, $must;
    for my $field ( keys %$column_filters ) {
        my $value  = $column_filters->{$field};
        my $lc_val = lc($value);
        my @fields = split /:/, $field;
        my @should;
        for my $f (@fields) {
            push @should,
                { prefix              => { "${f}.ci_raw" => $lc_val } },
                { match_phrase_prefix => { $f            => $value } };
        }
        push @must_clauses, {
            bool => {
                should               => \@should,
                minimum_should_match => 1,
            },
        };
    }

    my $body = {
        query => {
            bool => {
                must   => \@must_clauses,
                filter => \@filter_clauses,
            },
        },
        aggs => {
            map { $_ => { terms => { field => $_ eq 'restricted' ? $_ : "${_}.facet", size => 50 } } } @FACET_FIELDS
        },
    };

    return $body;
}

=head2 _build_sort

Translates an _order_by string like "-surname" or "+ext_attr_DEPT" into ES sort.

=cut

sub _build_sort {
    my ( $self, $order_by ) = @_;

    my @sort;
    for my $field ( split /,/, $order_by ) {
        $field =~ s/^\s+|\s+$//g;
        next unless $field;

        my $direction = 'asc';
        if ( $field =~ s/^-// ) {
            $direction = 'desc';
        } elsif ( $field =~ s/^\+// ) {
            $direction = 'asc';
        }

        # Use the .sort sub-field for sortable fields
        my $sort_field = "${field}.sort";
        push @sort, { $sort_field => { order => $direction, unmapped_type => 'long' } };
    }

    return \@sort;
}

1;
