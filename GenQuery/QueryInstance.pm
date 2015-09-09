#!perl
use strict; use warnings;

#Represents a single query associated with the GQConnection.
#May be parameterised and run.
package GenQuery::QueryInstance;
# use GenQuery::ResultTable;
use Data::Dumper;
use String::Tokenizer;

#What to put in an empty parameter (not the same as what is sent to the browser!!)
my $ALL = 'ALL';

#Constructor typically called by QueryCollection->instantiate()
sub new
{
    my $this = bless({} => shift());

    #Will be passed a connection handle and an info line.
    ($this->{gqconn}, $this->{dbid}, $this->{qinfo}) = @_;
    $this->{query_id} = $this->{qinfo}->{query_id};

    $this;
}

#Causes the list of parameters to be pulled from the database
#and cached.
sub load_paramlist
{
    my $this = shift();
    return if $this->{allparams};

    #Note that for XML lines qinfo may actually contain all the gubbins
    #and not just the basic info - so see if there is already a param list.
    if($this->{qinfo}->{query_param})
    {
	$this->{allparams} = $this->xml_query_params_to_allparams($this->{qinfo}->{query_param});
    }
    else
    {
	my $conn = $this->{gqconn}->conn();
	$this->{allparams} = $conn->get_params_for_query($this->{dbid}, $this->{query_id});
    }
}

sub xml_query_params_to_allparams
{
    my $this = shift;
    my ($query_param) = @_;

    #As you can probably guess from the long function name, this is a tidying-up function
    #which is only really useful to the function above.  It should probably be done within
    #the Configuration object but no matter.
    #So, take the hash from the XML and clean it up for use as the {allparams} hash within the
    #query object - note that the actual hash will be modified here.
    #If the user has not supplied id attributes then this will come through as an array.

    #I used to have a remap to permit short names but this is a misfeature as it just confuses things
    #and also upsets XML::Simple that wants to use the <name> element as a hash key.
    my($param_id, $param_hash);

    my $fixup = sub
    {
	#Set param_no
	$param_hash->{param_no} = $param_id;
	#And put in a default name if needed, same as above
	$param_hash->{param_name} ||= "PARAM" . $param_hash->{param_no};
	#Set empty option list if there is no menu_query
	unless($param_hash->{menu_query} || $param_hash->{option})
	{
	    $param_hash->{option} = [];
	}
	#Fix suppress_all
	$param_hash->{suppress_all} = (($param_hash->{suppress_all} || '') =~ /yes|true|1/i);
    };

    if(ref $query_param eq 'ARRAY')
    {
	for( my $nn = 0; $nn < @$query_param; $nn++)
	{
	    $param_hash = $query_param->[$nn];
	    $param_id = $nn + 1;

	    &$fixup();
	}
	#Return a hashref mapped by param_no
	return { map { $_->{param_no} => $_ } @$query_param };
    }
    elsif(ref $query_param eq 'HASH')
    {
	while( ($param_id, $param_hash) = each %$query_param )
	{
	    &$fixup();
	}
	return $query_param;
    }
    else
    {
	die "ref(\$query_param) = " . ref($query_param);
    }
}

#Causes all mutiple choice params to be pulled from the database
#and cached.
sub load_paramvals
{
    my $this = shift();
    return if $this->{allparamvals};
    $this->load_paramlist();

    my $pvals = $this->{allparamvals} = {};
    #Looping over all param numbers for this query
    while( my($key,$param_info) = each %{$this->{allparams}} )
    {
	#See if there is an option list (in the XML)
	if($param_info->{option})
	{
	   $pvals->{$key} = $param_info->{option};
	   next;
	}
	
	#Get from database (works for XML or SQL but if IDs collide then you'll
	#get unexpected results!)
	$pvals->{$key} = $this->{gqconn}->conn()->get_values_for_param(
							    $this->{dbid}, 
							    $this->{query_id}, 
							    $key,
							    $param_info->{menu_query});
    }
}

#Causes the SQL body of the query to be fetched from the database
sub load_body
{
    my $this = shift();
    my $qinfo = $this->{qinfo};
    return if exists $qinfo->{query_body};
    
    my $conn = $this->{gqconn}->conn();
    my $bandh = $conn->get_body_and_headings_for_query($this->{dbid}, $this->{query_id});
    @$qinfo{qw(query_body column_head export_formats)} = @$bandh;
}

#Causes the linkouts table to be pulled from the database
# TODO - obsolete??
sub load_linkouts
{
    my $this = shift;
    my $qinfo = $this->{qinfo};
    return if exists $qinfo->{query_linkout};

    my $conn = $this->{gqconn}->conn();
    $qinfo->{query_linkout} = $conn->get_linkouts_for_query($this->{dbid}, $this->{query_id});
}

sub get_info
{
    shift->{qinfo};
}

#How many parameters does this query take?
sub get_param_count
{
    my $this = shift();

    $this->load_paramlist();
    scalar(keys %{$this->{allparams}});
}

#And what are the associated IDs?
sub get_param_ids
{
    my $this = shift();

    $this->load_paramlist();
    sort {$a <=> $b} keys %{$this->{allparams}};
}

#For the given param returns a hashref with the following info:
# param_name
# param_label
# param_type (TEXT, MENU, etc.)
# value (current value as set below)
sub get_param_info
{
    my $this = shift();
    my $param_id = shift();
    
    $this->load_paramlist();
    
    $this->{allparams}->{$param_id};
}

#What are the possible values, in the case of a dropdown?
sub get_param_values
{
    my $this = shift();
    my $param_id = shift();

    $this->load_paramvals();

    my $vals = $this->{allparamvals}->{$param_id};

    $vals ? @$vals : ();
}

#What linkouts are defined for this query - in the same vein as above
sub get_linkouts
{
    my $this = shift;

    $this->load_linkouts();

    $this->{qinfo}->{query_linkout};
}

#Retrieve the name, category and description
#Not supported - get them from the collection object!
# sub get_name;
# sub get_category;
# sub get_description;

#To actually run the query:

#Set a parameter value
#If you set an unknowm param it will be bunged in the hash and then ignored.
#You can use a param within the query which is not in query_param table,
#which is handy for advanced pivot querying or custom direct links.
sub set_param_by_name
{
    my $this = shift();
    my ($param_name, $value) = @_;

    $this->{setparamvals}->{$param_name} = $value;
}

#Convenience to set by names - will revisit if I need a "getParamByName"
sub set_all_params_by_name
{
    my $this = shift();
    my ($paramhash) = @_;
    
    while(my($key, $val) = each %$paramhash)
    {
		$this->set_param_by_name($key, $val);
    }
}

sub set_param_by_id
{
    my $this = shift();
    my ($param_id, $value) = @_;
    $this->load_paramlist();

    $this->set_param_by_name($this->{allparams}->{$param_id}->{param_name}, $value);
}

sub get_raw_query
{
    #Utility methd to peek at the raw query
    my $this = shift;

    $this->load_body();

    $this->{qinfo}->{query_body};
}

sub get_processed_query
{
    #Utility method to drop in parameters and return query
    #basically a dummy execution.
    my $this = shift;
    my $qinfo = $this->{qinfo};
    $this->load_body();

    $qinfo->{query_body} or return undef;

    $this->drop_in_params($qinfo->{query_body}, $this->{setparamvals});
}

sub get_export_formats
{
    #Find out what formats this query wants to be exported in
    my $this = shift;
    $this->load_body();

    $this->{qinfo}->{export_formats};
}

sub execute
{
    require GenQuery::ResultTable;

    my $this = shift;
    my $conn = $this->{gqconn}->conn();
    my $qinfo = $this->{qinfo};
    $this->load_body();

    #Assert
    $qinfo->{query_body} or die "No query to execute.  Maybe this is an URL link query?\n";

    my $query = $this->drop_in_params($qinfo->{query_body}, $this->{setparamvals});

    #Debug
# 	die "query: $query";

    my $res = eval{
	GenQuery::ResultTable->new($conn->selectall_gq($this->{dbid}, $query), 
				   $qinfo->{column_head}, 
				   $this->{setparamvals});
    };

    $res or die "Failed to generate a table of results running query \"$this->{qinfo}->{title}\" with " .
		scalar(keys %{$this->{setparamvals}}) . " input parameters.  Check SQL syntax.\n$@";
}

sub get_param_quoted
{
    my $this = shift;
    my ($paramname, $setparams) = @_;

    #This is used by drop_in_params below and also by the debugger to dump
    #the params held by the query.
    #When called from drop_in_params, $setparams will be provided, otherwise
    #grab it.
    $setparams ||= $this->{setparamvals};

    my $conn = $this->{gqconn}->conn(); #Needed for quoting
    my $dbid = $this->{dbid};		   #Ditto

    if(defined($setparams->{$paramname}))
    {
	if(ref($setparams->{$paramname}) eq 'ARRAY')
	{
	    return join(', ', map {$conn->quote($dbid, $_)} @{$setparams->{$paramname}});
	}
	else
	{
	    return $conn->quote( $dbid, $setparams->{$paramname} );
	}
    }
    else
    {
	return $conn->quote( $dbid, $ALL ); #The database $ALL is not the same as the web $ALL!
    }
}

sub drop_in_params
{
    my $this = shift();
    my ($query, $setparams) = @_;

    #So take the query and replace:
    #$PARAM => quoted value or quoted values joined with commas
    #$_PARAM => unquoted value - EEK! Vulnerable to SQL injection and quoting foul-ups
    #           Only use this if you are happy with your DB security and are basically content
    #           to allow arbitrary queries.  In fact if you set the query to simply "$_PARAM1" then that
    #           is just what you get!
    #$?PARAM{{ ... }} => include only if PARAM is set
    #$!PARAM{{ ... }} => include only if PARAM is not set
    #Warning - this subroutine may contain magic.  It should ignore special characters
    #quoted within strings, and it should deal correctly with arbitrary nesting, but it's
    #a little hard to follow.

    #First off, single or double quotes in comments will still be detected as string
    #delimiters so -- don't do this! ("This'd be ok")
    #I could try to purge comments but this is hard because I need to make sure that what
    #looks like a comment isn't quoted, including being part of a multi-line string.
    # $query =~ s/(^|\n)\s*--.*?($|\n)//g; ## looks good but no dice!
    
    my $st = String::Tokenizer->new(
                $query,
		q{,()'"=:},
		String::Tokenizer->RETAIN_WHITESPACE
	     );
    
    my $newquery = '';
    my ($insq, $indq, $exclude) = 0; 

    #DEBUG
#     die(join "\n", $st->getTokens());
    
    my $st_iter = $st->iterator();
    while($st_iter->hasNextToken())
    {
	my $tok = $st_iter->nextToken();
	
	#Detect when within a quoted string.  In SQL quotes always balance so this
	#is reasonably easy.
	if($tok eq q{'} && !$indq)
	{
		$insq = !$insq;
	}
	elsif($tok eq q{"} && !$insq)
	{
		$indq = !$indq;
	}

	unless( $indq || $insq )
	{
		#Detect a simple variable sub - $FOO or $_FOO
		if($tok =~ /\$(\w+)/)
		{
			$1 =~ /(_?)(\w+)/ or die "_";
			
			#So $1 now tells me whether to quote or not.
			if($1)
			{	
				if(defined($setparams->{$2}))
				{
					if(ref($setparams->{$2}) eq 'ARRAY')
					{
						#Erm?  Space separated seems the best option
						$tok = join(' ', @{$setparams->{$2}});
					}
					else
					{
						#So in goes the unfiltered string.  
						$tok = $setparams->{$2};
					}
				}
				else
				{
					$tok = '';
				}
			}
			else
			{
				$tok = $this->get_param_quoted($2, $setparams);
			}
		}
		#Detect a conditional include - $?FOO
		elsif($tok =~ /\$\?(\w+)(\{\{)/)
		{
			if($exclude || !defined($setparams->{$1}))
			{
				$exclude++;
			}
			$tok = '';
		}
		#Very similar for a negated conditional include $!FOO
		elsif($tok =~ /\$\!(\w+)(\{\{)/)
		{
			if($exclude || defined($setparams->{$1}))
			{
				$exclude++;
			}
			$tok = '';
		}
		elsif($tok =~ /\}\}/)
		{
			$exclude-- if $exclude;
			$tok = '';
		}
	}

	$newquery .= $tok unless $exclude;
    }

    $newquery;
}

1;
