#!perl
use strict; use warnings;

# This will arrange a three-column table into a matrix, tab separated.  All tabs in data will be converted to
# three spaces but otherwise no quoting will be done.
# The table must have exactly three columns.
# The first will be row headings, the second will be column headings, the third will be values.
# Everything will be kept in the order it appears in the results, so to get this:
#
# Latitude\\Month   Jan	Feb Mar
# 60		    4	5   7
# 70                12	13  15
# 80		    16	17  20
#
# Select this:
#
# Latititude	Month	whatever
# 60		Jan	4
# 60		Feb	5
# 60		Mar	7
# 70		Jan	12
# 70		Feb	13
# 70		Mar	15
# 80		Jan	16
# 80		Feb	17
# 80		Mar	20
#
# Note that any ordering of rows will produce a matrix but the ordering may not be
# so obvious, so the above is the suggested format.
#
# If you want empty cells in the matrix changed to zeros, you need to add this to genquery_conf.xml,
# at the top level:
#   <export_options>exp_matrixpadempty=0</export_options>

package GenQuery::ResultExporter::Matrix;

# use Data::Dumper;
use GenQuery::ResultTable;

sub new
{
	my ($class) = @_;

	#Should the MIME type be set as application/text-tsv?  Probably.
	my $this = { mimetype => 'text/plain' };
	bless $this => $class;
	$this;
}

sub get
{
	(my $this, $_) = @_;

	/mimetype/ ? $this->{mimetype} : undef;
}

#Strip tabs
sub stripts
{
    if(@_)
    {
	if(wantarray)
	{
	    return map { my $foo = $_ ; $foo =~ s/\t/   /g ; $foo } @_;
	}
	else
	{
	    my $foo = "@_";
	    $foo =~ s/\t/   /g;
	    return $foo;
	}
    }
    else
    {
	s/\t/   /g;
    }
}

sub dump
{
    my ($this, $rs, $opts) = @_;
    $opts ||= {};
    my $res;

    #In-memory processing is much more robust, and allows holes in the matrix
    #Until I get streaming working in general the streaming version is useless.
    my $in_memory = $opts->{inmemory} || 1;
    my $empty_string = $opts->{matrixpadempty}; #Only works in-memory

    my $flags = $rs->{column_flags};
    my $nn = 0;
    my @column_head = grep {!$flags->[$nn++]} @{$rs->{column_head}};
    if( scalar(@column_head) != 3 )
    {
	return "You must have exactly three visible columns to make a matrix\n";
    }

    my $legend = stripts( $column_head[0] . "\\\\" . $column_head[1] );

    if($in_memory)
    {
	#Capture everything
	my(@row_headings, %row_headings);
	my(@col_headings, %col_headings);
	my %data;
	
	for(@{$rs->{res}})
	{
	    my ($rowhead, $colhead, $val) = @$_;

	    $row_headings{$rowhead}++ || push @row_headings, $rowhead;
	    $col_headings{$colhead}++ || push @col_headings, $colhead;
	    $data{$rowhead}{$colhead} = $val;
        }

	#Spew it
	$res = "$legend\t" . join("\t", stripts(@col_headings)) . "\n";

	for my $rh (@row_headings)
	{
	    $res .= stripts($rh) . "\t" . 
		    join("\t", map { stripts( !exists($data{$rh}{$_})  ? $empty_string :
			                      !defined($data{$rh}{$_}) ? '' :
					      $data{$rh}{$_}
			                    ) } @col_headings) . "\n";
	}
    }
    else
    {
	#This is untested and probably best not used for now.
	#Relies on data for all cells and total ordering.
	
	#Empty case
	if(!scalar(@{$rs->{res}})){ return "$legend\n" }

	my $firstrow = 1;
	my $currentrowhead = $rs->{res}->[0]->[0];

	my $headerline = "$legend";
	my $firstline = stripts($currentrowhead);

	for(@{$rs->{res}})
	{
	    #Case where we just hit the second row heading and thus have all
	    #the column headings so can dump botht the header and the first row.
	    if($firstrow && $_->[0] ne $currentrowhead)
	    {
		$res = "$headerline\n$firstline";
		$firstrow = 0;
	    }

	    if($firstrow)
	    {
		$headerline .= "\t" . stripts($_->[1]);
		$firstline .= "\t" . stripts($_->[2]);
	    }
	    else
	    {
		if($_->[0] ne $currentrowhead)
		{
		    $currentrowhead = $_->[0];
		    $res .= "\n" . stripts($currentrowhead);
		}
		$res .= "\t" . stripts($_->[2]);
	    }
	}
	$res .= "\n";
    }

    $res;
}

1;
