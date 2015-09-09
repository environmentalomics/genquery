#!perl

=head1 NAME

GenQuery::Util::ParamPacker

=head1 AUTHOR

Tim Booth <tbooth@ceh.ac.uk>

=head1 CREATED

25/04/07

=head1 SYNOPSIS

	use GenQuery::Util::ParamPacker;

	my $packed = param_pack(\@values);
	my $unpacked = param_unpack($packed);

=head1 SUMMARY

The idea behind this module is that I want to be able to pass big lists of result values out from GenQuery
via an URL link for the linkout feature.  For <pivotquery and <linkwithterms I could be pretty sure that the
URL would not grow beyond the 2000-ish character limit imposed by IE.  For the linkout I could potentially have 2000 rows
to contend with (in fact more, since I could linkout all results) which leaves me decidedly pushed for space.  This module 
will compress an array of strings into a single packed, base64-encoded format to be pasted into the URL.

This is in particular optimised for lists of numbers, and especially where many numbers are sequential, but arbitrary strings
are supported and undefs will be preserved.  It has also been checked for corner cases like the empty list and empty string.

As the compression schema is complex, clients (eg Handlebar) will want to use this module to do their own decompression of
the packed data, so it should stand alone as far as possible.

=head1 METHOD

params will be escaped, giving me : and , to play with
any sequential numbers will be grouped with a : separator (see code for making accession lists)
everything will be joined by commas
resulting string will be gzipped
and gzipped again, because for some reason this is very effective on lists of numbers - I know it
shouldn't work, but it does.
resulting buffer will be base64 encoded
tr|/+=|_.-| because these chars don't expand in the URL

=head1 METHODS

=over 4

=item * B<param_pack(\@values)>

Packs array to return a string

=item * B<param_unpack($packed)>

Unpacks string to return arrayref.  Will die with an error if the input does not unpack as expected.

=back

=cut

use strict;
use warnings;
package GenQuery::Util::ParamPacker;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(param_pack param_unpack);

use MIME::Base64;
use Compress::Zlib qw(compress uncompress);

sub param_pack
{
	#Deliberate copying of values prior to manipulation.
	my @values = map { ref($_) eq 'ARRAY' ? @$_ : $_ } @_;
	my $count = scalar(@values);
	return '.' if $count == 0;

	#Escape all (: , &) to (&1 &2 &3)
	for(@values)
	{
		#Can't deal with undef - escpae that too
		if(defined($_))
		{
			s/([:,&])/$1 eq ':' ? '&1' : $1 eq ',' ? '&2' : '&3'/eg;
		}
		else
		{
			$_ = '&4';
		}
	}

	#Join with commas, unless there are sequential numbers in the list
	my $buf = shift(@values);
	my $lastval = $buf;
	my $inrange = 0;

	while(scalar(@values))
	{
		my $nextval = shift(@values);

		if(check_sequential($lastval, $nextval))
		{
			$inrange = 1; #We are within a range
		}
		else
		{
			#If I was in a range I need to add the lastval
			if($inrange)
			{
				$buf .= ":$lastval";
				$inrange = 0;
			}

			$buf .= ",$nextval";
		}
		$lastval = $nextval;
	}
	#Don't forget to close the range
	$buf .= ":$lastval" if $inrange;

	#Double-gzip the buffer (see ~/perl/zlibtest.perl for proof I'm not mad)
	$buf = compress($buf, 9);
	$buf = compress($buf, 9);

	#Encode it
	$buf = encode_base64($buf, '');

	#Transcode it
	$buf =~ tr|/+=|_.-|;

	#Done!
	$buf;
}

sub param_unpack
{
	my ($buf) = @_;
	
 	die "param_unpack() called with nothing to unpack.\n" unless $buf;
	return [] if ($buf eq '.');

	#No real verification is done on $packed.  Corruption will show up in the decoding or the decompression
	#but if the input has been tinkered with you could produce some crazy results or an infinite loop
	#or something nasty.  (Hmmm - actually, probably not)
	
	#Undo the transliteration
	$buf =~  tr|_.-|/+=|;

	#decode it
	$buf = decode_base64($buf);

	#double unzip it
	$buf = uncompress(uncompress($buf));

	#At this point bale out if $buf is undef
	die "Not a valid packed string.\n" unless (defined($buf));

	#special case for empty string, which otherwise vanishes in the split
	#true empty arrays are represented by a compressed string consisting of a
	#single period, nulls are escaped as '&4'.
	return [''] if ($buf eq '');

	#split on commas preserving trailing fields
	my @result = split(',', $buf, -1);

	#expand all colon-delineated ranges
	@result = map { /:/ ? expand_sequence($_) : $_ } @result;
		
	#Restore all escaped characters and undefs
	for(@result)
	{
		if($_ eq '&4')
		{
			$_ = undef;
		}
		else
		{
			s/&([123])/$1 eq '1' ? ':' : $1 eq '2' ? ',' : '&'/eg;
		}
	}

	#Done
	\@result;
}

sub check_sequential
{
	my($foo, $bar) = @_;

	#Returns true if
	# $foo is an integer > 0
	# $bar is an integer
	# $bar = $foo + 1;
	# Neither number begins with a leading +, 0 etc.
	
	return 0 unless $foo =~ /^[1-9]/ && $bar =~ /^[1-9]/;
	return 0 if $foo =~ /\D/ || $bar =~ /\D/;

# 	return 0 unless $foo > 0;
	return ($bar == $foo + 1);
}

sub expand_sequence
{
	#Not robust - I assume the string was properly formatted!
	my ($from, $to) = split(':', $_[0]);

	$from..$to;
}

1;
