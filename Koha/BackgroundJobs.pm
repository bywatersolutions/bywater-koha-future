package Koha::BackgroundJobs;

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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use base qw(Koha::Objects);
use Koha::BackgroundJob;

=head1 NAME

Koha::BackgroundJobs - Koha BackgroundJob Object set class

=head1 API

=head2 Class Methods

=cut

sub filter_by_current {
    my ($self) = @_;

    return $self->search(
        {
            status => { not_in => [ 'cancelled', 'failed', 'finished' ] }
        }
    );
}

=head3 purge

    my $params = { job_types => ('all') , # Arrayref of jobtypes to be purged
                   days      => 1,        # Age in days of jobs to be purged
                   confirm   => 1,        # Confirm deletion
                };
    my $count = Koha::BackgroundJobs->purge( $params );

Deletes finished background jobs. Returns the number of jobs that was / would've been deleted.

=cut

sub purge {
    my ( $self, $params) = @_;

    return 0 unless ( exists $params->{job_types} && scalar @{ $params->{job_types} }  >= 1 );
    return 0 unless ( exists $params->{days} );

    my $types = $params->{job_types};
    my $days  = $params->{days};

    my $confirm = exists $params->{confirm} ? $params->{confirm} : 0;

    my $rs;
    if ( $types->[0] eq 'all' ){
        $rs = $self->search(
            {
                ended_on => { '<' => \[ 'date_sub(curdate(), INTERVAL ? DAY)', $days ] },
                status   => 'finished',
            });

    } else {
        $rs = $self->search(
            {
                ended_on => { '<' => \[ 'date_sub(curdate(), INTERVAL ? DAY)', $days ] },
                type     => $types,
                status   => 'finished',
            });
    }
    my $count = $rs->count();
    $rs->delete if $confirm;

    return $count;
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'BackgroundJob';
}

=head3 object_class

=cut

sub object_class {
    return 'Koha::BackgroundJob';
}

1;
