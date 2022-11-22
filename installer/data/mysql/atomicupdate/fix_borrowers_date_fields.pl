use Modern::Perl;

return {
    bug_number => "XXX",
    description => q{Set borrower date fields to NULL if the value is "0000-00-00"},
    up => sub {
        my ($args) = @_;
        my ($dbh, $out) = @$args{qw(dbh out)};
        $dbh->do(q{UPDATE borrowers SET dateofbirth = NULL WHERE dateofbirth = "0000-00-00"});
        $dbh->do(q{UPDATE borrowers SET dateenrolled = NULL WHERE dateenrolled = "0000-00-00"});
        $dbh->do(q{UPDATE borrowers SET dateexpiry = NULL WHERE dateexpiry = "0000-00-00"});
        $dbh->do(q{UPDATE borrowers SET password_expiration_date = NULL WHERE password_expiration_date = "0000-00-00"});
        $dbh->do(q{UPDATE borrowers SET date_renewed = NULL WHERE date_renewed = "0000-00-00"});
        $dbh->do(q{UPDATE borrowers SET debarred = NULL WHERE debarred = "0000-00-00"});
    },
};
