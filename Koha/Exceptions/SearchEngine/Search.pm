package Koha::Exceptions::SearchEngine::Search;

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

use Koha::Exception;

use Exception::Class (

    'Koha::Exceptions::SearchEngine::Search' => {
        isa => 'Koha::Exception',
    },
    'Koha::Exceptions::SearchEngine::Search::InvalidQuery' => {
        isa         => 'Koha::Exceptions::SearchEngine::Search',
        description => 'The search request was invalid',
        fields      => ['invalid_fields'],
    },
);

=head1 NAME

Koha::Exceptions::SearchEngine::Search - Backend-neutral search exceptions

=head1 DESCRIPTION

Exceptions raised while building or running a patron (or, in general, record)
search, regardless of the underlying backend (Elasticsearch, database, ...).
Controllers can map these to a documented HTTP 400 response rather than leaking
an internal 500.

=head1 Exceptions

=head2 Koha::Exceptions::SearchEngine::Search

Generic search exception.

=head2 Koha::Exceptions::SearchEngine::Search::InvalidQuery

Raised when a request references fields that are not part of the resolved
searchable set, or is otherwise malformed. The offending field names, when
known, are available through the C<invalid_fields> accessor.

=cut

1;
