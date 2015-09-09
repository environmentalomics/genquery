#
#===============================================================================
#
#         FILE:  Dumper.pm
#
#  DESCRIPTION:  Exports a dataset usign Data::Dumper so i can easily re-read it
#                into another Perl script.
#
#       AUTHOR:  Tim Booth (TB), <tbooth@ceh.ac.uk>
#      COMPANY:  NEBC
our   $VERSION=  1.0;
#      CREATED:  06/09/07 16:45:28 BST
#===============================================================================

use strict;
use warnings;

package GenQuery::ResultExporter::Dumper;

use Data::Dumper;

sub new
{
	my ($class, @params) = @_;

	my $this = { mimetype => 'text/plain', 
				 extn => 'dump',
				 opts => \@params };
	bless $this => $class;
	$this;
}

sub get
{
	#Shortest way.
	$_[0]->{$_[1]};	
}

sub dump
{
	my ($this, $rs, @opts) = @_;
	@opts = @{$this->{opts}} unless @opts;

	#Ignore options and just dump it.

	Dumper($rs);
}

1;
