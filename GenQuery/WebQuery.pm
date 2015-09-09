#!perl
use strict;

#The CGI::Application that drives the web interface.  The meat of GenQuery.
package GenQuery::WebQuery;
use base 'CGI::Application';
use CGI::Application::Plugin::Forward;
use GenQuery::QueryCollection;
use GenQuery::Configuration;
use GenQuery::GQConnection;

#Only for debugging:
use Data::Dumper;
use Encode;

#Trying to make a general purpose test for old and new mod_perl
our $RUNNING_UNDER_APACHE_REGISTRY = ($Apache::Registry || %{ModPerl::}) ? 1 : 0;

#Some appropriate globals.
#This needs to match the declaration in GenQuery::WebFormControls
our $ALL = "ALL\240"; #ie. "ALL&nbsp;" avoids unlikely collision with a literal "ALL"

use warnings;

#A problem with CGI is that it generates a Netscape 2.0 input/button tag but not
#a new style <button>.  Easily remedied...
sub cgiapp_prerun
{
    #This belongs in prerun because I need to have the query object available and
    #this is the earliest I get at it.
    my $this = shift;
    my $q = $this->query();
    $q->import('Button');

    #This belongs here because I need to specifically avoid it in logout mode.
    my $runmode = shift;
    unless($runmode eq 'logout')
    {
	$this->param('config')->set_from_cgi($this->query());
    }

    #I want to work in Unicode
    # The browser will say if it can accept utf-8, or if running outside the browser
    # I can peek at the current locale and use that.
    # The charset header tells the browser what to expect
    # Cases: cgi + !utf = works already
    #        cgi + utf = needs binmode STDOUT setting
    #        mod + !utf = see cgiapp_postrun
    #        mod + utf = works already, but needs params upgrading
    if(($q->http('HTTP_ACCEPT_CHARSET') || $ENV{LANG} || '') =~ /utf.?8/i)
    {
	$this->header_add(-charset => 'utf-8');
	binmode STDOUT, ':utf8';
	$this->param(utf8 => 1);
	#The query params will be in utf8 but CGI.pm doesn't have them flagged
	#unless the input handle is set to utf8 mode, and it's too late to
	#do that.
	_fix_utf8_query_params($q);

	#It shouldn't matter if I upgrade $ALL to utf8 now or let the output layer do it,
	#but this seems saner.
	utf8::upgrade($ALL);
    }
    else
    {
	binmode STDOUT, ':raw';
	$this->param(utf8 => 0);
    }
}

sub cgiapp_postrun
{
	my $this = shift;
	my ($output_ref) = @_;

	#It seems that when running under mod_perl and serving non utf8 I need to manually
	#downgrade the output before I send it.
	#With standard CGI it all works already.
	#I really don't know what I'm doing here, and this is probably wrong in general,
	#but it seems to work for me right now...
 	if(  $RUNNING_UNDER_APACHE_REGISTRY && !$this->param('utf8') )
 	{
	    utf8::downgrade($$output_ref, 1);
 	}
}

sub _fix_utf8_query_params
{
	#This is hacky, but I need to do it if I can't set binmode ':utf-8'
	#on STDIN befoe CGI.pm gets to the data.
	#Derived from http://ahinea.com/en/tech/perl-unicode-struggle.html
	my ($q) = @_;

	foreach my $name ( $q->param ) {
	  my @val = $q->param( $name );
	  foreach ( @val ) {
		utf8::decode( $_ );
	  }
	  utf8::decode( $name );
	  if ( scalar @val == 1 ) {   
		$q->param($name => $val[0]);
	  } else {                      
		$q->param(-name => $name, '-values' => \@val);  # save value as an array ref
	  }
	}
}

sub teardown
{
    #This is a good place to close the DB connection.
    my $this = shift;

    if(my $conn = $this->param('conn'))
    {
	$conn->disconnect();
    }
}

sub determine_rm
{
    my $this = shift;
    #This is a problem with IE.  If you want to use image buttons to submit a form,
    #which I do, then you can't just set the name of the button to 'rm' and the value
    #to the desired run-mode because it won't get picked up.  You have to detect the
    #button name and account for the .x and .y cruft.
    #Even worse, if you move to using a <button> tag then when the form is submitted all
    #the button values on the form get sent back, and there is no way to see which
    #was actually clicked!
    #I have to resort to JavaScript...
    #(Note - this means a lot of the following cruft is obsolete, but it works so I'm not cleaning it up)

    my $q = $this->query();
    my $rm = $q->param('rm');
    
    #Maybe the user has hit the logout button
    $q->param('logout.x') and $q->param(logout => 1);

    my @goparams;
    #Maybe the JavaScript hook has set the hidden value?
    if(my $goparam = $q->param('A pox on you, Bill Gates!'))
    {    
	@goparams = ($goparam);
	#Clear logout spuriously set by IE
	$q->param(logout => 0);
	$q->delete('A pox on you, Bill Gates!');
    }
    else
    {
	@goparams = grep /^go_/, $q->param();
    }

    #Now safe to logout
    $q->param('logout') and return 'logout';

    #Otherwise if rm is specified then fine
    return $rm if $rm;

    #Maybe a menu item has been clicked but the JS did not work.
    #We are looking for any param starting 'go_'
    for(@goparams)
    {
	#Now I don't know if I have
	#    go_whatever.[xy]=123
	# or go_whatever=Go and it is remotely possible that some spanner would name
	# their category foo.x and I don't like hanging corner cases, hence this test:
	if(/\.[xy]/ && $q->param($_) =~ /^\d+/)
	{
	    chop, chop; #Yay for Perlisms!
	}

	if($_ eq 'go_mainmenu')
	{
	    $rm = 'mainmenu';
	}
	else
	{
	    /^go_(.+?)_(.+)/ or die "Malformed go_ parameter!";

	    $rm = $1;
	    $q->param( menu_or_query => $2 );
	}
	last;
    }

    $q->param( rm => $rm ) if $rm;

    #TODO - can I return undef to allow the start mode or must I return it explicitly?
    $rm;
}

#Setup needs to define run modes and set some paths.
sub setup
{
    my $this = shift;
    $this->run_modes({
 	    login => 'login_form',
	    mainmenu => 'show_main_menu',
	    submenu => 'show_submenu',
	    subclose => 'close_submenu',
	    query => 'show_query',
	    results => 'show_results',
	    dl => 'download_results',
	    graph => 'show_graph',
	    logout => 'log_out',
    });
    $this->mode_param(\&determine_rm);
    $this->start_mode('submenu');
    $this->error_mode('error_handler');

    #This was originally in cgiapp_init but that is silly.
    my $conf = $this->configurate($this->param('config_data') || $this->param('config_file'));

    #Templates should be pointed to in config file.
    my $template_dir = $conf->get_param('template_dir');
    $this->tmpl_path($template_dir) if $template_dir;
}

sub load_tmpl
{
    #Override the standard load_tmpl to give default settings
    #and set variables from config, and to give a custom error.
    my $this = shift;
    my $conf = $this->param('config');
    my $tmpl;

	#TODO - implement override_template(original_file_name,template_as_string) to allow the caller to substitute
	#an alternative template instead of a normal one. (with this, templates could also be injected directly in the
	#config data)
	# if(my $to = $this->param('template_overrides'))
	# { 
	#	if(my $overriden_template = $to->{$_[0]})
	#	{
	#		shift @_;
	#		$tmpl = HTML::Template->new(...,  die_on_bad_params => 0);
	#	}
	# }
	# else
    eval {
        $tmpl = $this->SUPER::load_tmpl(@_, die_on_bad_params => 0, 
					    cache => $RUNNING_UNDER_APACHE_REGISTRY);
    }
    or die (
	"Unable to load the template file \"@_\". This probably means that the template directory is " .
	"not set correctly in the configuration file.\n\n",
	 ($conf->get_param('template_dir') ?
	    "The current template directory is " . $conf->get_param('template_dir') . ". " :
	    "No template directory has been set. " ) .
	"Please check that the templates are in place and/or amend the configuration.\n\n$@\n"
    );

    #Pass through vars from the configuration.
    if($tmpl)
    {
	if(my $vars = $conf->get_param('template_vars'))
	{
	    while( my ($key, $val) = each %$vars )
	    {
		$tmpl->param( $key => $val );
	    }
	}
    }
    $tmpl;
}

sub error_handler
{
    my $this = shift;
    #This will handle all errors apart from ones where it is appropriate
    #to redirect back to the database login - eg incorrect user/password.  
    #See if the user set an error reporter, otherwise see if there is
    #an error template to use, otherwise just die.

    #First gather some debugging info...
    my($lasterr, $lastsql);
    if(my $conn = $this->param('conn'))
    {
	$lasterr = $conn->last_sql_error();
	$lastsql = $conn->last_sql_statement();
    }

    if(my $althandler = $this->param('error_handler'))
    {
	return &$althandler($this, "@_", $lasterr, $lastsql);
    }
    
    my $tmpl;
    eval{ $tmpl = $this->load_tmpl('error.template.html') };
    if($tmpl)
    {
	(my $perl_error = "@_") =~ s/\n/<br \/>\n/g;

	$tmpl->param(PERL_ERROR => $perl_error);	
	$tmpl->param(LAST_DBI_ERROR => CGI::escapeHTML($lasterr));
	$tmpl->param(LAST_SQL_COMMAND => CGI::escapeHTML($lastsql));

	return $tmpl->output();
    }

    #TODO - optional 'warn' to get errors into the Apache log.

    #If the caller has used CGI::Carp this last resort may be the best idea.
    die "@_" . ($lasterr ? "\n$lasterr\n$lastsql\n" : "\n");
}

sub savetofile
{
    #Call the save method to persist the CGI object
    #You can supply the name of the correct config file to associate with this rerun
    my $this = shift;
    my ($filename, $configfilename) = @_;
    my $q = $this->query();

    my $OUT;
    open ($OUT, ">$filename") || die $!;

    #Save the name of the config file
    print $OUT "last_gq_run_config=", $q->escape($configfilename), "\n" if $configfilename;

    #And everything else
    $q->save($OUT);

    close $OUT;
}

sub configurate
{
    #Called from cgiapp_init to pull in all the configuration
    #Conffile can be an actual file, an XML string or a hashref
    my $this = shift;
    my $conffile = shift || 'genquery_conf.xml';
    
    my $config = new GenQuery::Configuration;
    $config->load_config($conffile);

    #Setting from CGI now done in prerun

    $this->param(config => $config);
    $config;
}

sub conn
{
    my $this = shift;
    my $q = $this->query();

    #This will either return the GQConnection object or bring it
    #magically into being or else trigger login_form($err) as an error
    #handler.
    #So elsewhere in this module I just do:
    # my $conn = $this->conn();

    #If I already have it just return it.
    my $conn;
    $conn = $this->param('conn') and return $conn;
    
    #Sanity check config has loaded or die for real.
    my $conf = $this->param('config') or die "Assertion failed - config not loaded";

    #Use login_form as an error handler.
    my $old_error_mode = $this->error_mode();
    $this->error_mode('login_form');

    #Check that either the user params were supplied or there were none to supply.
    if($conf->needs_user_params() && !$conf->has_user_params())
    {
	die "\n"; #Not an error, we just need to ask the user now.
	# 	die "No login attempted";
    }

    $conf->validate_all_params(); #Errors will be propogated 

    #Random Note: 
    #You should always have a login page.
    #If you are making a service with no login params, replace the login
    #page template with a straight error report page.

    #Connect now while I am ready to trap connection errors.
    $conn = new GenQuery::GQConnection();
    $conn->setup_from_config($conf);
    $conn->connect_connection();

    #Connection is done!
    $this->error_mode($old_error_mode);

    #Now is the time to set the validated username and password cookies
    if($conf->get_param('login_cookies') ne 'no')
    {
	$this->header_add(-cookie => $conf->generate_login_cookies($q));
    }

    #I looked at CGI::Application::Plugin::DBH but it does not provide the requisite hook
    #to jump to the login_form if the connection is not ready and in any case I want to
    #deal in GQConnection objects.
    $this->param(conn => $conn);
    $conn;
}

sub log_out
{
    my $this = shift;
    my $q = $this->query();

    #Logging out is not as simple as it could be.  We have to:
    # 1) Clear all the params out of the CGI object so they don't get persisted
    # 2) Clear out all the settables - to do this I moved set_from_cgi to cgiapp_prerun
    #    and avoid it if logout is selected.
    # 3) Generate a header to clear the login cookies.  This is done in the login_form code
    #    as they need to be cleared when a login fails as well as on a logout.

    #So - 1)
    $q->delete_all();

    $this->login_form("You have logged out");
}

sub login_form
{
    my $this = shift;
    #This is not a real run mode.  It is called when the connection cannot be made.
    my $q = $this->query();

    if($this->get_current_runmode() eq 'login')
    {
	die "Login mode should not be called directly.";
    }

    my $message = shift;
    my $conf = $this->param('config');

    #Load the appropriate template.
    my $tmpl = $this->load_tmpl('login.template.html') or die
	    "Failed to load template - cannot show login form";

    #Maybe the user is back here due to a login error.  If so, let them
    #know what it was.
    $tmpl->param( LOGIN_FAILURE_REASON => $message );

    #Config object can compile required fields into HTML
    $tmpl->param( LOGIN_FIELDS => $conf->generate_html_prompts($q) );

    #Attach the saved state into the form so we can jump back to the original request.
    #Unless the user wanted to log out, in which case the params will have already been cleared.

    #Now I want to preserve all the CGI fields apart from the ones which consitute part
    #of the login form.
    my %formparams = map {$_ => 1} $conf->find_all_params(1,1);
    my $savedfields = join("\n", map {$formparams{$_} ? () : $q->hidden($_)} $q->param());
    $tmpl->param( SAVED_STATE => $savedfields);

    #Either login failed, or this is the first login, or the user has hit logout.
    #Either way, clear the cookies which may still contain username and password. 
    unless($conf->get_param('login_cookies') eq 'no')
    {
	$this->header_add(-cookie => $conf->clear_login_cookies($q));
	#	die Dumper $conf->clear_login_cookies($q);
    }

    $tmpl->output();
}

sub show_main_menu
{
    my $this = shift;
    my $q = $this->query();

    #Clear any selections and jump to show_submenu
    $q->delete('menu_or_query');
    $q->delete('expanded');

    $this->forward('submenu');
}

sub show_submenu
{
    my $this = shift;
    my $q = $this->query();
    my $config = $this->param('config');
    
    #Deserialise or load from database
    my $allqueries = $this->instantiate_queries();

    #Fire up the template
    my $tmpl = $this->load_tmpl('menu.template.html') or die
	    "Failed to load template - cannot show menu form";

    #See if a category restriction was specified in the config
    my $current_category;
    if(my $only_category = $config->get_param('only_category'))
    {
	#$allqueries = $allqueries->get_by_category($only_category);
	#The above is done already by instantiate_queries
	$current_category = $only_category;
    }
    else
    {
	#Determine which menu is opened
	$current_category = $q->param('menu_or_query');
    }

    #And what levels are expanded if using the tree view
    my $expanded = $this->sort_out_expansions(scalar($q->param('expanded')),
					      $allqueries, 
					      $current_category,
					      scalar($q->param('category_to_close')));

    #DEBUG!
#      print STDERR Dumper($expanded), ($current_category || 'no category') ;

    #And 
    $tmpl->param( MENU_TITLE => $current_category || 'Main Menu' );
    $this->add_menu_to_tmpl($tmpl, $allqueries, $current_category, undef, $expanded);
    
    #Done
    $tmpl->param( SHOWING_TOP_MENU => $current_category ? 0 : 1 ); 
    $tmpl->output();
}

sub close_submenu
{
    #In this case the "menu_or_query" parameter should give the category to
    #collapse.  So sort that out...
    my $this = shift;
    my $q = $this->query();

    $q->param(category_to_close => $q->param('menu_or_query'));
    $q->delete('menu_or_query');

    $this->forward('submenu');
}

sub sort_out_expansions
{
    my $this = shift;
    my $config = $this->param('config');

    #Keeping track of the state of the tree menus turns out to be a bit fiddly,
    #partly because I insist on keeping a current category as well as a list of
    #what is expanded and what is collapsed.  Fortunately most of the cruft is
    #confined to this function which looks at the incoming 'expanded' parameter and
    #fixes it up to decide what to really show.
    my ($expanded_param, $allqueries, $current_category, $category_to_close) = @_;

    $expanded_param = '' unless defined($expanded_param);
    my @expanded = split("," , $expanded_param);

    my @categories = $allqueries->get_categories();
    my $expand_all = $config->get_param('expand_all') || 'no';

    #If expand_all is 'always' then set the list to everything.
    #If the list is empty and expand_all is yes then ditto.
    if($expand_all eq 'always')
    {
	return [0..$#categories];
    }

    #If the list is empty return undef or maybe everything.
    if(! @expanded) 
    {
	if($expand_all eq 'yes')
	{
	    return [0..$#categories];
	}
	elsif($expand_all eq 'never')
	{
	    #The expand parameter will never appear and GQ will operate in the old mode
	    return undef; 
	}
	#else
	    #Can't just return this - I might need to add the current category
    }

    #If the list contains a - then set the list to nothing.
    #If the list contains a * then set the list to everything.
    #But I still need to consider the current selection
    for(@expanded)
    {
	$_ eq '-' and @expanded = (), last;
	$_ eq '*' and @expanded = (0..$#categories), last;
    }

    #Ensure the list is sorted, unique integers and contains the current item
    #but not the category_to_close.
    my $idx_of_current = -1;
    if(defined($current_category))
    {
	my $nn = 0;
	for(@categories)
	{
	    $idx_of_current = $nn if $_ eq $current_category;
	    $nn++;
	}
    }

    my $foo; my $last = -1;
    return [ grep { $foo = $last; $last = $_; $_ != $foo } 
	      sort {$a <=> $b} grep
		{eval{
		    return 0 if /\D/; #Catches junk and negative numbers
		    return 0 if $_ > $#categories;
		    return 0 if defined($category_to_close) and $categories[$_] eq $category_to_close;
		    1;
		}}
		(@expanded, $idx_of_current) ];
}

sub instantiate_queries
{
    #This will instantiate the query list from the frozen parameter
    #or else fall back to checking the database.
    my $this = shift;
    my $config = $this->param('config'); 
    my $q = $this->query();

    #It is good to have a stack backtrace if this goes wrong
    #local $SIG{__WARN__} = sub{ require Carp; goto &Carp::confess };

    my $queries;

    if((my $frozenqs = $q->param('frozenqs')) && $config->get_param('cache_queries'))
    {
	#die "'$frozenqs'";
	if($queries = new GenQuery::QueryCollection($this, "$frozenqs\n"))
	{
	    #No need to filter, I hope.
	    return $queries;
	}
	else
	{
	    #Something corrupted!
	    die "Could not recreate query collection from CGI parameters.",
	    "Not falling back to database.";		 
	}
    }

    my $conn = $this->conn();
    $queries = $conn->get_query_collection();
    if(my $only_category = $config->get_param('only_category'))
    {
	return $queries->get_by_category($only_category);
    }

    return $queries;
}

sub add_menu_to_tmpl
{
    my $this = shift;
    my ($tmpl,          #An active template object
        $allqueries,    #All the available queries, icluding hidden ones
        $currentitem,   #The category to be shown, by title, or undef
	$openquery,     #The current query, or undef
	$expandeditems  #List of categories to be expanded in the menus - must be sorted unique integers
	) = @_;

    my $q = $this->query();
    my $config = $this->param("config");

    #FIXME - This seems to be needed on ivpcl19, but it is already done in the
    #initialisation stage.  Should not be needed twice - something is amiss!
    $q->import('Button');

    #TODO What if there are no queries at all?  Do something sensible.
    #TODO What if the current category has no queries?  This should not be possible
    # as categories are defined by queries of that category, but it could be a
    # misconfiguration - could show the title and a message in tree view.
    
    #This is the bit that really shows the menus
    #If the template does not use 'MENU_AND_CONNECTION_STATE' then there is no point adding
    #any menus so we may as well quit now.
    if(! $tmpl->query(name => 'MENU_AND_CONNECTION_STATE') eq 'VAR')
    {
	#If the user is using CURRENT_MENUS or PARENT_MENUS then they need to be told
	#that this ain't gonna work.
	if($tmpl->query(name => 'CURRENT_MENUS') || $tmpl->query(name => 'PARENT_MENUS'))
	{
		die "Bad template - includes menu entries but no MENU_AND_CONNECTION_STATE placeholder.\n";
	}
	return 3;
    }

    #Zerothly decide of the client browser is a broken piece of trash
    #(or indeed Konq/Safari)
    #Note - I was using $q->http() to detect CGI but this can spit warnings
    my $msie = $ENV{GATEWAY_INTERFACE} && ($q->user_agent('MSIE') || $q->user_agent('KHTML'));
    my $onclick_menu = '';
    my $onclick_link = '';

    #Firstly get rid of any hidden queries
    my $queries = $allqueries->get_non_hidden();

    #The persistence fields need to be within the menu form, so it makes sense to deal with them
    #here.
    #Generate a hidden field for the query object
    my $state = "";
    if( $config->get_param('cache_queries') )
    {
	    my $frozenqs = "";
	    $frozenqs = $allqueries->freeze() unless $q->param("frozenqs");
	    $state = $q->hidden( {-name => "frozenqs",
				  -value => $frozenqs } );
    }
    #Add connection state
    $state .= join("\n", @{$config->generate_persistence_fields($q)});

    #And add a field to overcome IE sending all button values back no
    #matter what you click, plus the little JS hook to fill it
    #I also need to force the issue when a link button is clicked in IE
    #otherwise it has no effect.
    if($msie)
    {
	$state .= $q->hidden( { -name => "A pox on you, Bill Gates!" } );

	$state .= qq|
	<script type='text/javascript'><!--
	  function setclicked(button)
	  {
		var button_form = button.form;
		var state_var = button_form.elements.namedItem("A pox on you, Bill Gates!");
		state_var.value = button.name;
	  }
	  function forcelink(button)
	  {
		var button_link = button.parentNode.href;
		self.location = button_link;
	  }
	--></script>|;

	$onclick_menu = "setclicked(this)";
	$onclick_link = "forcelink(this)";
    }

    #And remember what categories were expanded.
    if($expandeditems)
    {
	$q->param( expanded => (scalar(@$expandeditems) ? join (',', @$expandeditems) : '-' ));
	$state .= $q->hidden( { -name => "expanded" } );
    }

    $tmpl->param( MENU_AND_CONNECTION_STATE => $state );

    #Now if the template does not include menus we can quit here.
    unless($tmpl->query(name => 'CURRENT_MENUS') || $tmpl->query(name => 'PARENT_MENUS'))
    {
	return 2;
    }
    
    #Generate child menus for anything that is selected/open
    #If there is an expanded list it will already contain the selected category.  If not
    #then use just that category.
    # TODO - make it so!
    my @menus_to_generate = $expandeditems
			    ? ($allqueries->get_categories())[@$expandeditems]
			    : ( $currentitem || () );
    my (@parent_menus, %child_menus);
    my $button_id;
    
    #warn "\@menus_to_generate = @menus_to_generate, \$expandeditems = " . Dumper($expandeditems);

    for my $menu_to_generate (@menus_to_generate)
    {
	#Generate the open submenu/child menus
	my $child_queries = $queries->get_by_category($menu_to_generate);
	#Note - if all the queries in the category are hidden the collection will be empty, but
	#no matter.

	for my $id($child_queries->get_query_ids())
	{
	    my $info = $child_queries->get_info_by_id($id);
	    my $submit_button;
	    my $icon_index = $info->{icon_index};
	    
	    #The following is generating the query buttons
	    if($info->{query_url})
	    {
		$icon_index ||= 2;
		#Button replacement is done in CSS using the hack
		$button_id = "query_${icon_index}_normal";

		#Create a suitable button
		$submit_button = $q->a({ -href => $info->{query_url}, 
					 -style => "background:transparent" },
					 $q->Button({-value => 'Go', 
						     -class => 'icon',
						     -id => $button_id,
						     -type => 'button',
						     -onClick=>$onclick_link}, '<span class="buttontext">Go</span>')
				 );
	    }
	    else
	    {
		$icon_index ||= 1;

		#Is this query selected or not?
		if($openquery && $openquery == $id)
		{
		    $button_id = "query_${icon_index}_selected";
		}
		else
		{
		    $button_id = "query_${icon_index}_normal";
		}

		$submit_button = $q->Button({ -name => "go_query_$id",
					      -id => $button_id,
					      -class => 'icon',
					      -type => 'submit',
					      -value => 'Go',
					      -onClick => $onclick_menu }, '<span class="buttontext">Go</span>');
	    }
		
	    push @{$child_menus{$menu_to_generate}}, 
			       { MENU_ITEM_NAME => $info->{title},
				 MENU_ITEM_DESCRIPTION => $info->{long_label},
				 MENU_ITEM_DATABASE => $info->{database_name},
				 MENU_ITEM_SUBMIT => $submit_button };
	}
    }

    #Generate the main menu, adding sub-menu if appropriate.
    for my $category($queries->get_categories())
    {
	my $submit_button;
	my $icon_index;
# 	my $this_category_open = 0;
	
	#We have a normal and a selected icon
	if($child_menus{$category})
	{
# 		$this_category_open = 1;
		$button_id = "category_selected";

		#Originally, clicking an expanded category did a 'go_mainmenu'.  Now it needs to
		#toggle the expansion state.

		$submit_button = $q->Button({-name => "go_subclose_$category",
					     -class => 'icon',
					     -id => $button_id,
					     -type => 'submit',
					     -value => 'Back',
					     -onClick => $onclick_menu }, '<span class="buttontext">Back</span>');
	}
	else
	{
		$button_id = "category_normal";

		$submit_button = $q->Button({-name => "go_submenu_$category", 
					    #TODO - check escaping for funky category names
					     -id => $button_id,
					     -class => 'icon',
					     -type => 'submit',
					     -value => 'Go',
					     -onClick => $onclick_menu }, '<span class="buttontext">Go</span>');
	}
	
	push @parent_menus, { MENU_ITEM_NAME => $category,
			      MENU_ITEM_DESCRIPTION => "Category: $category",
			      MENU_ITEM_DATABASE => $queries->get_db_name_for_category($category),
			      MENU_ITEM_SUBMIT => $submit_button,
			      CHILD_MENUS => $child_menus{$category} || [] };

    }

    #Sort out CURRENT_MENUS
    #If no category is selected the parent menu is current, else add the open category
    if($currentitem)
    {
	$tmpl->param( CURRENT_MENUS => $child_menus{$currentitem} );
    }
    else
    {
	$tmpl->param( CURRENT_MENUS => \@parent_menus );
    }
    
    #The parent_menus structure is now loaded with the necessary tree.
    $tmpl->param( PARENT_MENUS => \@parent_menus );

    #No defined return value.
    1;
}

sub show_query
{
    my $this = shift();

    my $config = $this->param('config');
    my $q = $this->query();

    #Fire up the template
    my $tmpl = $this->load_tmpl('query.template.html') or die
	    "Failed to load template - cannot show query form";

    #Deserialise or load from database
    my $allqueries = $this->instantiate_queries();
    my $query_to_show = $this->determine_query($allqueries);
    my $queryinfo = $allqueries->get_info_by_id($query_to_show);
    my $thisquery = $allqueries->instantiate_by_id($query_to_show);

#     die Dumper($allqueries);
#     die Dumper($thisquery);

    #Right.  This is the run mode invoked to show the query.  
    #First thing is that if there are no params run the query straight away.
    #(TODO : Should this be a configurable option?)
    unless($config->get_param('always_show_query') || $thisquery->get_param_count())
    {
	return $this->forward('results');
    }
    
    #Depending on what is in the HTML template we may well be showing the menus 
    #as well, so that is the second order of business.
    
    #Determine which menu is opened, ie the category of this query.
    my $current_category = $queryinfo->{category};

    #And 
    #First, what levels are expanded if using the tree view
    my $expanded = $this->sort_out_expansions(scalar($q->param('expanded')),
					      $allqueries, 
					      $current_category);

    $tmpl->param( SHOWING_TOP_MENU => 0 ); 
    $tmpl->param( MENU_TITLE => $current_category );
    $this->add_menu_to_tmpl($tmpl, $allqueries, $current_category, $query_to_show, $expanded);

    #Now the actual query
    $this->add_query_to_tmpl($tmpl, $queryinfo, $thisquery, $allqueries, $expanded);
    
    #Done
    $tmpl->output();
}

sub add_query_to_tmpl
{
    my $this = shift();
    my ($tmpl, $queryinfo, $qobj, $allqueries, $expandeditems) = @_; #Last two not compulsory
    my $q = $this->query();
    my $config = $this->param('config');

    (my $qlabel = $queryinfo->{long_label} || '') =~ s/\n/<br \/>/g;

    $tmpl->param( SHOWING_QUERY => 1 );
    $tmpl->param( QUERY_ID => $queryinfo->{query_hash_id} );
    $tmpl->param( QUERY_TITLE => $queryinfo->{title} );
    $tmpl->param( QUERY_LABEL => $qlabel );

    my $qform_submit = qq{<input type="hidden" name="rm" value="results">\n};
    #If running in graph mode stay in graph mode and preserve fmt
    if($this->get_current_runmode() eq 'graph')
    {
	$qform_submit = qq{<input type="hidden" name="rm" value="graph">\n};
	$qform_submit .= $q->hidden( -name => 'fmt' );
    }

    #Add connection state
    $qform_submit .= join("\n", @{$config->generate_persistence_fields($q)});
    
    #Still keep all the queries if we have them
    if($allqueries &&  $config->get_param('cache_queries'))
    {
	my $frozenqs = "";
	$frozenqs = $allqueries->freeze() unless $q->param("frozenqs");
 	$qform_submit .= $q->hidden( {-name => "frozenqs",
				      -value => $frozenqs} );
    }

    #Save the ID of this query
    $qform_submit .= $q->hidden( -name => 'menu_or_query' );

    #Keep the menus unfolded
    if($expandeditems)
    {
	$q->param( expanded => (scalar(@$expandeditems) ? join (',', @$expandeditems) : '-' ));
	$qform_submit .= $q->hidden( { -name => "expanded" } );
    }

    #And finally the actual button
    $qform_submit .= $q->Button({ -name => "submit",
				  -id => "run_query",
				  -type => 'submit',
				  -value => "Run query" }, '<span class="buttontext">Run query</span>');

				 
    #Now the hard bit.  The template should provide the <form> tags, 
    #a containing table and a placeholder for $qform_submit.
    #I do the rest.
    require GenQuery::WebFormControls;
    my $control_maker = new GenQuery::WebFormControls($q, $this->get_current_runmode() eq 'query');
    my $param_count = $qobj->get_param_count();
    my @query_params;

    if(! $param_count)
    {
	push @query_params, { QUERY_PARAM_LABEL => "There are no parameters to set for this query" };
    }
    else
    {
	#Format the fields using the control maker.
	for my $id($qobj->get_param_ids())
	{
	    my $plabel = $qobj->get_param_info($id)->{param_text};
	    my $pcontrol = $control_maker->param_to_control($qobj, $id);
    
	    push @query_params, { QUERY_PARAM_LABEL => $plabel,
				  QUERY_PARAM_CONTROL => $pcontrol };
	}
    }
    
    $tmpl->param( DATE_PICKER_USED => $control_maker->date_picker_used() );
    $tmpl->param( QUERY_PARAM_COUNT => $param_count );
    $tmpl->param( QUERY_PARAMS => \@query_params );
    $tmpl->param( QUERY_FORM_SUBMIT => $qform_submit );
}

sub determine_query
{
    #When in the show_results mode we need to determine which query is to be run.
    my $this = shift;
    my ($allqueries) = @_;
    my $q = $this->query();

    my $query_id;
    #First see if menu_or_query is set.
    if($query_id = $q->param('menu_or_query'))
    {
	return $query_id;
    }

    if($query_id = $q->param('queryid'))
    {
	$q->param(menu_or_query => $query_id);
	return $query_id;
    }

    if(my $query_name = $q->param('queryname'))
    {
	$query_id = $allqueries->title_to_id($query_name);
	$q->param(menu_or_query => $query_id);
	return $query_id;
    }

    die "Cannot determine query from CGI input - nothing to run!\n";
}

sub add_exports_to_tmpl
{
    require GenQuery::ResultExporter;

    #TODO - I designed it so that the first export format would be the
    #default one - make it so!
    my ($this, $tmpl, $query_instance, $permalink, $link_postfix) = @_;
    my $config = $this->param('config');
    $permalink ||= $this->query_to_permalink();
    $link_postfix ||= '';

    #See what the export formats are, firstly by asking the query,
    #else by asking the configuration
    my $export_formats = $query_instance->get_export_formats()
			    || $config->get_param('export_formats');

    #Export options can be set by the configuration too, but currently not on a per-query basis.  
    #Format is:
    # exp_opt1=foo;exp_opt2=bar
    my $export_options = $config->get_param('export_options'); 
    $export_options = $export_options ? ";$export_options" : '';

    my @format_info = ();
    for(split(';', $export_formats))
    {
	my ( $exp_type, $exp_cname, $exp_longname ) = GenQuery::ResultExporter::get_info_for_exporter($_);

	if($exp_type eq 'results')
	{   
	    push @format_info => {  EXPORT_SHORT_NAME => $_,
				    EXPORT_LINK => "$permalink;rm=results${export_options}${link_postfix}",
				    EXPORT_LONG_NAME => $exp_longname };
	}
	elsif($exp_type eq 'text' || $exp_type eq 'binary')
	{
	    push @format_info => {  EXPORT_SHORT_NAME => $_,
				    EXPORT_LINK => "$permalink;rm=dl${export_options};fmt=$exp_cname",
				    EXPORT_LONG_NAME => $exp_longname };
	}
	elsif($exp_type eq 'graph')
	{
	    push @format_info => {  EXPORT_SHORT_NAME => $_,
				    EXPORT_LINK => "$permalink;rm=graph${export_options};fmt=$exp_cname$link_postfix",
				    EXPORT_LONG_NAME => $exp_longname };
	}
    }	

    $tmpl->param( EXPORT_FORMATS => \@format_info );
}

sub show_results
{
    my $this = shift;

    my $config = $this->param('config');
    my $q = $this->query();
    my $conn = $this->conn();
    my ($tmpl, $debug_mode, $res);

    #See if I want to be running in debug mode
    if($q->param('debug')  && !$config->get_param('disable_debug'))
    {
	$debug_mode = 1;
	$tmpl = $this->load_tmpl('debug.template.html') or die
		"Failed to load debug template - cannot run query in debug mode";
    }
    else
    {	
	#Fire up the template
	$tmpl = $this->load_tmpl('results.template.html') or die
		"Failed to load template - cannot show query results";
    }

    #Deserialise or load from database
    my $allqueries = $this->instantiate_queries();
    my $query_to_run = $this->determine_query($allqueries);
    my $queryinfo = $allqueries->get_info_by_id($query_to_run);
    my $thisquery = $allqueries->instantiate_by_id($query_to_run);

    #Right.  This is the run mode invoked to show the results.   
    #Depending on what is in the HTML template we may well be showing the menus 
    #and the query as well, so that is the first order of business.
    
    #Determine which menu is opened, ie the category of this query.
    my $current_category = $queryinfo->{category};

    #And 
    #First, what levels are expanded if using the tree view
    my $expanded = $this->sort_out_expansions(scalar($q->param('expanded')), 
					      $allqueries, 
					      $current_category);

    $tmpl->param( SHOWING_TOP_MENU => 0 ); 
    $tmpl->param( MENU_TITLE => $current_category );
    $this->add_menu_to_tmpl($tmpl, $allqueries, $current_category, $query_to_run, $expanded);

    #Now the part specific to running the query.
    #Pull out any qp_ parameters and feed them to the query
    $this->feed_parameters_to_query($thisquery);

    #Now having removed defaults add the actual query to the template
    $this->add_query_to_tmpl($tmpl, $queryinfo, $thisquery, $allqueries, $expanded);

    #How we do this depends on the debug mode.
    if($debug_mode)
    {
	eval{ $res = $thisquery->execute(); };

	#If there was an error grab it
	unless($res)
	{
	    $tmpl->param(PERL_ERROR => "@_");
	    $tmpl->param(LAST_DBI_ERROR => CGI::escapeHTML($conn->last_sql_error()));
	}

	$res ||= new GenQuery::ResultTable();
	$res->set_debug_mode(1);

	#Report the raw query
	$tmpl->param(UNPARSED_QUERY => $thisquery->get_raw_query());

	#Report the parameters
	$tmpl->param(DUMPED_QUERY_PARAMETERS =>
		join( "\n", map 
			{ 
				my $param_name = ($thisquery->get_param_info($_))->{param_name};
				$param_name . " => " . $thisquery->get_param_quoted($param_name);
			} $thisquery->get_param_ids()
		    ) );
    }
    else
    {
	$res = $thisquery->execute();
    }
    #In all cases report the actual query run - the template maintainer can use it or not
    $tmpl->param(LAST_SQL_COMMAND => $conn->last_sql_statement());

    #Set a bookmark for the pivot links
    my $link_postfix = $config->get_param('bookmarks_on_links') ? '#results' : '';
    $res->set_link_postfix($link_postfix);

    #Tell the ResultTable about any connection params for internal links
    $res->set_login_params($config->generate_persistence_hash());

    #Tell the result table which mode to use for checkbox columns, and add the
    #target URL and a submit button for new-style linkouts while we are at it.
    if($queryinfo->{linkout_target})
    {
	$this->add_newlinkout_to_tmpl($tmpl, $queryinfo->{linkout_target});
	$res->set_checkbox_pivot_mode(!($queryinfo->{linkout_target} =~ m{://}));
    }

    #See how many rows to put in table
    my $display_max_rows = $config->get_param('display_max_rows') || 2000;

    my $rt_head = $q->th($res->get_display_headings());
    my @rt_rows;
    while(my @arow = $res->get_next_row_html())
    {
	#Limit to 2000 rows - TODO support paging of results.
	if(@rt_rows > $display_max_rows)
	{
	    push @rt_rows, { ROW_DATA => 
			     $q->Tr($q->td({-colspan => scalar(@arow)},
				    "<i>Too many rows - stopping after $display_max_rows.</i>"))
		       };
	    last;
	}

	push @rt_rows, { ROW_DATA => join( "\n", $q->td([@arow]) ),
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
    my $permalink = $this->query_to_permalink();
    #TODO - download link should be replaced by export.
    $this->add_exports_to_tmpl($tmpl, $thisquery, $permalink, $link_postfix);

    $tmpl->param( PERMALINK => "$permalink;rm=results$link_postfix" );
    $tmpl->param( DOWNLOADLINK => "$permalink;rm=dl" );
    #This is handy if you are not showing the query form on the results page and want
    #to get back to the query form
    my $expanded_bit = '';
    if($expanded)
    {
	$expanded_bit = ';expanded=' . $q->escape(scalar(@$expanded) ? join (',', @$expanded) : '-' );
    }
    $tmpl->param( QUERYLINK => "$permalink;rm=query$expanded_bit" );
    $tmpl->param( MENULINK => "$permalink;rm=submenu$expanded_bit" );

    #Offer debug mode unless it was disabled
    unless($config->get_param('disable_debug'))
    {
	$tmpl->param( DEBUGLINK => "$permalink;rm=results;debug=1" );
    }

    #Old-style linkouts are probably deprecated, but in any case...
    #Add any old-style linkouts to the template
    if($debug_mode)
    {
	$tmpl->param(DUMPED_LINKOUTS => $this->dump_linkouts($thisquery->get_linkouts(), $res));
    }
    else
    {
	$this->add_linkouts_to_tmpl($tmpl, $thisquery->get_linkouts(), $res);
    }

    #Done
    $tmpl->output();
}

sub show_graph
{
    #Now here I don't actually run the query.  Instead basically do the same as show_query
    #and then generate a link to embed an image, calling gq in export mode.  Note this
    #won't work if authentication is needed and cookies are disabled.  To make it work I'd
    #need to re-implement logins with persistent session keys on the server, which I may well
    #want to do for web services anyway.
    my $this = shift();

    my $config = $this->param('config');
    my $q = $this->query();

    #Fire up the template
    my $tmpl = $this->load_tmpl('graph.template.html') or die
	    "Failed to load template - cannot show graph output";

    #Deserialise or load from database
    my $allqueries = $this->instantiate_queries();
    my $query_to_show = $this->determine_query($allqueries);
    my $queryinfo = $allqueries->get_info_by_id($query_to_show);
    my $thisquery = $allqueries->instantiate_by_id($query_to_show);

    #Depending on what is in the HTML template we may well be showing the menus 
    #as well, so that is the second order of business.
    
    #Determine which menu is opened, ie the category of this query.
    my $current_category = $queryinfo->{category};

    #And 
    #First, what levels are expanded if using the tree view
    my $expanded = $this->sort_out_expansions(scalar($q->param('expanded')),
					      $allqueries, 
					      $current_category);

    $tmpl->param( SHOWING_TOP_MENU => 0 ); 
    $tmpl->param( MENU_TITLE => $current_category );
    $this->add_menu_to_tmpl($tmpl, $allqueries, $current_category, $query_to_show, $expanded);

    #Now the actual query
    $this->feed_parameters_to_query($thisquery);
    $this->add_query_to_tmpl($tmpl, $queryinfo, $thisquery, $allqueries, $expanded);
    
    #Now offer other export formats and permalink
    my $permalink = $this->query_to_permalink();
    my $link_postfix = $config->get_param('bookmarks_on_links') ? '#results' : '';
    my $fmt = $q->param('fmt') || 'graph-default';

    $this->add_exports_to_tmpl($tmpl, $thisquery, $permalink, $link_postfix);

    #(TODO) should permalink be the graph link here?
    my $expanded_bit = '';
    if($expanded)
    {
	$expanded_bit = ';expanded=' . $q->escape(scalar(@$expanded) ? join (',', @$expanded) : '-' );
    }
    $tmpl->param( PERMALINK => "$permalink;rm=results$link_postfix" );
    $tmpl->param( QUERYLINK => "$permalink;rm=query$expanded_bit" );
    $tmpl->param( MENULINK => "$permalink;rm=submenu$expanded_bit" );

    #Now set up the graph link
    $tmpl->param( SHOWING_GRAPH => 1 );
    $tmpl->param( GRAPH_LINK => "$permalink;rm=dl;fmt=$fmt" );

    #Done
    $tmpl->output();
}

sub feed_parameters_to_query
{
    #Takes the CGI parameters and feeds them to the query object.  Does not actually
    #cause the SQL body to be produced.
    my ($this, $thisquery) = @_;
    my $q = $this->query();

    for( grep {/^qp_/} $q->param() )
    {
	(my $realname = $_ ) =~ s/qp_//;

	#Remember that there may be more than one value.
	my @val = $q->param($_);

	if(!@val)
	{
	    #Should never happen
	    die "Error: Assertion failed - param has zero values set."
	}
	elsif(@val > 1)
	{
	    $thisquery->set_param_by_name($realname => \@val);
	}
	else
	{
	    #Single param.  Check it is something real.
	    my ($val) = @val;

	    if(defined($val) and $val ne '' and $val ne $ALL)
	    {
		$thisquery->set_param_by_name($realname => $val);
	    }
	    else
	    {
		#Remove unset params so they don't get fed back to the query form
		#Unneccesary?  Having a side effect in this routine is not very neat!
		$q->delete($_);
	    }
	}
    }
}

sub add_newlinkout_to_tmpl
{
    #New-style linkouts using <checkbox or <passparam columns in the results.
    my $this = shift;
    my ($tmpl, $target) = @_;
    my $q = $this->query();
    my $config = $this->param("config");

    #First see if the target is a url or otherwise assume it's the name of a query
    if($target =~ m{://})
    {
	my( $url, $label ) = split(' ', $target, 2);
	$label ||= "Submit Query";

	#To make a relative URL just prefix :// - totally non-standard but easy to implement
	$url =~ s{^://}{};

	#Simple - the template supplies all the required gubbins.
	$tmpl->param(LINKOUT_TARGET => $url);
	$tmpl->param(LINKOUT_SUBMIT => $q->submit(-label=>$label));
    }
    else
    {
	#Point back to this script
	$q->delete('queryname');
	$tmpl->param(LINKOUT_TARGET => $q->url(-relative=>1,-query=>0));
	$tmpl->param(LINKOUT_SUBMIT => join("\n", $q->hidden(-name => 'rm', -value => 'results'),
						  $q->hidden(-name => 'queryname', -value => $target),
						  @{$config->generate_persistence_fields($q)}, 
						  $q->submit(-label=>$target)) );
    }
}

sub add_linkouts_to_tmpl
{
	my $this = shift;
	#If there are any linkouts defined for this query, generate the linkout and add it to the template.
	#I was thinking of skipping this if the template was not using linkouts, but it is hard to detect
	#because of the dynamically named parameter thing.
	#$linkouts will be a hashref but it may be empty.
	my ($tmpl, $linkouts, $res) = @_;

	my @all_linkouts;
	for(sort keys %$linkouts)
	{
	    my $linkout_info = $linkouts->{$_};
	    my ($url) = $res->generate_linkout($linkout_info->{url},
					       $linkout_info->{key_column},
					       $linkout_info->{pack});

	    #Add the links as both a list and as individual named items.  See design notes
	    $tmpl->param( "LINKOUT_$_" => $url );
	    push @all_linkouts, { LABEL => $linkout_info->{label}, 
				  URL => $url,
				  NAME => $_ };
	}

	$tmpl->param( LINKOUTS => \@all_linkouts );
}

sub dump_linkouts
{
    my $this = shift;
    #Similar to the above but for the debug mode.  Report the linkouts and if they worked
    my ($linkouts, $res) = @_;
    my $result = '';

    for(sort keys %$linkouts)
    {
	my $linkout_info = $linkouts->{$_};
	my ($url, $count);
	eval{ ($url, $count) = $res->generate_linkout(
					$linkout_info->{url},
					$linkout_info->{key_column},
					$linkout_info->{pack});
	};
	if($@)
	{
	    $result .= "$_ on '$linkout_info->{key_column}' - no such column in results.\n";
	}
	else
	{
	    $result .= "$_ on '$linkout_info->{key_column}' - collected up $count values.\n";
	}
    }
    $result || "No linkouts defined";
}		

sub download_results
{
    my $this = shift;
    my $q = $this->query();
    my $config = $this->param('config');
    #Similar to show_results

    #The mime type list for exporting was originally embedded in here, but I want to make 
    #it fully modular.
    #The result set should be able to export itself in a format, returning the MIME
    #type and the exported bytes.
    #Note that I now don't spot an invalid format until after the query has been
    #executed.

    #TODO - add more formats...
    my $fmt = $q->param('fmt') || 'CSV';
#     my $mimetype = $mimetypes{$fmt} or die "Illegal format $fmt.";

    my $allqueries = $this->instantiate_queries();
    my $query_to_run = $this->determine_query($allqueries);
    my $thisquery = $allqueries->instantiate_by_id($query_to_run);

    #Pull out any qp_ parameters and feed them to the query
    $this->feed_parameters_to_query($thisquery);

    my $res = $thisquery->execute();

    #Now allow some parameters to be passed through to export
    #Special case width and height
    my @exp_params = map { /^exp_(.*)/, $q->param($_) } grep(/^exp_/, $q->param() );
    push @exp_params, (height => $q->param('height'));
    push @exp_params, (width => $q->param('width'));

    #Also tell the exporter about the URL that generated it, minus login credentials
    my $export_options = $config->get_param('export_options'); 
    $export_options = $export_options ? ";$export_options" : '';
    $res->set_permalink($this->query_to_permalink(0,{-relative=>0,-full=>1}) . ";rm=dl${export_options};fmt=$fmt");

    my ($mimetype, $extension, $csv) = $res->export($fmt, {@exp_params});

    #Come up with a filename
    my $fname = $thisquery->get_info()->{title};
    $fname =~ tr/A-Za-z0-9/_/cs;
    $fname .= ".$extension"; 

    $this->header_add( -type => $mimetype );

    if($mimetype =~ /^text/)
    {
	$this->header_add( -content_disposition => "filename=$fname" );
    }
    elsif($mimetype =~ /^image/)
    {
	$this->header_add( -content_disposition => "filename=$fname" );
	binmode STDOUT, ':raw';
    }
    else
    {
	$this->header_add( -content_disposition => "attachment;filename=$fname" );
    }
    
    $csv;
}

sub query_to_permalink
{
    my $this = shift;
    my ($format, @urlopts) = @_;
    @urlopts = %{$urlopts[0]} if ref($urlopts[0]);
    my $q = $this->query();
    my $config = $this->param('config');

    #Return a link to re-run this query.  Currently works by stripping out some stuff from the query object so
    #to be safe I can copy the query before tinkering.
    #Maybe I should build the URL from scratch rather than going the other way?
    my $new_q = new CGI($q);
    
    #Don't want to know about username or password for DB - see find_all_params
    #which determines what goes and what stays.
    $new_q->delete( $config->find_all_params(0, 1) );

    #No need to keep the frozen queries
    $new_q->delete('frozenqs');

    #And some more
    $new_q->delete('rm');
    $new_q->delete('submit');
    $new_q->delete('debug');
    $new_q->delete('fmt');
    $new_q->delete('expanded');
    $new_q->delete(grep /\.[xy]$/, $new_q->param());

    #Also pack any query parameters that got too long...
    for($new_q->param())
    {
	if(/^qp_/ && @{$new_q->param_fetch($_)} >= 5000)
	{
	    require GenQuery::Util::ParamPacker;
	    (my $newname = $_) =~ s/^qp_/qpp_/;
	    $new_q->param($newname => GenQuery::Util::ParamPacker::param_pack($new_q->param_fetch($_)));
	    $new_q->delete($_);
	}
    }
    
    #TODO - should I link by query name or stick with ID?  Which is more likely to change?
    if(my $queryid = $new_q->param('menu_or_query'))
    {
	$new_q->param(queryid => $queryid);
	$new_q->delete('menu_or_query');
    }
    $new_q->param(fmt => $format) if $format;

    $new_q->url( {-relative=>1, -query=>1, @urlopts} );
}

1;
