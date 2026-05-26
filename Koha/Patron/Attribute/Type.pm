package Koha::Patron::Attribute::Type;

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

use Koha::Database;
use Koha::Exceptions::Patron::Attribute::Type;

use base qw(Koha::Object Koha::Object::Limit::Library);

=head1 NAME

Koha::Patron::Attribute::Type - Koha::Patron::Attribute::Type Object class

=head1 API

=head2 Class Methods

=cut

=head3 store

    my $attribute = Koha::Patron::Attribute->new({ code => 'a_code', ... });
    try { $attribute->store }
    catch { handle_exception };

=cut

sub store {

    my $self = shift;

    $self->check_repeatables;
    $self->check_unique_ids;

    return $self->SUPER::store();
}

=head3 delete

    $attribute_type->delete;

Deletes the attribute type. Deleting a type cascades in the database and removes
every C<borrower_attributes> row for this code. Those values are also mirrored in
the patron search index (as C<ext_attr_E<lt>codeE<gt>> fields), so the affected
patrons are reindexed after the deletion to purge the now-removed values.

=cut

sub delete {
    my ($self) = @_;

    # Capture affected patrons before the cascade removes the attribute rows.
    my %seen;
    my @patron_ids = grep { !$seen{$_}++ } $self->attributes->_resultset->get_column('borrowernumber')->all;

    my $result = $self->SUPER::delete;

    if (@patron_ids) {
        require Koha::BackgroundJob::UpdateElasticPatronIndex;
        Koha::BackgroundJob::UpdateElasticPatronIndex->new->enqueue( { patron_ids => \@patron_ids } );
    }

    return $result;
}

=head3 attributes

=cut

sub attributes {
    my ($self) = @_;
    my $attributes_rs = $self->_result->borrower_attributes;
    Koha::Patron::Attributes->_new_from_dbic($attributes_rs);
}

=head2 Internal Methods

=cut

=head3 check_repeatables

=cut

sub check_repeatables {
    my ($self) = @_;

    return $self if $self->repeatable;

    my $count = $self->attributes->search(
        {},
        {
            select   => [ { count => 'id', '-as' => 'c' } ],
            group_by => 'borrowernumber',
            having   => { c => { '>' => 1 } }
        }
    )->count;

    Koha::Exceptions::Patron::Attribute::Type::CannotChangeProperty->throw( property => 'repeatable' )
        if $count;

    return $self;
}

=head3 check_unique_ids

=cut

sub check_unique_ids {
    my ($self) = @_;

    return $self unless $self->unique_id;

    my $count = $self->attributes->search(
        {},
        {
            select   => [ { count => 'id', '-as' => 'c' } ],
            group_by => 'attribute',
            having   => { c => { '>' => 1 } }
        }
    )->count;

    Koha::Exceptions::Patron::Attribute::Type::CannotChangeProperty->throw( property => 'unique_id' )
        if $count;

    return $self;
}

=head3 _type

=cut

sub _type {
    return 'BorrowerAttributeType';
}

=head3 _library_limits

=cut

sub _library_limits {
    return {
        class   => 'BorrowerAttributeTypesBranch',
        id      => 'bat_code',
        library => 'b_branchcode'
    };
}

1;
