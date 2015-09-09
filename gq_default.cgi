#!/usr/bin/perl 
use strict; use warnings;

#The stub CGI application.  Locations need to be set here explicitly to
#bootstrap finding the config file and modules.

our $conf = '/etc/genquery/genquery_conf.xml';

BEGIN { if($ENV{REQUEST_METHOD}){
    require CGI::Carp; import CGI::Carp qw(fatalsToBrowser);
} };

#This is only needed as a debugging hook.
# my $error_handler = sub {
#     shift;
#     die "@_";
# };
my $error_handler = undef;

#Point GenQuery to the appropriate configuration file.
our $params = {
	config_file => $conf,
	error_handler => $error_handler,
};

use GenQuery::WebQuery;
our $cgiapp = GenQuery::WebQuery->new(PARAMS => $params);

## Uncomment this if you want to use gq_rerun.perl.  This is designed to be run from the command line and
## possibly under the debugger - ie.
## % perl -d /usr/lib/cgi-bin/genquery/gq_rerun.perl
#
# $cgiapp->savetofile("/tmp/last_gq_run.out", $conf);

$cgiapp->run();
