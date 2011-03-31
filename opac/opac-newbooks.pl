#!/usr/bin/perl

use strict;
use warnings;

use CGI;

use C4::Context;
use C4::Auth;
use C4::Biblio;
use C4::Output;
use C4::Koha;

my $dbh   = C4::Context->dbh;

my $input = CGI->new();

my ( $template, $borrowernumber, $cookie ) = get_template_and_user(
    {
        template_name   => "opac-bibdetails.tmpl",
        type            => "opac",
        query           => $input,
        authnotrequired => 1,
        flagsrequired   => { borrow => 1 },
    }
);

my $query = q/SELECT biblionumber
FROM items
WHERE itemcallnumber LIKE 'NEW %'
OR location = 'NEW'
ORDER BY RAND()
LIMIT 6/;

my $sth = $dbh->prepare($query);
$sth->execute();

my @bibs = ();
my $marcflavour = C4::Context->preference('marcflavour');
while (my ($biblionumber) = $sth->fetchrow_array) {
    my $bib_details = GetBiblioData($biblionumber);
    # some useful variables for enhanced content;
    # in each case, we're grabbing the first value we find in
    # the record and normalizing it
    my $record = GetMarcBiblio($biblionumber);
    $bib_details->{normalized_upc} = GetNormalizedUPC($record,$marcflavour);
    $bib_details->{normalized_ean} = GetNormalizedEAN($record,$marcflavour);
    $bib_details->{normalized_oclc} = GetNormalizedOCLCNumber($record,$marcflavour);
    $bib_details->{normalized_isbn} = GetNormalizedISBN(undef,$record,$marcflavour);
    $bib_details->{content_identifier_exists} = 1;
    push @bibs, $bib_details;
}
$template->param(bibs => \@bibs);

output_html_with_http_headers $input, $cookie, $template->output;
