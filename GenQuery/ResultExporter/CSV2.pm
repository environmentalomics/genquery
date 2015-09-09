#!perl
use strict; use warnings;

# This will export a result set to CSV but not using CSV_XS because that code suXX0Rs.

package GenQuery::ResultExporter::CSV2;

# use Data::Dumper;
use GenQuery::ResultTable;

sub new
{
	my ($class) = @_;

	#Should the MIME type be left as text/plain?  Probably.
	my $this = { mimetype => 'text/csv', extn => 'csv' };
	bless $this => $class;
	$this;
}

sub get
{
	(my $this, $_) = @_;

	/^_/ ? undef : $this->{$_};
}

sub dump
{
    my ($this, $rs, $opts) = @_;
    $opts ||= {};
    my $res;
    my $nn;

    my $sep = $opts->{sep} || ',';
    my $quot = $opts->{quot} || '"';
    my $doubleup = $opts->{doubleup} || 0;

    my $escaper;
    if($doubleup)
    {
	my $escaper = sub{
	map {
	    s/([$quot])/$1$1/g || /[\s,]/ ? "${quot}${_}${quot}" : $_;
	} @_ };
    }
    else
    {
	$escaper = sub{
	map {
	    s/([\\$quot])/\\$1/g || /[\s,]+/ ? "${quot}${_}${quot}" : $_;
	} @_ };
    }

    $res = join($sep, &$escaper(@{$rs->{column_head}})) . "\n";
	
    for (@{$rs->{res}})
    {
	my $nn = 0; my $flags = $rs->{column_flags};
	my @row = grep {!$flags->[$nn++]} @$_; #Copy it and remove any flagged columns

        $res .= join($sep, &$escaper(@row)) . "\n";
    }

    $res;
}

1;
