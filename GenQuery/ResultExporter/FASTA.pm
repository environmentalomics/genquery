#!perl
use strict; use warnings;

# This will export a reult set to FASTA format.  It is assumed that the last column contains the sequence,
# but no checking will be done so you can actually export any old junk in a pseudo-fasta format.

package GenQuery::ResultExporter::FASTA;

# use Data::Dumper;
use GenQuery::ResultTable;

sub new
{
	my ($class) = @_;

	#Should the MIME type be left as text/plain?  Probably.
	my $this = { mimetype => 'application/x-fasta' };
	bless $this => $class;
	$this;
}

sub get
{
	(my $this, $_) = @_;

	/mimetype/ ? $this->{mimetype} : undef;
}

sub dump
{
    my ($this, $rs, $opts) = @_;
    $opts ||= {};
    my $res;
    my $nn;

    my $cols = $opts->{cols} || 70;
    my $sep = $opts->{sep} || ' ';
	
    for (@{$rs->{res}})
    {
		my $nn = 0; my $flags = $rs->{column_flags};
		my @row = grep {!$flags->[$nn++]} @$_; #Copy it and remove any flagged columns
		my $seq = pop(@row) || '';
		$seq =~ s/[\r\f\n]//g;  # Kill linefeeds
		
		my $label = join($sep, grep {defined($_)} @row);
		$label =~ s/[\r\f\n]//g;  # Kill linefeeds

		$res .= ">$label\n";
		$res .= "$1\n" while $seq =~ /(.{1,$cols})/go;
	}

    $res;
}

1;
