#!perl
use strict; use warnings;

#This represents a table of results returned from the database.  Basically an active statement handle.
#Or I could just do a fetchall and hold onto the result.

#In the end, this class ends up containing quite a bit of HTML-specific CGI logic 
#for the special column feature.

package GenQuery::ResultTable;

use constant NONE => 0;
use constant LINKNOTERMS => 1;
use constant LINKWITHTERMS => 2;
use constant PIVOTQUERY => 3;
use constant HIDE => 4;
use constant CHECKBOX => 5;
use constant PASSPARAM => 6;

use CGI qw(a i td checkbox escapeHTML);
#use Data::Dumper;

our $ResultExporter = 'GenQuery::ResultExporter';

sub new
{
    my $this = bless( {} => shift() );

    my($colhead, $paramvals);
    ($this->{res}, $this->{names}, $this->{types}, $colhead, $paramvals) = @_;
    $this->{nextline} = 0;

    #Default constructor
    #If no arguments are supplied, the result table should be a valid object with
    #zero rows and a single column named 'empty'
    if(!@_)
    {
	$this->{res} = [];
	$this->{names} = ['empty'];
	$this->{types} = [undef];		#TODO - think about this when I actually use the types.
    }

    #Currently I use fetchall_arrayref to get all the data in one go, and hold it in
    #{res}.  If the database is returning more than 2000 rows, and I'm only diplaying the first
    #2000, then it should make sense to only fetch 2000.  Problem is, the DBD::Pg manual says:
    # ...Hence the "execute" method fetches all data at once into data structures located in the
    #  front-end application. This approach must to be considered when selecting large amounts 
    #  of data!
    #In other words, you can't win!

    my @newheadings = ();
    my $colhead_size = 0;
    my $needtermslink = 0;
    my @flags = ();

    #Go through headings and find special columns
    if($colhead)
    {
	my @headings = split_headings($colhead);
	$colhead_size = scalar(@headings);

	for(@headings)
	{
	    ($_ eq '<linknoterms' || $_ eq '<link') and push(@flags, LINKNOTERMS), next;
	    
	    $_ eq '<linkwithterms' and push(@flags, LINKWITHTERMS),
							       $needtermslink = 1,
							       next;
	    
	    $_ eq '<pivotquery' and	push(@flags, PIVOTQUERY), next;
	    
	    $_ eq '<hide' and push(@flags, HIDE), next;
	    
	    $_ eq '<checkbox' and push(@flags, CHECKBOX), next;

	    $_ eq '<passparam' and push(@flags, PASSPARAM), next;

	    push @flags, NONE;
	    push @newheadings, $_;
	}
    }
    for(my $nn = $colhead_size; $nn < @{$this->{names}}; $nn++)
    {
	push @newheadings, ucfirst($this->{names}->[$nn]);
	push @flags, NONE;
    }
    $this->{column_flags} = \@flags;
    $this->{column_head} = \@newheadings;

    #See if I need a CGI object to do a terms link or a pivot link
    if($needtermslink)
    {
	my $tl = new CGI($paramvals);
	$this->{termslink} = $tl->query_string();
    }
    $this->{link_postfix} = '';
    $this->{permalink} = '';

    $this->{checkbox_pivot_mode} = 1;

    $this;
}

sub split_headings
{
    #Previously just split on semicolon, but there is a problem - the columns go into 
    #the HTML unquoted so you may want to manually escape a character like &lt; or &amp; 
    #but then this gets split because of the semicolon.  Therefore look out for &xxx; and re-join.
    #If you want to put in a literal semicolon use '&#59;'
    my @res;
    for(split(';', $_[0]))
    {
	if($res[-1] && $res[-1] =~ /&[A-Za-z0-9#]+$/)
	{
	    $res[-1] .= ";$_";
	}
	else
	{
	    push @res, $_;
	}
    }
    @res;
}

sub set_link_postfix
{
    #A bit of a kludge, but I wanted a way to tell a ResultTable object that when
    #it generates pivot links it should append #results to the end so that the links
    #don't jump the user to the top of the page

    my $this = shift;
    $this->{link_postfix} = shift;
}

sub set_link_base
{
    #And a similar one for linking pivots to a page other than the calling page - needed
    #for embedding.
    
    my $this = shift;
    $this->{link_base} = shift;
}

sub set_link_max_param_length
{
    #Also a kludge.  Tries to prevent big long text fields from getting into
    #the pivot query.  It is unlikely that anything more than about 75
    #chars would want to be fed into a pivot so that is the default.
    my $this = shift;
    $this->{link_max_param_length} = shift;
}

sub set_checkbox_pivot_mode
{
    #Tells the result table that when generating checkboxes the parameter name
    #should have 'qp_' tacked on the beginning.  Default is on.
    my $this = shift;
    $this->{checkbox_pivot_mode} = shift;
}

sub set_login_params
{
    #When making a pivotquery link, if the user has supplied credentials
    #to log in to the database then these need to be preserver in the link, just
    #like for a permalink.  The problem is that the ResultTable has no link back to
    #the configuration to find these out, so as with the above allow relevant values to be
    #poked through from the caller as a hashref.
    my $this = shift;
    $this->{database_login_parameters} = shift;
}

sub set_debug_mode
{
    #And yet another.  This tells the output functions get_display_headings
    #and get_next_row_html to return data in debug format
    #so people can get a better view of what their queries are doing.
    #- All hidden/special columns are included
    #- All column headings have the internal name in brackets
    my $this = shift;
    ($this->{debug_mode}) = @_;
}

sub set_permalink
{
    #And here comes another.  You can tell this ResultSet about a permalink
    #to itself.
    my $this = shift;
    ($this->{permalink}) = @_;
}

sub get_display_headings
{
    my $this = shift;

    if($this->{debug_mode})
    {
	my @res = ();
	#Copy these arrays
	my @extheads = @{$this->{column_head}};
	my @intheads = @{$this->{names}};

	#Go through all the flags and recreate them
	for my $flag (@{$this->{column_flags}})
	{
	    $flag == NONE and push(@res, shift(@extheads) . " (" . shift(@intheads) . ")"), next;
	    $flag == LINKNOTERMS and push(@res, "<i>&lt;linknoterms</i> (" . shift(@intheads) . ")"), next;
	    $flag == LINKWITHTERMS and push(@res, "<i>&lt;linkwithterms</i> (" . shift(@intheads) . ")"), next;
	    $flag == PIVOTQUERY and push(@res, "<i>&lt;pivotquery</i> (" . shift(@intheads) . ")"), next;
	    $flag == HIDE and push(@res, "<i>&lt;hide</i> (" . shift(@intheads) . ")"), next;
	    $flag == CHECKBOX and push(@res, "<i>&lt;checkbox</i> (" . shift(@intheads) . ")"), next;
	    $flag == PASSPARAM and push(@res, "<i>&lt;passparam</i> (" . shift(@intheads) . ")"), next;
	}

	return \@res;
    }

    $this->{column_head};
}

sub get_internal_headings
{
    my $this = shift;
    $this->{names};
}

#TODO - make use of this info in Excel/webRowSet export
sub get_types
{
    my $this = shift;
    $this->{types};
}

sub _escape
{
    #A wrapper for escapeHTML which fixes newlines.
    my ($val) = @_;
    return $val unless $val; #Return undefs, empty string etc. as-is
    (my $res = CGI::escapeHTML($val)) =~ s/\n/<br \/>/g;
    $res;
}

sub _make_checkbox
{
    #A macro to make a checkbox given various bits of info, used below
    my ($labelcol_name, $label, $labelcol_val, $cbcol_val, $nextflag, $pivot_mode) = @_;

    #Ensure that there is no flag on the next column.
    if($nextflag && $nextflag != HIDE)
    {
	#Drastic but there you go...
	die "Query error: the column following a &lt;checkbox must be a regular column.  
	     To get a column which has both a link and a checkbox, put the link first.\n";
    }

    #Now I'm taking the name of the parameter from the column head just like with pivots,
    #but if the link is a query name I want to set the parameter to qp_XXX and otherwise I 
    #probably want to leave it as just Xxx.  For now make everything qp_XXX.
    my $param_name = $labelcol_name;
    $param_name = "qp_" . uc($param_name) if $pivot_mode;

    my $value_when_selected = $cbcol_val;

    #As a convenience, if the value is blank then use the value from the
    #previous column/label but still allow "0"
    if(!defined $value_when_selected || $value_when_selected eq '')
    {
	$value_when_selected = $labelcol_val;
    }
    
#     checkbox(-name=>$param_name, -checked=>1, -value=>$value_when_selected, -label=>$label);
    #Do the checkbox manually to avoid auto-escaping
    my $vws = escapeHTML($value_when_selected);
    my $pn = escapeHTML($param_name);
    "<label><input type='checkbox' name='$pn' value='$vws' checked='checked' />$label</label>";
}

sub get_next_row_html
{
    #Get the next row of results with HTML formatting for the links.
    my $this = shift;
    my $row = $this->{res}->[$this->{nextline}] or return ();
    $this->{nextline}++;

    my @newrow;
    my @flags = @{$this->{column_flags}};
    my $debug_mode = $this->{debug_mode};

    my $link_max_param_length = $this->{link_max_param_length} || 75;
    my $pivot_mode = $this->{checkbox_pivot_mode};

#     die Dumper \@newrow, \@flags;

    #De-crufted this a bit, so <hide and other flags should not interfere with
    #each other.

    for(my $nn = 0; $nn < @$row; $nn++)
    {
	my ($label, $link);
    
	#See what the flag is for this and the next column
	my $currentflag = shift(@flags);
	my $nextflag = $flags[0] || NONE;

	#The <hide flag effects the current col
	next if($currentflag == HIDE && !$debug_mode);

	#Don't care if the nextflag is HIDE
	if(!$nextflag || $nextflag == HIDE)
	{
	    #Default action
	    push @newrow, _escape($row->[$nn]);
	}
	elsif($nextflag == LINKNOTERMS)
	{
	    $label = _escape($row->[$nn]);
	    $nn++; shift @flags; #Skip next col
	    $link = $row->[$nn];

	    #Allow checkbox following link
	    if($flags[0] && $flags[0] == CHECKBOX)
	    {
		$nn++; shift @flags;

		push @newrow, _make_checkbox($this->{names}->[$nn-2], a( {-href=>$link}, $label ), 
					    $row->[$nn-2], $row->[$nn], $flags[0], $pivot_mode);
		push(@newrow, i(_escape($link)), i(_escape($row->[$nn]))) if $debug_mode;
	    }
	    else
	    {
		push @newrow, a( {-href=>$link}, $label );
		push(@newrow, i(_escape($link))) if $debug_mode;
	    }
	}
	elsif($nextflag == LINKWITHTERMS)
	{ 
	    $label = _escape($row->[$nn]);
	    $nn++; shift @flags;
	    $link = $row->[$nn];
	    
	    #Bolt the original search terms into the link.  A little crufty but it seems to work.
	    my $termslink = ($link =~ /\?/ ? ';' : '?') . $this->{termslink};
	    
	    my $linktag = a( {-href=>"${link}${termslink}"}, $label );

	    #Allow checkbox following link
	    if($flags[0] && $flags[0] == CHECKBOX)
	    {
		$nn++; shift @flags;

		push @newrow, _make_checkbox($this->{names}->[$nn-2], $linktag, $row->[$nn-2], $row->[$nn], $flags[0], $pivot_mode);
		push(@newrow, i(_escape($link)), i(_escape($row->[$nn]))) if $debug_mode;
	    }
	    else
	    {
		push @newrow, $linktag;
		push(@newrow, i(_escape($link))) if $debug_mode;
	    }
	}
	elsif($nextflag == PIVOTQUERY)
	{
	    #This is where the columns are collected to generate a new query
	    #with all the values fed in.
	    $label = _escape($row->[$nn]);
	    my @heads = map uc, @{$this->{names}};
	    my %rowhash;
	    #Copy in login parameters if there were any...
	    %rowhash = %{$this->{database_login_parameters}} if $this->{database_login_parameters};

	    #A way to find out which column was clicked in case you want to use this in
	    #the next query.
	    $rowhash{"qp_$heads[$nn]_SEL"} = 1;

	    $nn++; shift @flags;
	    my $query = $row->[$nn];
	    my $flags = $this->{column_flags};
	    for(my $nn = 0; $nn < @heads; $nn++)
	    {
		next if $flags->[$nn] && $flags->[$nn] != HIDE; #Skip special columns but not hidden ones.
		
		#Also avoid putting big long strings into the pivot beacause the URL cannot go over about 2000
		#characters in IE, and dont pass empty values at all
		next unless defined $row->[$nn];
		next if length($row->[$nn]) > $link_max_param_length;
		
		$rowhash{"qp_$heads[$nn]"} = $row->[$nn];
	    }

	    $rowhash{rm} = "results";
	    $rowhash{queryname} = $query;
	    my $pivot = new CGI(\%rowhash);

	    #In some cases (EmbedQuery.pm) I need to be able to set a different target
	    #in {link_base}
	    my $pivot_url = $this->{link_base} ?
			    ( $this->{link_base} . '?' . $pivot->query_string() ) :
			    $pivot->url(-relative=>1,-query=>1) ;
	    $pivot_url .= ($this->{link_postfix} || '');


	    #Note that CGI.pm < 3.43 may mis-generate the link in certain circumstances.
	    #You should upgrade CGI.pm if you have an earlier version.
	    my $linktag = a( {-href=> $pivot_url}, $label );

	    #Allow checkbox following link
	    if($flags[0] && $flags[0] == CHECKBOX)
	    {
		$nn++; shift @flags;

		push @newrow, _make_checkbox($this->{names}->[$nn-2], $linktag, $row->[$nn-2], $row->[$nn], $flags[0], $pivot_mode);
		push(@newrow, i(_escape($query)), i(_escape($row->[$nn]))) if $debug_mode;
	    }
	    else
	    {
		push @newrow, $linktag;
		push(@newrow, i(_escape($query))) if $debug_mode;
	    }
	}
	elsif($nextflag == CHECKBOX)
	{
	    #This is where a checkbox appears next to the value.  If you wrap a form around
	    #the results table in the HTML template the user will be able to select results
	    #and submit the form to whatever URL is given in query_url.
	    $nn++; shift @flags;

	    push @newrow, _make_checkbox($this->{names}->[$nn-1], _escape($row->[$nn-1]), $row->[$nn-1], $row->[$nn], $flags[0], $pivot_mode);

	    push(@newrow, i(_escape($row->[$nn]))) if $debug_mode;
	}
    }
    @newrow;
}

sub generate_linkout
{
    my $this = shift;
    my ($url, $key_column, $pack) = @_;

    #Make a linkout URL.  Firstly, because $pack is from the XML it may be "no".
    #I should really keep all the boolean conversions in the Configuration
    #module but this is a lot easier:
    $pack = ($pack && $pack !~ /no/i);

    #Find out which column corresponds to the $key_column name
    my $col_idx = -1;
    my $nn = 0;
    for(@{$this->{names}})
    {
	$col_idx = $nn, last if($_ eq $key_column);
	$nn++;
    }
    $col_idx > 0 or die "No such column $key_column.\n";

    my $linkout = new CGI({});

    #ParamPacker supports undefs but I can't see that anyone would ever want blanks
    #included in the link.
    my @values = map {defined($_->[$col_idx]) ? $_->[$col_idx] : () } @{$this->{res}};
    if($pack)
    {
	require GenQuery::Util::ParamPacker;
	$linkout->param($key_column => GenQuery::Util::ParamPacker::param_pack(\@values));
    }
    else
    {
	$linkout->param('-name' => $key_column, '-values' => \@values);
    }

    $url . ($url =~ /\?/ ? ';' : '?') . $linkout->query_string() , scalar(@values);
}

sub rewind
{
    my $this = shift;

    $this->{nextline} = 0;
}

sub export
{
    my $this = shift;
    my ($fmt, $extraparams) = @_;
    my ($res, $mimetype, $extn);
	
    #$fmt has not been checked and could be tainted, so tread carefully.  The CSV
    #exporter is built in here but everything else will be a module in ResultExporter

    if(!$fmt || $fmt eq "csv" || $fmt eq "CSV")
    {
	require Text::CSV_XS;
	my $csv = Text::CSV_XS->new( {binary=>1,eol=>"\n"} );

	$res = $csv->combine(@{$this->{column_head}})
		    ? $csv->string() 
		    : die "Cannot convert heading to CSV: " . $csv->error_input();

	my $flags = $this->{column_flags};
	for(@{$this->{res}})
	{
	    #Before combining, scrub anything with a flag not NONE
	    my $nn = 0;
	    my @out = grep {!$flags->[$nn++]} @$_;
	    $res .= $csv->combine(@out) 
		    ? $csv->string() 
		    : die "Cannot convert something to CSV: " . $csv->error_input();
	}
	$extn = 'csv';
	$mimetype = 'text/csv';
    }
    else
    {
	if($fmt =~ /[^0-9a-zA-Z_]/) { die "Invalid export format - contains non alphanumeric chars\n"; }

	#You can now add exp_keeplinks=1 to params, and I've made keeping the XML 
	#declaration the default, so I don't need the XML2 hack any more

	require GenQuery::ResultExporter;
	my $exporter_obj = GenQuery::ResultExporter::get_exporter($fmt);
	$res = $exporter_obj->dump($this, $extraparams);

	$mimetype = $exporter_obj->get('mimetype') || 'text/plain';
	$extn = $exporter_obj->get('extn') || lc($fmt);
    }

    if(wantarray)
    {
	($mimetype, $extn, $res);
    }
    else
    {
	$res;
    }
}

1;
