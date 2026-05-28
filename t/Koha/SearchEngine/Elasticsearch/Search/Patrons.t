#!/usr/bin/env perl

# Tests for Koha::SearchEngine::Elasticsearch::Search::Patrons

use Modern::Perl;

use Test::NoWarnings;
use Test::More tests => 6;
use Test::MockModule;
use Test::MockObject;
use Test::Exception;

use t::lib::Mocks;

# Mock the ES base class so we don't need a real connection
my $es_base_mock = Test::MockModule->new('Koha::SearchEngine::Elasticsearch');
$es_base_mock->mock(
    'new',
    sub {
        my ( $class, $params ) = @_;
        return bless {
            index      => $params->{index},
            index_name => 'koha_' . $params->{index},
        }, $class;
    }
);

my $es_search_mock = Test::MockModule->new('Koha::SearchEngine::Elasticsearch::Search');
$es_search_mock->mock(
    'new',
    sub {
        my ( $class, $params ) = @_;
        return bless {
            index      => $params->{index},
            index_name => 'koha_' . $params->{index},
        }, $class;
    }
);

use_ok('Koha::SearchEngine::Elasticsearch::Search::Patrons');

subtest '_build_query' => sub {
    plan tests => 5;

    my $searcher = bless { index => 'patrons', index_name => 'koha_patrons' },
        'Koha::SearchEngine::Elasticsearch::Search::Patrons';

    # Basic query with no filters (default match = contains)
    my $body = $searcher->_build_query(
        query_string         => 'smith',
        search_fields        => [qw( patron_name surname cardnumber )],
        filters              => {},
        restricted_libraries => [],
    );

    # must is an array with the main query clause
    my $must = $body->{query}{bool}{must};
    ok( ref $must eq 'ARRAY' && @$must > 0, 'must clause is a non-empty array' );
    is_deeply( $body->{query}{bool}{filter}, [], 'no filters when none provided' );

    # With facet filter
    $body = $searcher->_build_query(
        query_string         => 'john',
        search_fields        => [qw( patron_name )],
        filters              => { library_id => 'CPL', category_id => 'PT' },
        restricted_libraries => [],
    );

    is( scalar @{ $body->{query}{bool}{filter} }, 2, 'two filter clauses for two facets' );

    # Aggregations present
    ok( exists $body->{aggs}{library_id},  'library_id aggregation present' );
    ok( exists $body->{aggs}{category_id}, 'category_id aggregation present' );
};

subtest '_build_sort' => sub {
    plan tests => 4;

    my $searcher = bless { index => 'patrons', index_name => 'koha_patrons' },
        'Koha::SearchEngine::Elasticsearch::Search::Patrons';

    my $sort = $searcher->_build_sort('-surname');
    is( $sort->[0]{'surname.sort'}{order}, 'desc', 'descending with - prefix' );

    $sort = $searcher->_build_sort('+firstname');
    is( $sort->[0]{'firstname.sort'}{order}, 'asc', 'ascending with + prefix' );

    $sort = $searcher->_build_sort('cardnumber');
    is( $sort->[0]{'cardnumber.sort'}{order}, 'asc', 'ascending by default (no prefix)' );

    $sort = $searcher->_build_sort('-ext_attr_DEPT');
    is( $sort->[0]{'ext_attr_DEPT.sort'}{order}, 'desc', 'extended attribute sort field' );
};

subtest 'library scoping via restricted_libraries' => sub {
    plan tests => 3;

    my $searcher = bless { index => 'patrons', index_name => 'koha_patrons' },
        'Koha::SearchEngine::Elasticsearch::Search::Patrons';

    my $body = $searcher->_build_query(
        query_string         => 'smith',
        search_fields        => [qw( patron_name )],
        filters              => {},
        restricted_libraries => [ 'CPL', 'MPL' ],
    );

    my ($scope) = grep { $_->{terms} && $_->{terms}{'library_id.facet'} } @{ $body->{query}{bool}{filter} };
    ok( $scope, 'restricted_libraries adds a library_id.facet terms filter' );
    is_deeply(
        $scope->{terms}{'library_id.facet'},
        [ 'CPL', 'MPL' ],
        'scoping filter contains exactly the caller-visible libraries'
    );

    $body = $searcher->_build_query(
        query_string         => 'smith',
        search_fields        => [qw( patron_name )],
        filters              => {},
        restricted_libraries => [],
    );
    my ($no_scope) = grep { $_->{terms} && $_->{terms}{'library_id.facet'} } @{ $body->{query}{bool}{filter} };
    ok( !$no_scope, 'no scoping filter when caller can see all libraries' );
};

subtest '_assert_searchable rejects non-searchable fields' => sub {
    plan tests => 4;

    my $searcher = bless { index => 'patrons', index_name => 'koha_patrons' },
        'Koha::SearchEngine::Elasticsearch::Search::Patrons';

    my %allowed = ( surname => 1, cardnumber => 1, ext_attr_PUBLIC => 1 );

    lives_ok { $searcher->_assert_searchable( \%allowed, qw( surname cardnumber ) ) }
    'allowed fields pass validation';

    lives_ok { $searcher->_assert_searchable( \%allowed, '-surname', 'ext_attr_PUBLIC' ) }
    'sort markers and allowed ext_attr pass validation';

    throws_ok { $searcher->_assert_searchable( \%allowed, 'ext_attr_SECRET' ) }
    'Koha::Exceptions::SearchEngine::Search::InvalidQuery',
        'a non-searchable field is rejected';

    my $e;
    eval { $searcher->_assert_searchable( \%allowed, 'userid:opac_notes' ) };
    $e = $@;
    is_deeply(
        [ sort @{ $e->invalid_fields } ],
        [ 'opac_notes', 'userid' ],
        'composite colon key is split and all non-searchable parts reported'
    );
};
