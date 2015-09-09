#!/usr/bin/perl

# How to run GQ without a separate configuration file.

### Put contents of genquery_conf.xml after this line:
my $conf = <<'CONF';

<gq_config>

  <template_dir>/etc/genquery/templates</template_dir>

  <!-- These will be passed directly into templates -->
  <template_vars>
    <SITE_TITLE>My GenQuery site</SITE_TITLE>
    <SITE_BANNER>GenQuery is the Generic Query Generator</SITE_BANNER>
  </template_vars>

  <!-- Single database connection with all parameters supplied -->
  <db_connection id="0">
    <db_type>Pg</db_type>
    <db_host>dbhost.example.com</db_host>
    <db_name>yourdb</db_name>
    <db_user>webuser</db_user>
    <db_pass>webuser</db_pass>
    <db_schema>public</db_schema>

    <query_defs>public.query_def</query_defs>
    <query_params>public.query_param</query_params>
  </db_connection>

  <cache_queries>no</cache_queries>
  <login_cookies>yes</login_cookies>
  <bookmarks_on_links>yes</bookmarks_on_links>

</gq_config>

CONF
### End of configuration.  You should not need to edit below this line.

use GenQuery::WebQuery;
use CGI;
use strict;  use warnings;

BEGIN { if($ENV{REQUEST_METHOD}){
    require CGI::Carp; import CGI::Carp qw(fatalsToBrowser);
} };

#Point GenQuery to the appropriate configuration file.
my $params = { config_file => $conf };

# At this point you can inspect and modify the parameters, in which case you need
# to pass a CGI object to WebQuery->new()
#   my $query = new CGI;
#   if $query->param('foo') { do something };
#   my $cgiapp = GenQuery::WebQuery->new(QUERY => $query, PARAMS => $params);

# or more simply...
my $cgiapp = GenQuery::WebQuery->new(PARAMS => $params);

# Uncomment for debugging:
#  $cgiapp->savetofile("/tmp/last_gq_run.out");

$cgiapp->run();
