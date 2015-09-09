#!perl
#
# Exporter that creates a bar graph rendering of the data

use strict; use warnings;

package GenQuery::ResultExporter::Graph_Pie;

use GD;
use GD::Graph::pie;
use Data::Dumper;

#Output a results table as a bar chart.  The first column will be used as the X axis
#labels and other numeric columns will be used as bar heights.

sub new
{
    my $class = shift;

    my $this = { mimetype => 'image/png', extn => 'png', opts => shift };

    bless $this => $class;
}

sub get
{
    (my $this, $_) = @_;
    
    /mimetype/ and return $this->{mimetype};
    /extn/ and return $this->{extn};
    
    undef;
}

sub dump
{
    my ($this, $rs, $opts) = @_;
    $opts ||= $this->{opts};
    my $im;
    my $nn;

    #binmode STDOUT; #Wants to be set in WebQuery to avoid munging of binary as unicode
    my @names = @{$rs->get_display_headings()};
    my $flags = $rs->{column_flags};
    $nn = 0;
    my @types = grep {!$flags->[$nn++]} @{$rs->get_types()};

    my $x_label = $names[0];
    my $y_label = undef;

    my $width = $opts->{width} || 800;
    my $height = $opts->{height} || 400;
    (my $dclrs_option = $opts->{pieclrs} || '') =~ tr/./#/;
    my @dclrs = split(' ',  $dclrs_option);
    my $flag3d = $opts->{'3d'} ? 1 : 0;

    #Now I want to force a non-3d chart to come out round, not oval.
    my @margins = ();
    if(!$flag3d)
    {
	if($width > $height)
	{
	    @margins = (l_margin => int(($width - $height) / 2) , r_margin => int(($width - $height) / 2));
	}
	elsif($height > $width)
	{
	    @margins = (t_margin => int(($height - $width) / 2) , b_margin => int(($height - $width) / 2));
	}
    }

    #Decide which columns to output
    $nn = 0;
    my @cols_to_output = ();
    for($nn = 0; $nn < @types; $nn++)
    {
	next unless $nn;

	next if $types[$nn]->{TYPE_NAME} =~ /text|char|date/i;
	push @cols_to_output, $nn;
    }

    @cols_to_output or die "No numeric columns in this result set";

    #Up to now I've copied the bar chart, but for pies there can be only
    #one data column.
    @cols_to_output = ($cols_to_output[0]);
    my @data = ([], []);
    for my $row (@{$rs->{res}})
    {
	$nn = 0;
	for(0, @cols_to_output)
	{
	    push @{$data[$nn]}, $row->[$_];
	    $nn++;
	}
    }

    #Now limit to ten labels along the x axis by skipping
    my $x_label_skip = int(@{$data[0]} / 10) + 1;

#	die Dumper(\@data);

    my $graph = new GD::Graph::pie( $width, $height );
     $graph->set(
#     die Dumper(
	    x_label      => $x_label,
	    title        => undef,
	    rotate_chart => 0,
	    transparent  => 1,
	    show_values  => 1,
	    start_angle => 180,
 	    (@dclrs ? (dclrs => \@dclrs) : ()),
	    x_label_skip => $x_label_skip,
	    '3d'	 => $flag3d,
 	    @margins,
    );

=cruft
    if(@cols_to_output == 1)
    {	
	#Single series
	$graph->set(
	    y_label => $names[$cols_to_output[0]],
	    cycle_clrs	=> 1,
	);
    }
    else
    {
	#Multiple series
	$graph->set(	
	    bargroup_spacing => 4,
	    cycle_clrs => 0,
	    legend_placement => 'RT',
	);
	$graph->set_legend(@names[@cols_to_output]);
	$graph->set_legend_font(GD::gdLargeFont);
    }
=cut

#     $graph->set_values_font(GD::gdSmallFont);
     $graph->set_label_font(GD::gdLargeFont);
     $graph->set_value_font(GD::gdLargeFont);

     #Special case for no data or all zero
     if(@{$data[0]} == 0) { @data = ( ['No data', 1] ) };
     my $sum = 0; map {$sum += $_} @{$data[1]};
     if(!$sum) {map { $_++ } @{$data[1]} };

    $im = $graph->plot( \@data );

    return $im->png(); # unless $gresize;
=cruft

#This can be done just by setting margins - much simpler plus you don't get labels chopped off at the edges.

    #If $gresize was set I want to centre the graph on a larger canvas
    my $im2 = 2.0 <= $GD::VERSION
        ?   GD::Image->newPalette($width, $height)
        :   GD::Image->new($width, $height);

    my $white = $im2->colorAllocate(255,255,255);
    $im2->transparent($white);
    $im2->filledRectangle(0,0,$width,$height,$white);

    my $dstX = ($width - $gwidth) / 2;
    my $dstY = ($height - $gheight) / 2;

    $im2->copy($im,int($dstX),int($dstY),0,0,$gwidth,$gheight);
    $im2->png();
=cut
}

1;

