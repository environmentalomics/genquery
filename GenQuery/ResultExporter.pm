#
#===============================================================================
#
#         FILE:  ResultExporter.pm
#
#  DESCRIPTION:  Wrapper for result exporter plugin classes
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Tim Booth (TB), <tbooth@ceh.ac.uk>
#      COMPANY:  NEBC
#      VERSION:  1.0
#      CREATED:  06/02/08 15:34:31 GMT
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;

package GenQuery::ResultExporter;
our $ResultExporter = "GenQuery::ResultExporter";

sub get_info_for_exporter
{
	#Returns the type, canonical name and long description of an exporter module.
	#Types can be "results", "graph", "text", "binary"
	#To save loading all the exporter classes, just code info in here.
	my $exporter = shift;
	$exporter eq __PACKAGE__ and $exporter = shift;

	for($exporter)
	{
		tr/-/_/;
		/graph_pie/i and return ( graph => 'Graph_Pie', "pie chart" );
		/graph_bar/i and return ( graph => 'Graph_Bar', "bar chart" );
		/graph_line/i and return ( graph => 'Graph_Line', "line graph" );
		#Sadly GD::Graph does not support scatter plots :-(
# 		/graph_scatter/i and return ( graph => 'Graph_Scatter', "scatter plot" );
		/graph_(.+)/i and return ( graph => $_, $1 );

		/html/i and return ( results => 'html', "result table" );

		/dumper/i and return ( text => 'Dumper', "perl Dumper format" );
		/fasta/i and return ( text => 'FASTA', "multi-FASTA sequence file");
		/csv/i and return ( text => 'CSV', "comma separated values");

		return ( binary => $_, "$_ formatted data" );
	}
}

sub get_exporter
{
	my ($fmt, @extraparams) = @_;

	#lalalala
	my $exporter_obj;
	eval "
	     require ${ResultExporter}::$fmt;
	     \$exporter_obj = ${ResultExporter}::$fmt->new(\@extraparams);
	    " || die "Cannot load module ${ResultExporter}::$fmt.\n$@\n";

	$exporter_obj;
}

1;
