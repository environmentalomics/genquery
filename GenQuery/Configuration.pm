#!perl
use strict; use warnings;

#This manages the configuration, which consists of stuff from the
#config file and user supplied parameters as defined in the config
#file and gleaned from the query object.
package GenQuery::Configuration;

use XML::Simple;
our @booleans = qw(cache_queries bookmarks_on_links always_show_query disable_debug);
our @keyattrs = qw(id name);
our @arrays = qw(db_connection query_category query_definition query_param query_linkout prompt option);

use Data::Dumper;

#Some defaults to supply if they are not specified in the XML
#Not currently using this for anything as database names are dynamically
#generated.
#Now used for default 'export_formats' list
my %DEFAULT = (
    #display name for a database
#     display_name => "Default database",
    #what formats can we export these results in?
    export_formats => 'html;csv',
    login_cookies => 'no',
);

sub new
{
    bless { c => {} } => shift();
}

sub get_xml_reader
{
    #Shunted to a separate function so that I can get a correctly
    #configured reader for GQ-Edit without resorting
    #to cut-and-paste.

    new XML::Simple(ForceArray => \@arrays, 
		    KeepRoot => 0, 
		    KeyAttr => \@keyattrs,
		    SuppressEmpty => undef );
}

sub load_config
{
    my $this = shift;
    my ($configfile) = @_;
    my $conf = {};

    #Configfile can be a hashref - copy it
    if(ref($configfile) eq 'HASH')
    {
	$conf = $configfile;
    }
    else
    {
	#Load via XML::Simple
	my $xs = $this->get_xml_reader();

	eval{
		$conf = $xs->xml_in($configfile);
	} or die "Failed to load configuration from $configfile.  The error reported ",
		 "by the XML parser was:\n\n", split(/at \/.+/, $@);
    }
    die "Config file '$configfile' seems to be missing or empty - no configuration loaded." unless %$conf;

    $this->{c} = $conf;

    #Convert flags to boolean
    for( @booleans )
    {
	$conf->{$_} = ($conf->{$_} && $conf->{$_} !~ /no/i );
    }

    #Ensure login_cookies is not undefined, though it can be any string
    #and I'll let it pass.
    $conf->{login_cookies} = ($conf->{login_cookies} || $DEFAULT{login_cookies});

    #TODO
    #If there is just one DB connection and it does not have an ID then set it to
    #ID=0
}

sub set_from_env
{
    #Similar to set_from_cgi below but looks in the ENV VARS
    my $this = shift;
    my $conf = $this->{c};
    my $envparamsgot = 0;

    #Set any settables
    for my $pname ($this->find_all_params(1,1))
    {
	(my $envname = $pname) =~ tr/A-Za-z0-9_/_/c;
	my $pval = $ENV{"gq_$envname"};

	#If I found a parameter then store it.
	#All of these should have a colon - ie be DB specific - but I may change my
	#mind later so allow it either way
	if(defined $pval)
	{
	    if($pname =~ /(.+?):(.+)/)
	    {
		$conf->{db_connection}->{$1}->{$2} = $pval;
	    }

	    #Always store in {c} - makes it easier to generate cookies and links
	    $conf->{$pname} = $pval;

	    $envparamsgot++;
	}
    }

    $this->{PARAMSGOT} = $envparamsgot;
}

sub set_from_cgi
{
    my $this = shift;
    my $conf = $this->{c};
    my $q = shift;
    my $cgiparamsgot = 0;

    #Sets from params and from cookies.  CGI trumps cookie.
    
    #A prompt in the config looks like this:
    # {
    # 'prompt_longtext' => 'Your PostgreSQL User Name',
    # 'input_type' => 'TEXT',
    # 'item' => 'db_user',
    # 'keep_in_links' => 'yes',
    # 'prompt_text' => 'User Name',
    # 'rank' => '1'
    # }

    #Set any settables
    for my $pname ($this->find_all_params(1,1))
    {
	my $pval = $q->param($pname);

	#If there is no CGI param maybe there is a cookie?
	unless( defined($pval) || $conf->{login_cookies} eq 'no' )
	{
	    $pval = $q->cookie($pname);
	}
	
	#If I found a parameter then store it.
	#All of these should have a colon - ie be DB specific - but I may change my
	#mind later so allow it either way
	if(defined $pval)
	{
	    if($pname =~ /(.+?):(.+)/)
	    {
		$conf->{db_connection}->{$1}->{$2} = $pval;
	    }

	    #Always store in {c} - makes it easier to generate cookies and links
	    $conf->{$pname} = $pval;

	    $cgiparamsgot++;
	}
    }

    $this->{PARAMSGOT} = $cgiparamsgot;
}

sub get_param
{
    #Get a global param from the config file
    my $this = shift;
    my $conf = $this->{c};
    my $pname = lc(shift);

    my $res = $conf->{$pname};
    defined($res) ? $res : $DEFAULT{$pname};
}

sub get_db_param
{
    #Get a parameter or hash of all parameters relating to a database, by number
    my $this = shift;
    my $conf = $this->{c};
    my ($dbid, $pname) = map lc, @_;

    #TODO - is this the right place to be scrubbing the config??
    $dbid ||= 0;

    if($pname)
    {
	my $res = $conf->{db_connection}->{$dbid}->{$pname};
	return defined($res) ? $res : $DEFAULT{$pname};
    }

    #else - shallow copy and add defaults
    my %result = %{$conf->{db_connection}->{$dbid}};
    for(keys %DEFAULT)
    {
	$result{$_} = $DEFAULT{$_} unless defined($result{$_});
    }
    \%result;
}

sub get_db_display_name
{
    my $this = shift;
    my $conf = $this->{c};

    my ($dbid) = @_;
    my $db_conf = $conf->{db_connection}->{$dbid || 0};

    #Special function because if the display name is not set I want to generate one
    my $display_name = $db_conf->{display_name};
    
    if(!$display_name)
    {
	my $db_name = $db_conf->{db_name} || 'default';
	my $db_host = $db_conf->{db_host} || '[local]';
	$display_name = "$db_name\@$db_host";
    }
    $display_name;
}

sub get_db_ids
{
    my $this = shift;
    my $conf = $this->{c};

    sort keys %{$conf->{db_connection}};
}

sub get_all_queries
{
    my $this = shift;
    my $conf = $this->{c};

    #This needs to remap all the queries into the form
    #$queries->{dbid}->{qid}->query
    #So I need to fold the category into the query
    
    my $res = {};
    my $categories = $conf->{query_category} or return $res;
    
    for my $category(keys %$categories)
    {
	for my $queryid(keys %{$categories->{$category}->{query_definition}})
	{
	    my $query = $categories->{$category}->{query_definition}->{$queryid};

	    my $dbid = $query->{database}->{id} || 0;

	    #Shallow copy
	    my $query_copy = $res->{$dbid}->{$queryid} = {%$query};
    
	    #Fold in category
	    $query_copy->{category} = $category;

	    #Set empty query_param list if there is none - fixes
	    #bug where parameters for an unrelated query with the same ID can be fetched
	    #from the DB - see design.txt on 9/5/07
	    $query_copy->{query_param} ||= [];

	    #If both a query_url and a query_body are supplied move query_url to
	    #linkout_target
	    if($query_copy->{query_url} && $query_copy->{query_body})
	    {
		    $query_copy->{linkout_target} = $query_copy->{query_url};
		    $query_copy->{query_url} = undef;
	    }
	}
    }

    $res;
}

sub needs_user_params
{
    #Are there any user params to be queried?
    #Run through the connections and return 1 as soon as one is spotted
    my $this = shift;
    my $conf = $this->{c};
    for( values (%{$conf->{db_connection}}) )
    {
	return 1 if $_->{prompt};
    }
    return 0;
}

sub has_user_params
{
    #Have user params been queried?
    my $this = shift;
    $this->{PARAMSGOT};
}

sub validate_all_params
{
    #Die with an error if any params are problematic.
    #Error will describe all the problems.
    my $this = shift;
    my $conf = $this->{c};

    #Check that any params supplied from a list are actually in
    #that list.
    #This is a security measure to stop a naughty user feeding
    #spurious options back from the login form.
    for my $db ( keys (%{$conf->{db_connection}}) )
    {
	my $prompt = $conf->{db_connection}->{$db}->{prompt} or next;
	
	for(@$prompt)
	{
	    #Now $_ is a hashref and we care about the keys item and options
	    my $item = $_->{item};
	    my @options;
	    @options = @{$_->{option}} if $_->{option};
	    
	    if(@options)
	    {
		    my $setval = $conf->{db_connection}->{$db}->{$item};
		    grep {$setval eq $_} @options or
			    die "Illegal value $setval for $item for database " . 
			    $this->get_db_display_name($db) . ".\n"
	    }
	}
    }
    
    #Either die or return 1
    1;
}

sub generate_html_prompts
{
    #Generate the array of gubbins that we pass to the
    #template loop to display the login form in the HTML.
    my $this = shift;
    my $conf = $this->{c};
    my $q = shift; #A CGI object to help generate the form elements.

    my @fields; #Array of input fields to return
    my @database_ids = sort keys (%{$conf->{db_connection}});

    #TODO - have a nice cup of tea

    for my $db ( @database_ids )
    {
	my $prompt = $conf->{db_connection}->{$db}->{prompt} or next;
	
	for my $prompt (@$prompt)
	{
	    my $p = {
		LOGIN_FIELD_LABEL => $prompt->{prompt_text},
		LOGIN_FIELD_NOTES => $prompt->{prompt_longtext} || ''
	    };

	    if( scalar(@database_ids) > 1 )
	    {
		$p->{LOGIN_FIELD_LABEL} .= " for " . $this->get_db_display_name($db);
	    }

	    #Need to see if there is more than one DB and if so add the DB name to the prompts.
	    #Also add the DB ID to the field name.
	    
	    if($prompt->{input_type} eq 'MENU')
	    {
		$p->{LOGIN_FIELD_INPUT} = $q->popup_menu( 
					-name => "$db:$prompt->{item}",
					-values => [@{$prompt->{option}}],
					-default => $this->get_db_param($db, $prompt->{item})
				      );
	    }
	    elsif($prompt->{input_type} eq 'PASS')
	    {
		$p->{LOGIN_FIELD_INPUT} = $q->password_field(
					-name => "$db:$prompt->{item}",
				      );
	    }
	    else
	    {
		$p->{LOGIN_FIELD_INPUT} = $q->textfield(
					-name => "$db:$prompt->{item}",
					-default => $this->get_db_param($db, $prompt->{item})
				      );
	    }

	    push @fields, $p;
	} #end for prompts
    } #end for databases

    \@fields;
}

sub find_all_params
{
    my $this = shift;
    my $conf = $this->{c};
    my ($kept, $unkept) = @_;

    #So, to re-iterate, some parameters like schema or query_defs probably
    #want to be preserved and added to links.  Others like user name and
    #especially password want to be left out but do want to be persisted in
    #session cookies or POSTed as a backup to maintain the session.
    #
    #So the rule is that if the param is not a PASS type and has keep_in_links
    #set then it is kept, else it is 'unkept'.
    #Return will be an array of names.  If you pass 0, 0 then the array
    #will be empty!
    my @res;

    for my $db ( sort keys (%{$conf->{db_connection}}) )
    {
	my $prompt = $conf->{db_connection}->{$db}->{prompt} or next;

	for(@$prompt)
	{
	    #Now $_ is a hashref and we care about the keys item and options
	    my $iskept = ($_->{input_type} ne 'PASS' && $_->{keep_in_links} && $_->{keep_in_links} ne 'no');
	    
	    if( $iskept ? $kept : $unkept )
	    {
		push @res, "$db:$_->{item}";
	    }	    
	}
    }
    @res;
}

sub generate_persistence_hash
{
    #Subtly different to getting the fields because I need to explicitly find the values
    #rather than just spitting out placeholder hidden fields and relying on CGI.pm to
    #fill them in.  Could get the values from the query or the config - it matters not.
    my $this = shift;
    my $result = {};

    #If login_cookies is set to 'yes' then skip the unkept (db_user and db_pass) fields.
    my $skiplogins = ($this->{c}->{login_cookies} eq 'yes');

    for($this->find_all_params(1, !$skiplogins))
    {
	$result->{$_} = $this->get_param($_);
    }
    $result;
}

sub generate_persistence_fields
{
    #Need a set of hidden fields which carry all the login stuff
    my $this = shift;
#     my $conf = $this->{c};
    my $q = shift; #A CGI object to help generate the form elements.

    #If login_cookies is set to 'yes' then skip the unkept (db_user and db_pass) fields.
    my $skiplogins = ($this->{c}->{login_cookies} eq 'yes');

    my @fields;

    for($this->find_all_params(1, !$skiplogins))
    {
	#Do I need to explicitly push conf value into CGI object?  That should not be
	#necessary.
	push @fields, $q->hidden( -name => $_ );
    }

    \@fields;
}


sub generate_login_cookies
{
    my $this = shift;
    my ($q) = @_;
    my $conf = $this->{c};

    #This should only be called if:
    # 1) Cookies are turned on in the config
    # 2) Login to the database succeeded
    # Therefore not much checking needed
    
    #Arbitrary 2 hour expiry

    my @cookies;
    for( $this->find_all_params(0, 1) )
    {
	push @cookies,
		 $q->cookie(-name => $_,
		-value => $conf->{$_},
		-expires=>'+2h',
		-path=> $q->url(-absolute => 1) );
    }
    \@cookies;
}

sub clear_login_cookies
{
    my $this = shift;
    my $q = shift;

    #This should only be called if:
    # 1) Cookies are turned on in the config
    # 2) Login to the database failed and the login page is being shown
    # Therefore not much checking needed
    
    my @cookies;
    for( $this->find_all_params(0, 1) )
    {
	push @cookies,
	     $q->cookie(-name => $_,
			-value => '',
			-expires=> '-1d',
			-path=> $q->url(-absolute => 1) );
    }
    \@cookies;
}

1;
