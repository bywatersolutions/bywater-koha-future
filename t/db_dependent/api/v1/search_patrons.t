#!/usr/bin/env perl

# Tests for /api/v1/search/patrons

use Modern::Perl;

use Test::NoWarnings;
use Test::More tests => 5;
use Test::MockModule;
use Test::Mojo;

use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

my $t = Test::Mojo->new('Koha::REST::V1');
t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

subtest 'search - syspref disabled' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    t::lib::Mocks::mock_preference( 'ElasticsearchPatronSearch', 0 );

    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 2**4 }    # borrowers flag
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    $t->get_ok("//$userid:$password\@/api/v1/search/patrons?q=smith")
        ->status_is( 400, 'Returns 400 when syspref disabled' );

    $schema->storage->txn_rollback;
};

subtest 'search - syspref enabled' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    t::lib::Mocks::mock_preference( 'ElasticsearchPatronSearch', 1 );

    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 2**4 }
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    # Mock the ES search to return the librarian's ID
    my $search_mock = Test::MockModule->new('Koha::SearchEngine::Elasticsearch::Search::Patrons');
    $search_mock->mock(
        'new',
        sub {
            return bless { index => 'patrons', index_name => 'koha_patrons' }, $_[0];
        }
    );
    $search_mock->mock(
        'search_patrons',
        sub {
            return {
                total  => 1,
                hits   => [ $librarian->borrowernumber ],
                facets => {
                    library_id  => [ { value => $librarian->branchcode,   count => 1 } ],
                    category_id => [ { value => $librarian->categorycode, count => 1 } ],
                },
            };
        }
    );

    $t->get_ok("//$userid:$password\@/api/v1/search/patrons?q=test")
        ->status_is(200)
        ->json_is( '/total',            1 )
        ->json_is( '/hits/0/patron_id', $librarian->borrowernumber );

    $schema->storage->txn_rollback;
};

subtest 'search - unauthorized (401)' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    t::lib::Mocks::mock_preference( 'ElasticsearchPatronSearch', 1 );

    # No credentials supplied
    $t->get_ok("/api/v1/search/patrons?q=smith")->status_is( 401, 'Anonymous request is rejected with 401' );

    $schema->storage->txn_rollback;
};

subtest 'search - forbidden (403)' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    t::lib::Mocks::mock_preference( 'ElasticsearchPatronSearch', 1 );

    # A patron with no relevant permissions (flags => 0)
    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );
    my $password = 'thePassword123';
    $patron->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $patron->userid;

    $t->get_ok("//$userid:$password\@/api/v1/search/patrons?q=smith")
        ->status_is( 403, 'Request without list_borrowers permission is rejected with 403' );

    $schema->storage->txn_rollback;
};
