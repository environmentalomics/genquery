#!perl
use strict; use warnings;

#Class corresponding to database connection.  Knows about various types of database.
package GenQuery::DBConnection;

use DBI;
use Carp;
use Data::Dumper;

use constant {
    QUERY_DEFS_COLS => join(', ', qw(query_id title category hide long_label query_url icon_index)),
    QUERY_PARAMS_COLS => join(', ', qw(param_no param_type param_name param_text menu_query suppress_all)),
    QUERY_LINKOUTS_COLS => join(', ', qw(url label name key_column pack)),
};

sub new_from_handle
{
    #Uses an existing handle.  Don't call connect()!
    my $this = bless({} => shift);

    my $dbh = $this->{dbh} = shift;
    my $params = $this->{params} = shift;

    #Set params based on handle
    $params->{dbtype} = $dbh->{Driver}->{Name};
    $params->{db_name} = $dbh->{Name};
    $params->{db_user} = $dbh->{UserName};

    $this;
}

sub new
{
    my $this = bless({} => shift);

    my $params = $this->{params} = shift;
    my $dbtype = $this->{dbtype} = $params->{db_type};

    #Require appropriate driver
    eval "require DBD::$dbtype;" or die $@;

    $this;
}

sub connect
{
    my $this = shift;
    my $params = shift || $this->{params};

    #DEBUG:
#    die Dumper $params;

    my $dbtype = $this->{dbtype};
    my $db_host = $params->{db_host};
    my $db_port = $params->{db_port};
    my $db_name = $params->{db_name};
    my $db_user = $params->{db_user};
    my $db_pass = $params->{db_pass};
    my $db_schema = $params->{db_schema};
    my $db_sep_char = $params->{db_sep_char};
    
    my $dsn = "dbi:$dbtype:";
    if($dbtype ne 'CSV')
    {
	$db_name and $dsn .= ";dbname=$db_name";
	$db_host and $dsn .= ";host=$db_host";
	$db_port and $dsn .= ";port=$db_port";
    }
    else
    {
	#Special case for CSV
	$db_name and $dsn .= ";f_dir=$db_name";
	if($db_sep_char)
	{
	    $db_sep_char eq '\t' and $db_sep_char = "\t";
	    $dsn .= ";csv_sep_char=$db_sep_char";
	}
    }
    
    my $dbh; 
    #Purpose of the eval/re-throw is to neaten up the reported error by removing
    #the line number reference and maybe substituting a better message.
    eval{
	#The connection will be re-made on each call, so if using mod-perl it is probably
	#a good idea to activate Apache::DBI.  This will do transparent DBI handle caching
	#and prevent disconnection should 'just work'.
	$dbh = DBI->connect($dsn, $db_user, $db_pass, {AutoCommit => 1, RaiseError => 1});

	#Schema is currently PG specific
	#Note: FIXME  If the user cannot access the schema because of lacking permissions
	#you currently get a "not found" error rather than a permissions error.
	if($db_schema && $dbtype eq 'Pg')
	{
	    $dbh->do(qq{SET search_path=$db_schema, public});
	}

	#Before, I put any PostgreSQL database into 'ISO-8859-1' mode.
	#Note that the default just now (2010) is to set the client_encoding to UTF-8
	#but then treat what comes back as binary.  This is silly, so I'm being explicit on both counts.
	$dbh->do(qq{SET client_encoding="UTF8"}) if $dbtype eq 'Pg';	
	$dbh->{pg_enable_utf8} = 1 if $dbtype eq 'Pg';

	#Note - if you select a value that DBD::Pg doesn't recognise as a string then it will not set
	#the flag and the result will get double-encoded.  Ie. try:
	#  select 'xxx', 'xxx'::text;
	#And if xxx is some unicode-type text then you'll see the difference.

	$dbh->{mysql_enable_utf8} = 1 if $dbtype eq 'mysql';

	1; #Ensure the EVAL does not return 0 unless there was an error.
    } or die $this->error_demystify(DBI::errstr);

    $this->{dbh} = $dbh;
    1;
}

sub disconnect
{
    my $this = shift;
    $this->{dbh}->disconnect();
}

sub get_handle
{
    shift->{dbh};
}

sub get_config
{
    shift->{params};
}

sub error_demystify
{
    my $this = shift;
    my ($message) = @_;
    my $dbtype = $this->{dbtype};

    my @mappings = (
	{ dbtype => "Pg",
	  error  => qr/no password supplied/,
	  say    => "A password is needed to connect to the database" },

	{ dbtype => "Pg",
	  error  => qr/Password authentication failed for user/,
	  say    => "The username or password is incorrect" },
    );

    for(@mappings)
    {
	if($_->{dbtype} eq $dbtype && $message =~ /$_->{error}/)
	{
	    $message = $_->{say}; 
	    last;
	}
    }
    $message =~ /\n$/ ? $message : "$message\n";
}

sub selectall_gq
{
    #Implements selectall_gq from GQConnection
    my $this = shift;
    my $sql = shift;
    my $dbh = $this->{dbh};

    my($res, $names, $types);

    my $sth = $dbh->prepare($sql);
    eval {$sth->execute(@_); } or die "$@\nquery:$sql";

    $names = $sth->{NAME_lc};
    $types = $sth->{TYPE}; #May be undef for some drivers

    #Translate number to name
    if($types)
    {
        for(my $nn = 0; $nn < @$types; $nn++)
        {
            $types->[$nn] = $dbh->type_info($types->[$nn]);
        }
    }

    #Grab the data
    $res = $sth->fetchall_arrayref();

    ($res, $names, $types);
}

sub get_body_and_headings_for_query
{
    #Only works for queries defined within the database
    my $this = shift;
    my ($qid) = @_;

    my $query_defs = $this->{params}->{query_defs} or die "No query defs set.";
    my $dbh = $this->{dbh};

    my $res;
    unless( eval {
        $res = $dbh->selectrow_arrayref(
                      "SELECT query_body, column_head, export_formats FROM $query_defs
                       WHERE query_id = ?", undef, $qid
                     );
           } )
    {
        $@ =~ /export_formats.*?does not exist/ and die
                "The query definition table has no \"export_formats\" column.  Your database schema needs to be updated to ".
                "work with this version of GenQuery.  Please try running:\n".
                "  ALTER TABLE $query_defs ADD COLUMN export_formats text;\n\n";
        die $@;
    }
    $res;
}

sub get_params_for_query
{    
    #Only works for queries defined within the database
    my $this = shift;
    my ($qid) = @_;

    my $query_params = $this->{params}->{query_params} or return undef;
    my $dbh = $this->{dbh};

    my $res;
    unless( eval {
            $res = $dbh->selectall_hashref(
                    "SELECT " . QUERY_PARAMS_COLS . " FROM $query_params
                    WHERE query_id = ?", "param_no", undef, $qid);
            } )
    {
        $@ =~ /suppress_all.*?does not exist/ and die
                "The parameter table has no \"suppress_all\" column.  Your database schema needs to be updated to ".
                "work with this version of GenQuery.  Please try running:\n".
                "  ALTER TABLE $query_params ADD COLUMN suppress_all boolean;\n\n";
        die $@;
    }
    $res;
}

sub extract_queries_from_db
{
    my $this = shift;

    my $query_defs =  $this->{params}->{query_defs} or return {};
    my $dbh = $this->{dbh};

    my $allqueries;
    
    #This was initially easy, but in the improved version I want it so that any queries with
    #both a body and a query_url get picked up and munged so that query_url becomes
    #linkout_target.  I can't use SQL functions as this needs to be DB agnostic and I don't want
    #to hammer the database or fetch all the query bodies up-front.  I think I can consider the "IN (list)"
    #SQL construct to be universal but even "query_body = ''" needs to heed the right quoting.

    $allqueries = $dbh->selectall_hashref(
			"SELECT " . QUERY_DEFS_COLS . " FROM $query_defs",
			"query_id"
		     );

    #Find which queries have a query_url
    my @queries_with_url = map {$_->{query_url} ? $_->{query_id} : ()} values(%$allqueries);

    if(@queries_with_url)
    {
	my $queries_with_url_and_body = $dbh->selectcol_arrayref(
			"SELECT query_id FROM $query_defs
			 WHERE query_id IN (" . join(',', @queries_with_url) . ")
			 AND query_body IS NOT NULL
			 AND NOT query_body = ?", undef, '');

	for(@$queries_with_url_and_body)
	{
	    $allqueries->{$_}->{linkout_target} = $allqueries->{$_}->{query_url};
	    $allqueries->{$_}->{query_url} = undef;
	}
    }
    $allqueries;
}
    
1;
