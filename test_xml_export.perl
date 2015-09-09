#!/usr/bin/perl
#test_xml_export.perl - created Mon Mar 20 15:33:55 2006
 
use strict;
use warnings;
 
#Purposes of this file are:
#1) To provide an initial test for XML export which will be needed for web services.
#2) See if I can export the queries to XML and read from there

#Connect to DB
use DBI;
use DBD::AnyData;
use Data::Dumper;

#Massive kludge for DBD::AnyData
if(DBD::AnyData->VERSION eq '0.08')
{ eval
  '
    package DBD::AnyData::st;
    no warnings;

    sub DESTROY ($) { $_[0]->SUPER::DESTROY(@_) }
    sub finish ($) { $_[0]->SUPER::finish(@_) }
  ';
}

use XML::Simple;


my $dbh = DBI->connect("dbi:Pg:dbname=egtdc_admin_dev", undef, undef, {AutoCommit => 0, RaiseError => 1});

my $xmldbh = DBI->connect('dbi:AnyData:(RaiseError=>1)');

# $xmldbh->func(
#              'query_def',
#              'DBI',
# 	     $dbh,
#          'ad_import');

# print Dumper($xmldbh->selectall_hashref("select * from query_def", "query_id"));

#print $xmldbh->errstr(), "\n";

# print $xmldbh->func( 'query_def', 'XML', 'ad_export');

my $queryhash = $dbh->selectall_hashref("select * from query_def", "query_id");

my $queryarray = [values %$queryhash];

print XMLout($queryarray);
print "\n";

$dbh->disconnect();
