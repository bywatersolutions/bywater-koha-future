#!/usr/bin/perl

# Copyright 2009-2010 Kyle Hall
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

BEGIN {

    # find Koha's Perl modules
    # test carefully before changing this
    use FindBin;
    eval { require "$FindBin::Bin/../kohalib.pl" };
}

use Getopt::Long;
use Pod::Usage;
use Net::Printer;

use C4::Context;
use C4::Members qw(GetMember);
use C4::Letters qw(GetPreparedLetter);
use Koha::Database;

my $help    = 0;
my $test    = 0;
my $verbose = 0;
my @printers;
GetOptions(
    "help|?"      => \$help,
    "verbose|v"   => \$verbose,
    "test|t"      => \$test,
    "printer|p=s" => \@printers,
);
pod2usage(1) if $help;
pod2usage(1) unless @printers;

my $schema = Koha::Database->new()->schema();

my %printers;
foreach my $p (@printers) {
    my ( $branchcode, $printer_id ) = split( /:/, $p );
    $printers{$branchcode} = $schema->resultset('Printer')->find($printer_id);
}

my $dbh   = C4::Context->dbh;
my $query = "SELECT * FROM reserves WHERE printed IS NULL";
my $sth   = $dbh->prepare($query);
$sth->execute();

my $set_printed_query = "
    UPDATE reserves
    SET printed = NOW()
    WHERE reserve_id = ?
";
my $set_printed_sth = $dbh->prepare($set_printed_query);

while ( my $hold = $sth->fetchrow_hashref() ) {
    if ($verbose) {
        say "\nFound Notice to Print";
        say "Borrowernumber: " . $hold->{'borrowernumber'};
        say "Biblionumber: " . $hold->{'biblionumber'};
        say "Branch: " . $hold->{'branchcode'};
    }

    my $borrower =
      C4::Members::GetMember( 'borrowernumber' => $hold->{'borrowernumber'} );

    my $letter = GetPreparedLetter(
        module      => 'reserves',
        letter_code => 'HOLD_PLACED_PRINT',
        branchcode  => $hold->{branchcode},
        tables      => {
            'branches'    => $hold->{'branchcode'},
            'biblio'      => $hold->{'biblionumber'},
            'biblioitems' => $hold->{'biblionumber'},
            'items'       => $hold->{'itemnumber'},
            'borrowers'   => $borrower,
            'reserves'    => $hold,
        }
    );

    if ( defined( $printers{ $hold->{branchcode} } ) ) {
        unless ($test) {
            my ( $success, $error ) = $printers{ $hold->{'branchcode'} }->print(
                {
                    data    => $letter->{content},
                    is_html => $letter->{is_html},
                }
            );

            if ($success) {
                $set_printed_sth->execute( $hold->{'reserve_id'} );
            }
            else {
                warn "ERROR: $error";
            }
        }
        else {
            say "TEST MODE, notice will not be printed";
            say $letter->{'content'};
        }
    }
    else {
        say "WARNING: No printer defined for branchcode "
          . $hold->{'branchcode'}
          if ($verbose);
    }

}

__END__

=head1 NAME

Print Holds

=head1 SYNOPSIS

print_holds.pl --printer <branchcode>=<printer_id>

=head1 OPTIONS

=over 8

=item B<--help>

Print a brief help message and exits.

=item B<--printer>

Adds a printer to use in the format BRANCHCODE=PRINTER_ID.

e.g. print_holds.pl --printer MPL:1 --printer CPL:2

would add printers for branchcodes MPL and CPL. If a printer is not defined for a given branch, notices for
that branch will not be printed.

=head1 DESCRIPTION

B<This program> will print on-demand notices for items in the holds queue as they appear.

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

=cut
