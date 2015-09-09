#!/usr/bin/perl 
use strict;
use warnings;
use diagnostics;

#Test harness picks up the last run details and runs again.
#This gives me some hope of debugging the code.

use lib '/home/tbooth/sandbox/genquery/new';

#    require CGI::Carp; import CGI::Carp qw(fatalsToBrowser);
use IO::File;
use Data::Dumper;
use Carp;
$Carp::Verbose = 1;

use GenQuery::WebQuery;
use CGI;

my $query = new CGI(new IO::File($ARGV[0] || "/tmp/last_gq_run.out"));
my $conf = $query->param('last_gq_run_config') or die "No last_gq_run_config found in /tmp/last_gq_run.out";

my $error_handler = sub {
    shift;
    confess join("\n", map { defined($_) ? $_ : "(undef)" } @_);
};

#Point GenQuery to the appropriate configuration file.
my $params = {config_file => $conf,
			  error_handler => $error_handler
			 };

#die Dumper(scalar($query->Vars()));
my $cgiapp = GenQuery::WebQuery->new(QUERY => $query, PARAMS => $params);

#More debuggeration:

$cgiapp->run();
