#!perl
#
# This was going to be something that produced a scatter plot of the data,
# but I now realise that GD::Graph is not up to the job.  Could maybe try
# something commercial - eg: http://www.advsofteng.com/cdperl.html

use strict; use warnings;

package GenQuery::ResultExporter::Graph_Line;

use GD;
use GD::Graph::lines;
use Data::Dumper;

#Output a results table as a scatter plot.  The first column is assumed to contain labels
#while the second and third contain x and y co-ordinates

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

    my @names = @{$rs->get_display_headings()};
    my $flags = $rs->{column_flags};
    $nn = 0;
    my @types = grep {!$flags->[$nn++]} @{$rs->get_types()};

    my $x_label = $names[0];
    my $y_label = undef;

    my $width = $opts->{width} || 800;
    my $height = $opts->{height} || 400;
    (my $dclrs_option = $opts->{dclrs} || 'marine lblue') =~ tr/./#/;
    my @dclrs = split(' ',  $dclrs_option);

    #Decide which columns to output
    $nn = 0;
    my @cols_to_output = ();
    for($nn = 0; $nn < @types; $nn++)
    {
	next unless $nn;

	next if $types[$nn]->{TYPE_NAME} =~ /text|char|date/i;
	push @cols_to_output, $nn;
    }

    @cols_to_output == 2 or die "There need to be 2 numerical columns in the result set";

    #Now assemble the data.  It needs to be in columns, not rows
    my @data = ();
    for($nn = 0; $nn <= @cols_to_output; $nn++){ push(@data, []) };
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
#     my $x_label_skip = int(@{$data[0]} / 10) + 1;

#	die Dumper(\@data);

    my $graph = new GD::Graph::lines( $width, $height );
    $graph->set(
	    x_label =>  $names[$cols_to_output[0]],
	    title => undef,
	    rotate_chart => 0,
	    transparent => 1,
	    show_values => 1,
	    dclrs	    => \@dclrs,
	    x_label_skip => $x_label_skip,
    );

    #Single series
    $graph->set(
	y_label => $names[$cols_to_output[1]],
# 	    cycle_clrs	=> 1,
    );

    $graph->set_x_axis_font(GD::gdSmallFont);
    $graph->set_y_axis_font(GD::gdSmallFont);
    $graph->set_values_font(GD::gdSmallFont);
    $graph->set_x_label_font(GD::gdLargeFont);
    $graph->set_y_label_font(GD::gdLargeFont);

    $im = $graph->plot( \@data );

    $im->png();
}

1;

