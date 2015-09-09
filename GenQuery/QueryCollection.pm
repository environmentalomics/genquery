#!perl
use strict; use warnings;

#Represents a collection of queries and allows them to be filtered
#and instantiated as query objects.

package GenQuery::QueryCollection;
# use GenQuery::QueryInstance;

# use YAML; #For serialisation
use Data::Dumper; #For debuggeration

#The main structure held within this object will be an array of categories
#plus a hash of 
#category -> [ queries ] (q_by_cat) and also a hash of IDs to queries ( q_by_id )

sub new
{
    my $this = bless({} => shift);

    #Need to hold onto a GQConnection object or else an object on which I can
    #call $obj->conn() to get one (eg WebQuery).
    $this->{gqconn} = shift or die "No connection handle.";

    #Now the next param could be a string for me to deserialise or
    #else a hashref or undef to get an empty collection
    my $querydata = shift;
    $this->{categories} = [];
    $this->{q_by_cat} = {};
    $this->{q_by_id} = {};
    #Save munging the query def even more by keeping the dbids in a hash on their own
    #TODO - why is this here and not in the GQConnection?
    #Answer - because the QueryCollection needs to persist but the GQC gets trashed!
    $this->{query_db_map} = {}; 

    $this->{has_hidden} = 0;

    if(!defined($querydata))
    {
	#Nowt to do
    }
    elsif(ref($querydata) eq 'HASH')
    {
	$this->add_queries($querydata);
    }
    else
    {
	#Thaw some YAML or whatever
	$this->thaw($querydata);
    }

    $this;
}

sub add_queries
{
    my $this = shift;
    #Adds queries to the collection.  These could come straight from the config or
    #be coming out of the database or wherever see Configuration::get_all_queries.
    #Either we have one param which is
    #a hashref of dbid => %queries
    #or more than one param which can be built into one of those

    #FIXME - this is currently obliterating the old queries, I think!!

    my $stuff_to_add = (@_ == 1 ? $_[0] : {@_});

    #Get the connection handle so we can ask the names of databases
    my $conn = $this->{gqconn}->conn();

    #The hash is referenced first by database ID so a bit of folding is needed
    my $query_db_map = $this->{query_db_map}; 
    my $q_by_id = $this->{q_by_id};
    
    for my $dbid (keys %$stuff_to_add)
    {
	my $db_display_name = $conn->get_db_display_name($dbid);

	while( my($qid, $qinfo) = each %{$stuff_to_add->{$dbid}} )
	{
	    #Ensure that the query_id is actually held in the query object
	    $qinfo->{query_id} = $qid;

	    #TODO - dupe check!
	    #The original code meant that you had to ensure that all query IDs were
	    #unique across all databases and in the XML/SQL.  This is just making trouble!
	    #Solution - HACK!  For the purposes of hashing add a fractional offset.
	    while($q_by_id->{$qid}) {$qid += 0.01};

	    $q_by_id->{$qid} = $qinfo;
	    $qinfo->{query_hash_id} = $qid;
	    $qinfo->{database_name} = $db_display_name;
	    
	    $query_db_map->{$qid} = $dbid;
	}
    }

    #Rebuild query list each time as this is easier than inserting all the
    #lists in the right order.
    my $categories = $this->{categories} = [];
    my $q_by_cat = $this->{q_by_cat} = {};
	
    for(sort {$a <=> $b} keys(%$q_by_id))
    {
	my $thisline = $q_by_id->{$_};
	#Have we seen the category?
	unless($q_by_cat->{$thisline->{category}})
	{
	    push @$categories, $thisline->{category};
	    
	    $q_by_cat->{$thisline->{category}} = [];
	}
	push @{$q_by_cat->{$thisline->{category}}}, $thisline;

	$this->{has_hidden}++ if $thisline->{hide};
    }
}

sub get_categories
{
    my $this = shift;
    @{$this->{categories}};
}

sub get_db_name_for_category
{
    #A category may contain queries referencing more than one database.
    #Return either the display name of the database or multiple.
    #This is for display only and is not definitive.
    my $this = shift;
    my ($category) = @_;

    my $querylist = $this->{q_by_cat}->{$category};
    @$querylist or return 'none';

    my $database_name = $querylist->[0]->{database_name};
    for(@$querylist)
    {
	next unless defined($_->{database_name});
	$database_name ne $_->{database_name} and return "multiple";
    }

    $database_name;
}

sub get_by_category
{
    my $this = shift;
    my $cat = shift;
    
    #Quick version if there is only one:
    my @categories = $this->get_categories();
    @categories == 0 and return $this;
    @categories == 1 && $categories[0] eq $cat and return $this;

    #Filter and return
    my $newcollection = new GenQuery::QueryCollection($this->{gqconn});
    $newcollection->{query_db_map} = $this->{query_db_map};

    my $q_by_cat = $this->{q_by_cat}->{$cat} or return $newcollection;

    $newcollection->{categories} = [$cat];
    $newcollection->{q_by_cat} = { $cat => $q_by_cat };
    for(@$q_by_cat)
    {
	$newcollection->{q_by_id}->{$_->{query_hash_id}} = $_;
    }

    $newcollection;
}

sub get_non_hidden
{
    #Similar to get_by_category.  Filters all hidden queries.
    #Unfortunately I didn't make this easy for myself :-(
    my $this = shift;

    $this->{has_hidden} or return $this;
    my $q_by_cat = $this->{q_by_cat};
    my @categories = $this->get_categories();
    scalar(@categories) or return $this;
    
    my $newcollection = new GenQuery::QueryCollection($this->{gqconn});
    $newcollection->{query_db_map} = $this->{query_db_map};
    
    for my $cat(@categories)
    {
	my $arr = $q_by_cat->{$cat};
	my $copycount = 0;
	for(@$arr)
	{
	    unless($_->{hide})
	    {
		push @{$newcollection->{q_by_cat}->{$cat}}, $_;
		$newcollection->{q_by_id}->{$_->{query_id}} = $_;
		$copycount++;
	    }
	}
	$copycount and push @{$newcollection->{categories}}, $cat;
    }
    
    $newcollection;
}

sub title_to_id
{
    my $this = shift;
    my ($title_wanted) = @_;
    
    my $id_found;
    
    #Looks through the queries to find the ID for a given title.  This is not
    #indexed so a scan is required.
    while(my($id, $info) = each %{$this->{q_by_id}})
    {
	if($info->{title} eq $title_wanted)
	{
	    $id_found = $id;
	    last;
	}
    }

    $id_found or die "Cannot find a query with the title $title_wanted.\n";
}

sub get_query_ids
{
    my $this = shift;
    sort {$a <=> $b} keys %{$this->{q_by_id}};
}

# get_by_id returns a singleton collection by ID

sub get_by_id
{
    my $this = shift;
    my $idwanted = shift;

    my $newcollection = new GenQuery::QueryCollection($this->{gqconn});

    if(my $queryline = $this->{q_by_id}->{$idwanted})
    {
	$newcollection->{q_by_id}->{$idwanted} = $queryline;
	$newcollection->{categories} = [$queryline->{category}];
	$newcollection->{q_by_cat}->{category} = [$queryline];
	$newcollection->{query_db_map}->{idwanted} = $this->{query_db_map}->{idwanted};
    }

    $newcollection
}

sub get_info_by_id
{
    my $this = shift;
    my $idwanted = shift;

    $this->{q_by_id}->{$idwanted};
}

sub get_dbid_for_query_id
{
    my $this = shift;
    my $idwanted = shift;
    
    $this->{query_db_map}->{$idwanted};
}

sub instantiate_by_id
{
    require GenQuery::QueryInstance;
    my $this = shift;
    my $id = shift;

    #Allow singleton to be instantiated without ID
    if(!defined($id))
    {
	my @qlist = keys %{$this->{q_by_id}};
	$id = $qlist[0];
    }

    #Assertion
    my $qline = $this->{q_by_id}->{$id} or die "No such query with ID $id";

    my $qobj = new GenQuery::QueryInstance($this->{gqconn}, $this->{query_db_map}->{$id}, $qline);

    #Debug point
#     die "Assertion failed - Query object without ID!!\n",
#         Dumper($qline, $qobj) unless $qobj->{query_id};


    $qobj;
}

sub freeze
{
    my $this = shift;
    #Serialise $this ensuring that {gqconn} is left out
    require YAML;
    
    my %copy = (%$this);
    delete $copy{gqconn};

    YAML::Dump(\%copy);
}

sub thaw
{
    my $this = shift;
    my $encoded = shift;
    require YAML;

    my $decoded = YAML::Load($encoded);
    $this->{$_} = $decoded->{$_} for keys %$decoded;
}

1;
