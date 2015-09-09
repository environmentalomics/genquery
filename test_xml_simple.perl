#!/usr/bin/perl
#test_xml_simple.perl - created Thu Jun  1 15:32:25 2006
 
use strict;
use warnings;
 
use XML::Simple qw(:strict);
use Data::Dumper;

my @keyattrs = qw(id name);
my @arrays = qw(db_connection query_category query_definition query_param prompt);
my $xs = new XML::Simple(ForceArray => \@arrays, KeepRoot => 0, KeyAttr => \@keyattrs, SuppressEmpty => undef );

my $ref = $xs->xml_in('genquery_conf.xml');

print Dumper($ref);
