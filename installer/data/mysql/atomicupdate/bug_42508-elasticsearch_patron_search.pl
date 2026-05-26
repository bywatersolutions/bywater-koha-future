use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info say_failure);

return {
    bug_number  => "42508",
    description => "Add system preferences for Elasticsearch patron search",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        my %prefs = (
            ElasticsearchPatronSearch          => '0',
            ElasticsearchIndexStatus_patrons   => '0',
            ElasticsearchPatronMaxResultWindow => '1000000',
        );

        for my $pref ( sort keys %prefs ) {
            my $rv = $dbh->do(
                q{INSERT IGNORE INTO systempreferences (variable, value) VALUES (?, ?)},
                undef, $pref, $prefs{$pref},
            );

            if ( !defined $rv ) {
                say_failure( $out, "Failed to add system preference '$pref': " . $dbh->errstr );
            } elsif ( $rv > 0 ) {
                say_success( $out, "Added new system preference '$pref'" );
            } else {
                say_info( $out, "System preference '$pref' already exists, skipping" );
            }
        }
    },
};
