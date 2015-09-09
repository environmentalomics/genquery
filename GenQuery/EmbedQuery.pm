#!perl
use strict;
package GenQuery::EmbedQuery;

=head1 Title 

GenQuery::EmbedQuery 

=head1 Summary

The main web query stuff is in GenQuery::WebQuery, providing a full web application.
But what if you just want to run a single query and embed the reulsts into a page?
This module provides that interface.

=head1 Synopsis

 use GenQuery::EmbedQuery;

 #Within your CGI script...
 #Instantiate with the same params as for WebQuery.pm
 my $emq = new GenQuery::EmbedQuery( config_data => { ... }, link_base => '...' );
 # or (TODO)
 my $emq = new GenQuery::EmbedQuery( dbh => $dbh, query_defs => "...", query_params => "..." );
 
 $emq->set_query( 'My query' );
 # or
 $emq->set_query( id => 24 );
 $emq->set_template( $template_as_text );

 print $emq->run_and_print( %QUERY_PARAMS );

Note that you can run one query with several sets of params, and more than one query,
but each EmbedQuery object is wedded to one instance and one query set.

=notes

There are two ways to go about this.  Either bring in the whole of GQ to parse the configuration
and make the database connection or just supply a DBI handle and call upon DBConnection directly.
What I really want for Handlebar::Plugin::experiment_creator is the latter, but the former is
certainly easier to implement so let's stick with that for now...

=cut

#TODO - add direct call to DBConnection as suggested above and remove these
#dependencies in that case.
use GenQuery::QueryCollection;
use GenQuery::Configuration;
use GenQuery::GQConnection;

use HTML::Template;
use CGI qw(Tr th td escape); #Various utitlity thingies needed from CGI

#Instantiation returns an object configured and connected to the database.
sub new
{
	my $class = shift;
	my $this = {};

	#Config can be passed as config_file or config_params or whatever
	my $conf_in;
	for(my $nn=0 ; $nn < @_ ; $nn+=2)
	{
		$_[$nn] =~ /^config/ and $conf_in = $_[$nn+1];
		$_[$nn] =~ /^link_base/ and $this->{link_base} = $_[$nn+1];
	}
	$conf_in or die "Need to supply a configuration for GenQuery " . 
	                "(instantiation from a DB handle not yet supported)";

	my $conf = $this->{conf} = new GenQuery::Configuration;
	$conf->load_config($conf_in);

	#FIXME - should be possible to pass these in from the caller
	$conf->needs_user_params() and die "Configuration wants to prompt for user login params.";

	#Connect now.
	my $conn = $this->{conn} = new GenQuery::GQConnection();
	$conn->setup_from_config($conf);
	$conn->connect_connection();

	bless $this => $class;
}

#Set query by name or ID
sub set_query
{
    my $this = shift;

    my $allqueries = $this->{conn}->get_query_collection();

    my $query_id;

    if( @_ == 2 && $_[0] eq 'id' )
    {
	#ID is supplied.
	$query_id = $_[1];
    }
    else
    {
	$query_id = $allqueries->title_to_id($_[0]);
    }

    $this->{query} = $allqueries->instantiate_by_id($query_id) or die "Cannot instantiate query @_";
    $this->{queryinfo} = $allqueries->get_info_by_id($query_id);
}    

#set template as FH or text or existing template object
sub set_template
{
    my $this = shift;
    my($template_text) = @_;

    my $tmpl;
    my @tmpl_opts = (die_on_bad_params => 0);

    if( ref($template_text) eq 'HTML::Template' )
    {
	$tmpl = $template_text;
    }
    elsif( eval{ $template_text->fileno() }, !$@ ) #Test for a FH, trust me!
    {
	$tmpl = HTML::Template->new(filehandle => $template_text, @tmpl_opts);
    }
    else
    {
	$tmpl =  HTML::Template->new(scalarref => \$template_text, @tmpl_opts);
    }

    $this->{tmpl} = $tmpl;
}

sub run_and_print
{
    my $this = shift;
    my $query_params = ( @_ == 1 ? $_[0] : {@_} );

    my $conf = $this->{conf} or die "assertion failed - no conf object"; 
    my $thisquery = $this->{query} or die "Cannot run - no query is set.";
    my $queryinfo = $this->{queryinfo} or die "assertion failed - have query but no info"; 
    my $tmpl = $this->{tmpl} || die "Cannot run - no template is set.";

    #From feed_parameters_to_query in WebQuery.pm
    #It's the callers responsibiliy to feed multi-valued
    #params as array refs.
    $thisquery->set_param_by_name($_ => $query_params->{$_}) for keys(%$query_params);

    #From add_query_to_tmpl in WebQuery.pm
    #Just the basics - you fon't get a query form!
    (my $qlabel = $queryinfo->{long_label} || '') =~ s/\n/<br \/>/g;

    $tmpl->param( SHOWING_MENU => 0 );
    $tmpl->param( SHOWING_QUERY => 0 );
    $tmpl->param( QUERY_ID => $queryinfo->{query_hash_id} );
    $tmpl->param( QUERY_TITLE => $queryinfo->{title} );
    $tmpl->param( QUERY_LABEL => $qlabel );

    my $res = $thisquery->execute();

    #Set link base as provided when instantiating object
    $res->set_link_base($this->{link_base});

    #From show_results in WebQuery.pm
    my $link_postfix = $conf->get_param('bookmarks_on_links') ? '#results' : '';
    $res->set_link_postfix($link_postfix);

    #Tell the ResultTable about any connection params for internal links
    $res->set_login_params($conf->generate_persistence_hash());

    #Tell the result table which mode to use for checkbox columns, and add the
    #target URL and a submit button for new-style linkouts while we are at it.
    if($queryinfo->{linkout_target})
    {
	$this->add_newlinkout_to_tmpl($tmpl, $queryinfo->{linkout_target});
	$res->set_checkbox_pivot_mode(!($queryinfo->{linkout_target} =~ m{://}));
    }

    #######
    #And the bit that actually adds the results - copy/pasted (sorry) from WebQuery.pm.
    #See how many rows to put in table
    my $display_max_rows = $conf->get_param('display_max_rows') || 2000;

    my $rt_head = th($res->get_display_headings());
    my @rt_rows;
    while(my @arow = $res->get_next_row_html())
    {
	#Limit to 2000 rows - TODO support paging of results.
	if(@rt_rows > $display_max_rows)
	{
	    push @rt_rows, { ROW_DATA => 
			     Tr(td({-colspan => scalar(@arow)},
				    "<i>Too many rows - stopping after $display_max_rows.</i>"))
		       };
	    last;
	}

	push @rt_rows, { ROW_DATA => join( "\n", td([@arow]) ),
			 ROW_NUMBER => @rt_rows + 1 };
    }

      #Display
    $tmpl->param( SHOWING_RESULTS => 1 );
    if(@rt_rows > $display_max_rows)
    {
	$tmpl->param( ROWS_RETURNED => ">$display_max_rows" );
    }
    else
    {
	$tmpl->param( ROWS_RETURNED => scalar(@rt_rows) );
    }
    $tmpl->param( RESULTS_TABLE_HEADER => $rt_head );
    $tmpl->param( RESULTS_TABLE_ROW => \@rt_rows );
     
    #Offer CSV download and permalink
    my $permalink = $this->query_to_permalink($query_params);

    #FIXME - should really support exports
    #$this->add_exports_to_tmpl($tmpl, $thisquery, $permalink, $link_postfix);

    if($permalink)
    {
	$tmpl->param( PERMALINK => "$permalink;rm=results$link_postfix" );
	$tmpl->param( DOWNLOADLINK => "$permalink;rm=dl" );

	#This is handy if you are not showing the query form on the results page and want
	#to get back to the query form

	$tmpl->param( QUERYLINK => "$permalink;rm=query" );
	#but this makes no sense here...
        #$tmpl->param( MENULINK => "$permalink;rm=submenu$expanded_bit" );

	#No debug mode within EmbedQuery, but you can have a link to it.
	unless($conf->get_param('disable_debug'))
	{
	    $tmpl->param( DEBUGLINK => "$permalink;rm=results;debug=1" );
	}
    }

    #Old-style linkouts?  I don't think I need to worry.

    $tmpl->output();
}

sub query_to_permalink
{
    #The implementation in WebQuery.pm does this by stripping some parameters
    #off the original query, but here I need to ask the caller for a base link
    #as I don't know where the actual GQ endpoint is (or even if there is one).
    my $this = shift;
    my ( $query_params ) = @_;
    my $link_base = $this->{link_base} or return undef;

    my $new_q = new CGI($link_base);

    $new_q->param($_ => $query_params->{$_}) for keys(%$query_params);
    $new_q->param(queryid => $this->{queryinfo}->{query_hash_id});

    $new_q->url( {-relative=>0, -query=>1 } );
}

1;
