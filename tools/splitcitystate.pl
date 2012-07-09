#!/usr/bin/perl -w

# possible modules to use
use C4::Context;
use C4::Items;
use C4::Biblio;
use C4::Members;
use MARC::Field;
my $i = 0;


my $dbh = C4::Context->dbh();
my $sth = $dbh->prepare("UPDATE borrowers set city = ? where borrowernumber = ?");
my $sth2 = $dbh->prepare("UPDATE borrowers set state = ? where borrowernumber = ?");

while ( my $inp = <STDIN> ) {
chomp $inp;
my ($bornum,$city,$state) = split(/\,/, $inp);


$sth->execute($city, $bornum);
$sth2->execute($state, $bornum);

}
