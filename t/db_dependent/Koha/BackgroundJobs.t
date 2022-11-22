#!/usr/bin/perl

# Copyright 2020 Koha Development team
#
# This file is part of Koha
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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 13;
use Test::MockModule;

use Koha::Database;
use Koha::BackgroundJobs;
use Koha::DateUtils qw( dt_from_string );

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::lib::Dates;
use t::lib::Koha::BackgroundJob::BatchTest;

my $schema = Koha::Database->new->schema;
$schema->storage->txn_begin;

t::lib::Mocks::mock_userenv;

my $net_stomp = Test::MockModule->new('Net::Stomp');
$net_stomp->mock( 'send_with_receipt', sub { return 1 } );

my $builder = t::lib::TestBuilder->new;

my $background_job_module = Test::MockModule->new('Koha::BackgroundJob');
$background_job_module->mock(
    'type_to_class_mapping',
    sub {
        return { batch_test => 't::lib::Koha::BackgroundJob::BatchTest' };
    }
);

my $data     = { a => 'aaa', b => 'bbb' };
my $job_size = 10;
my $job_id   = t::lib::Koha::BackgroundJob::BatchTest->new->enqueue(
    {
        size => $job_size,
        %$data
    }
);

# Enqueuing a new job
my $new_job = Koha::BackgroundJobs->find($job_id);
ok( $new_job, 'New job correctly enqueued' );
is_deeply( $new_job->json->decode( $new_job->data ),
    $data, 'data retrieved and json encoded correctly' );
is( t::lib::Dates::compare( $new_job->enqueued_on, dt_from_string ),
    0, 'enqueued_on correctly filled with now()' );
is( $new_job->size,   $job_size,    'job size retrieved correctly' );
is( $new_job->status, "new",        'job has not started yet, status is new' );
is( $new_job->type,   "batch_test", 'job type retrieved from ->job_type' );

# FIXME: This behavior doesn't seem correct. It shouldn't be the background job's
#        responsibility to return 'undef'. Some higher-level check should raise a
#        proper exception.
# Test cancelled job
$new_job->status('cancelled')->store;
my $processed_job = $new_job->process;
is( $processed_job, undef );
$new_job->discard_changes;
is( $new_job->status, "cancelled", "A cancelled job has not been processed" );

# Test new job to process
$new_job->status('new')->store;
$new_job = $new_job->process;
is( $new_job->status,             "finished", 'job is new finished!' );
is( scalar( @{ $new_job->messages } ), 10,    '10 messages generated' );
is_deeply(
    $new_job->report,
    { total_records => 10, total_success => 10 },
    'Correct number of records processed'
);

is_deeply( $new_job->additional_report(), {} );

$schema->storage->txn_rollback;


subtest 'purge' => sub {
    plan tests => 9;
    $schema->storage->txn_begin;

    my $recent_date = dt_from_string;
    my $old_date = dt_from_string->subtract({ days => 3 });
    my $job_recent_t1_new      = $builder->build_object( { class => 'Koha::BackgroundJobs', value => { status => 'new', ended_on => $old_date, type => 'type1' } } );
    my $job_recent_t2_fin = $builder->build_object( { class => 'Koha::BackgroundJobs', value => { status => 'finished', ended_on => $recent_date, type => 'type2' } } );
    my $job_old_t1_fin    = $builder->build_object( { class => 'Koha::BackgroundJobs', value => { status => 'finished', ended_on => $old_date, type => 'type1' } } );
    my $job_old_t2_fin  = $builder->build_object( { class => 'Koha::BackgroundJobs', value => { status => 'finished', ended_on => $old_date, type => 'type2' } } );

    my $params = { job_types => ['type1'] , # Arrayref of jobtypes to be purged
                   days      => 1,        # Age in days of jobs to be purged
                   confirm   => 0,        # Confirm deletion
                };
    is( Koha::BackgroundJobs->purge($params), 1, 'Only the old finished type1 job would be purged' );

    $params->{'job_types'} = ['all'];
    is( Koha::BackgroundJobs->purge($params), 2, 'All finished old jobs would be purged with job_types = all' );

    my $rs = Koha::BackgroundJobs->search(
        {
            id => [ $job_recent_t1_new->id, $job_recent_t2_fin->id, $job_old_t1_fin->id, $job_old_t2_fin->id ]
        }
    );
    is( $rs->count, 4, 'All jobs still left in queue');

    $params->{'job_types'} = ['type1'];
    $params->{'confirm'} = 1;
    is( Koha::BackgroundJobs->purge($params), 1, 'Only the old finished type1 job is purged' );

    $rs = Koha::BackgroundJobs->search(
        {
            id => [ $job_recent_t1_new->id, $job_recent_t2_fin->id, $job_old_t1_fin->id, $job_old_t2_fin->id ]
        }
    );
    is( $rs->count, 3, '3 jobs still left in queue');

    $params->{'job_types'} = ['all'];
    is( Koha::BackgroundJobs->purge($params), 1, 'The remaining old finished jobs is purged' );
        $rs = Koha::BackgroundJobs->search(
        {
            id => [ $job_recent_t1_new->id, $job_recent_t2_fin->id, $job_old_t1_fin->id, $job_old_t2_fin->id ]
        }
    );
    is( $rs->count, 2, '2 jobs still left in queue');

    $rs = Koha::BackgroundJobs->search(
        {
            id => [ $job_recent_t1_new->id ]
        }
    );
    is( $rs->count, 1, 'Unfinished job still left in queue');

    $rs = Koha::BackgroundJobs->search(
        {
            id => [ $job_recent_t2_fin->id ]
        }
    );
    is( $rs->count, 1, 'Recent finished job still left in queue');

    $schema->storage->txn_rollback;

};
