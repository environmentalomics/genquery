#!perl
use strict; use warnings;

#Class representing all connected databases.  Knows about GenQuery tables and the like.
#Does not know about different databases - that is left to DBConnection
package GenQuery::GQConnection;
use GenQuery::QueryCollection;
use GenQuery::DBConnection;

use Carp; #http://www.activeangler.com/resources/cooking/recipes/carp/carp_index.asp

#Params in the tables
#FIXME - sort out the linkouts and remove this!
use constant {
    QUERY_DEFS_COLS => join(', ', qw(query_id title category hide long_label query_url icon_index)),
    QUERY_PARAMS_COLS => join(', ', qw(param_no param_type param_name param_text menu_query suppress_all)),
    QUERY_LINKOUTS_COLS => join(', ', qw(url label name key_column pack)),
};

#No longer created by a DBConnection - constructor just makes an empty collection
sub new
{
    my $this = bless({} => shift);

    #Constructor creates an empty set of connections.
    $this->{db_conns} = {};

    #And an empty list of queries (mapped by connection IDs as above)
    #These queries are just hashes - they need to be put into a QueryCollection and
    #instantiated.
    $this->{queries} = {};

    #No connecting yet.
    $this;
}

sub setup_from_config
{
#This will add the connections then grab the queries
    my $this = shift;
    my ($config) = @_;

    #Add the connections
    for my $dbid($config->get_db_ids())
    {
	$this->add_connection($dbid, $config->get_db_param($dbid), 
			      $config->get_db_display_name($dbid));
    }

    #And the queries from the XML - have to refactor the structure but this is done internally by
    #the configuration object
    $this->{queries} = $config->get_all_queries(); 
}

sub add_connection
{
#This will create a new connection object based on the params, but
#will not connect it.
    my $this = shift;
    my ($dbid, $connection_params, $displayname, $overwrite) = @_;

    my $connections = $this->{db_conns};

    if(!$overwrite && $connections->{$dbid})
    {
	die "Connection with ID $dbid already exists\n";
    }
    
    $this->{db_names}->{$dbid} = $displayname;
    $connections->{$dbid} = new GenQuery::DBConnection($connection_params);
}

sub add_query
{
    #This will add a query directly to the list
    my $this = shift;
    my ($dbid, $qid, $query) = @_;

    $this->{queries}->{$dbid}->{$qid} = $query;
}

sub get_db_display_name
{
    #Mirrors Configuration::get_db_display_name
    my $this = shift;
    my ($dbid) = @_;

    $this->{db_names}->{$dbid || 0};
}

#Ensure a database, or all databases, are actually logged in.
sub connect_connection
{
    my $this = shift;
    my $connections = $this->{db_conns};

    my @connections_to_connect = @_;
    @connections_to_connect = keys %$connections unless @connections_to_connect;

    $connections->{$_}->connect() for(@connections_to_connect);
}

#The only big public function
sub get_query_collection
{
    #Returns QueryCollection object
    my $this = shift;

    #Need to collect queries from database.
    #TODO - Is there potential for continuing if not all connections work?
    # -Mark bad connections
    # -Determine if error is a login problem (maybe re-prompt for username/password) or
    #  a db failure
    # -Allow config file to say 'fail on error' for a connection, or if there is only one connection
    # -Tell the user what is going on, without disrupting interface
    $this->connect_connection();

    #Initial query list from XML
    my $querycoll = new GenQuery::QueryCollection(
						$this,
						$this->{queries}
					);

    #Add from each database
    for my $conn (keys %{$this->{db_conns}})
    {
	my $dbqueries = $this->extract_queries_from_db($this->{db_conns}->{$conn});

	#DB queries should not overrride XML queries with the same ID
	#or if they do then I need to ensure that the parameter lists get found properly
	$querycoll->add_queries($conn, $dbqueries) if $dbqueries;
    }

    return $querycoll;
}

sub extract_queries_from_db
{
    my $this = shift();
    my ($connection) = @_;

    my $allqueries;
    eval{
	$allqueries = $connection->extract_queries_from_db();
    };
    if($@){ die "Unable to load queries from database - error was:\n$@\n"; }

    #Avoid sending an empty query hash.
    %$allqueries ? $allqueries : undef;
}

#A convenient thing.  This matches the conn() found in webquery
#which actually creates a new GQConnection, and allows something
#like a QueryCollection to be passed either a GQConnection or anything
#which provides conn() to get at one.
sub conn
{
    shift;
}

#Functions called by the QueryInstance objects
sub get_body_and_headings_for_query
{
    #Only works for queries defined within the database
    my $this = shift;
    my ($dbid, $qid) = @_;
    my $connection = $this->{db_conns}->{$dbid} or confess "No such connection ID $dbid";

    #Pass this onto the Db connection as error handling differs by database type.
    $connection->get_body_and_headings_for_query($qid);
}

sub get_linkouts_for_query
{
    #Very similar principle to the above, but if no linkouts are specified
    #just return an empty list
    my $this = shift;
    my ($dbid, $qid) = @_;
    my $connection = $this->{db_conns}->{$dbid} or confess "No such connection ID $dbid";
    my $query_linkouts = $connection->get_config()->{query_linkouts} or return {};
    my $dbh = $connection->get_handle();

    $dbh->selectall_hashref(
		"SELECT " . QUERY_LINKOUTS_COLS . " FROM $query_linkouts
		 WHERE query_id = ?", "name", undef, $qid
	  );
}

sub get_params_for_query
{
    #Only works for queries defined within the database
    my $this = shift;
    my ($dbid, $qid) = @_;
    my $connection = $this->{db_conns}->{$dbid} or confess "No such connection ID $dbid";

    my $res = $connection->get_params_for_query($qid);

    #Fixup unnamed params - this is repeated in the xml_query_params_to_allparams
    #function in QueryInstance.pm but it seemed sensible to always be returning clean
    #data.  (Or is this just dumb? - never do something twice!)
    for(values %$res)
    {
	$_->{param_name} ||= "PARAM" . $_->{param_no};
    }

    $res;
}

sub get_values_for_param
{
    #This needs to work for queries defined in the XML and ones in the database
    #and if there is more than one column of results should simply return a big array in
    #row-first order.
    my $this = shift;
    my ($dbid, $qid, $pid, $querystring) = @_;
    my $connection = $this->{db_conns}->{$dbid} or die "No such database connection ID $dbid (for query $qid).\n";
    my $dbh = $connection->get_handle();

    #Find the query to run
    if(!$querystring)
    {
	#Look in the database but be prepared that the row will not exist at all if
	#this was an XML query.  Strategy - put an eval round the whole thing and
	#ignore failure! 
	my $query_params = $connection->get_config()->{query_params} or return undef;
	eval{
		$querystring = $dbh->selectrow_arrayref(
		"SELECT menu_query FROM $query_params
		 WHERE query_id = ? AND param_no = ?",
		 undef, $qid, $pid)->[0];
	};
    }
    
    #This will die if the query string is bad.
    my $results = $querystring ? $dbh->selectall_arrayref($querystring) : undef;

    #The next line flattens the array into 1 dimension, I think...
    [ map {@$_} @$results ];
}

#The QueryInstance needs to be able to quote, and the quoting must be right for
#the DBH, so the DBID is passed through
sub quote
{
    my $this = shift;
    my $dbid = shift;
    my $connection = $this->{db_conns}->{$dbid} or confess "No such connection ID $dbid";
    my $dbh = $connection->get_handle();

    #If the quote function in DBD::Pg gets 2 args it can segfault the whole process!
    #Permit quoting a list because I might want that at some point...
    wantarray ? map {$dbh->quote($_)} @_ : $dbh->quote($_[0]);
}

#And to get results
sub selectall_gq
{
    my $this = shift;
    #This will do a selectall_arrayref and return:
    # 1) The array of arrays
    # 2) The array of headings ($sth->{NAME_lc})
    # 3) The array of type infos
    
    my ($dbid, $sql) = (shift, shift);
    my $connection = $this->{db_conns}->{$dbid} or confess "No such connection ID $dbid";

    #Save the query for debugging
    $this->{last_statement} = $sql;

    #Pass on SQL and all other arguments
    $connection->selectall_gq($sql, @_);
}

sub last_sql_error
{
    my $this = shift;

    #Easy because DBI provides a convenience method, but it seems sometimes this can die
    #and I have to be careful with the 'eval' to trap it:
    # eva{$DBI::errstr} || $@; doesn't work!
    my $err;
    eval{ $err = $DBI::errstr };
    $err || $@;
}

sub last_sql_statement
{
    my $this = shift;

    #Nearly as easy as the above, but DBD::Pg forgets the last statement if execution was
    #successful.  This is a bug, but never mind - I can store it myself.
    my $h = {};
    eval{
	$h = $DBI::lasth or return undef;
    };
    $h->{Statement} || $this->{last_statement};
}

sub disconnect
{
    #Tell all GQConnections to finish up
    my $this = shift;

    my $connections = $this->{db_conns};
    $connections->{$_}->disconnect() for(keys %$connections);
}

1;
