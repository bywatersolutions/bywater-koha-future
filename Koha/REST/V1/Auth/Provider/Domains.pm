package Koha::REST::V1::Auth::Provider::Domains;

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

use Mojo::Base 'Mojolicious::Controller';

use Koha::Auth::Provider::Domains;
use Koha::Auth::Providers;

use Koha::Database;

use Scalar::Util qw(blessed);
use Try::Tiny;

=head1 NAME

Koha::REST::V1::Auth::Provider::Domains - Controller library for handling
authentication provider domains routes.

=head2 Operations

=head3 list

Controller method for listing authentication provider domains.

=cut

sub list {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $auth_provider_id = $c->validation->param('auth_provider_id');
        my $provider         = Koha::Auth::Providers->find($auth_provider_id);

        unless ($provider) {
            return $c->render(
                status  => 404,
                openapi => {
                    error      => 'Object not found',
                    error_code => 'not_found',
                }
            );
        }

        my $domains_rs = $provider->domains;
        return $c->render(
            status  => 200,
            openapi => $c->objects->search($domains_rs)
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 get

Controller method for retrieving an authentication provider domain.

=cut

sub get {
    my $c = shift->openapi->valid_input or return;

    return try {

        my $auth_provider_id = $c->validation->param('auth_provider_id');
        my $provider         = Koha::Auth::Providers->find($auth_provider_id);

        unless ($provider) {
            return $c->render(
                status  => 404,
                openapi => {
                    error      => 'Object not found',
                    error_code => 'not_found',
                }
            );
        }

        my $domains_rs = $provider->domains;

        my $auth_provider_domain_id = $c->validation->param('auth_provider_domain_id');
        my $domain                  = $c->objects->find( $domains_rs, $auth_provider_domain_id );

        unless ($domain) {
            return $c->render(
                status  => 404,
                openapi => {
                    error      => 'Object not found',
                    error_code => 'not_found',
                }
            );
        }

        return $c->render( status => 200, openapi => $domain );
    } catch {
        $c->unhandled_exception($_);
    }
}

=head3 add

Controller method for adding an authentication provider.

=cut

sub add {
    my $c = shift->openapi->valid_input or return;

    return try {

        Koha::Database->new->schema->txn_do(
            sub {
                my $domain = Koha::Auth::Provider::Domain->new_from_api( $c->validation->param('body') );
                $domain->store;

                $c->res->headers->location( $c->req->url->to_string . '/' . $domain->id );
                return $c->render(
                    status  => 201,
                    openapi => $domain->to_api
                );
            }
        );
    } catch {
        if ( blessed($_) and $_->isa('Koha::Exceptions::Object::FKConstraint') ) {
            return $c->render(
                status  => 404,
                openapi => {
                    error      => 'Object not found',
                    error_code => 'not_found',
                }
            );
        }

        $c->unhandled_exception($_);
    };
}

=head3 update

Controller method for updating an authentication provider domain.

=cut

sub update {
    my $c = shift->openapi->valid_input or return;

    my $auth_provider_id        = $c->validation->param('auth_provider_id');
    my $auth_provider_domain_id = $c->validation->param('auth_provider_domain_id');

    my $domain = Koha::Auth::Provider::Domains->find(
        { auth_provider_id => $auth_provider_id, auth_provider_domain_id => $auth_provider_domain_id } );

    unless ($domain) {
        return $c->render(
            status  => 404,
            openapi => {
                error      => 'Object not found',
                error_code => 'not_found',
            }
        );
    }

    return try {

        Koha::Database->new->schema->txn_do(
            sub {

                $domain->set_from_api( $c->validation->param('body') );
                $domain->store->discard_changes;

                return $c->render(
                    status  => 200,
                    openapi => $domain->to_api
                );
            }
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 delete

Controller method for deleting an authentication provider.

=cut

sub delete {
    my $c = shift->openapi->valid_input or return;

    my $auth_provider_id        = $c->validation->param('auth_provider_id');
    my $auth_provider_domain_id = $c->validation->param('auth_provider_domain_id');

    my $domain = Koha::Auth::Provider::Domains->find(
        { auth_provider_id => $auth_provider_id, auth_provider_domain_id => $auth_provider_domain_id } );

    unless ($domain) {
        return $c->render(
            status  => 404,
            openapi => {
                error      => 'Object not found',
                error_code => 'not_found',
            }
        );
    }

    return try {
        $domain->delete;
        return $c->render(
            status  => 204,
            openapi => q{}
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

1;
