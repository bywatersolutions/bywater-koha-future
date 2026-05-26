package Koha::Exceptions::SearchEngine::Indexer;

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

    'Koha::Exceptions::SearchEngine::Indexer' => {
        isa => 'Koha::Exception',
    },
    'Koha::Exceptions::SearchEngine::Indexer::IndexingError' => {
        isa         => 'Koha::Exceptions::SearchEngine::Indexer',
        description => 'The search engine failed to index one or more records',
        fields      => ['record_ids'],
    },
    'Koha::Exceptions::SearchEngine::Indexer::DeletionError' => {
        isa         => 'Koha::Exceptions::SearchEngine::Indexer',
        description => 'The search engine failed to delete one or more records',
        fields      => ['record_ids'],
    },
);

=head1 NAME

Koha::Exceptions::SearchEngine::Indexer - Backend-neutral search engine indexer exceptions

=head1 DESCRIPTION

These exceptions are raised by patron (and, in general, record) indexer backends
regardless of the underlying implementation (Elasticsearch, database, ...). Code that
enqueues or performs indexing/deletion operations can catch these to react to a failure
(for instance, re-enqueueing the affected records) without depending on a specific
search engine.

=head1 Exceptions

=head2 Koha::Exceptions::SearchEngine::Indexer

Generic search engine indexer exception.

=head2 Koha::Exceptions::SearchEngine::Indexer::IndexingError

Raised when the backend fails to index one or more records. The affected identifiers
are available through the C<record_ids> accessor.

=head2 Koha::Exceptions::SearchEngine::Indexer::DeletionError

Raised when the backend fails to remove one or more records from the index. The affected
identifiers are available through the C<record_ids> accessor.

=cut

1;
