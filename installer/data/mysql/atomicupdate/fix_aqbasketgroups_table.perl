$DBversion = 'XXX';
if( CheckVersion( $DBversion ) ) {

    if( !column_exists( 'aqbasketgroups', 'deliveryplace' ) ) {
        $dbh->do( "ALTER TABLE aqbasketgroups ADD COLUMN deliveryplace varchar(10) COLLATE utf8mb4_unicode_ci DEFAULT NULL AFTER booksellerid" );
        print "Added deliveryplace to aqbasketgroups\n";
    }
    if( !column_exists( 'aqbasketgroups', 'freedeliveryplace' ) ) {
        $dbh->do( "ALTER TABLE aqbasketgroups ADD COLUMN freedeliveryplace mediumtext COLLATE utf8mb4_unicode_ci AFTER deliveryplace" );
        print "Added freedeliveryplace to aqbasketgroups\n";
    }
    if( !column_exists( 'aqbasketgroups', 'deliverycomment' ) ) {
        $dbh->do( "ALTER TABLE aqbasketgroups ADD COLUMN deliverycomment varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL AFTER freedeliveryplace" );
        print "Added deliverycomment to aqbasketgroups\n";
    }
    if( !column_exists( 'aqbasketgroups', 'billingplace' ) ) {
        $dbh->do( "ALTER TABLE aqbasketgroups ADD COLUMN billingplace varchar(10) COLLATE utf8mb4_unicode_ci DEFAULT NULL AFTER deliverycomment" );
        print "Added billingplace to aqbasketgroups\n";
    }

    NewVersion( $DBversion, 00000, "ByWater Fix AcqBasketGroups table");
}
