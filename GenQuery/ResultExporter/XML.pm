#!perl
use strict; use warnings;

#This module encapsulates methods for writing a result table out to XML.
#"Why do you need yet another module to convert a database resultset
#to XML?", you may well ask.  Simple reason - the others just don't cut
#it.  This version wants to:
#
# 1- Preserve null versus empty string
# 2- Preserve order of rows and columns
# 3- Allow funny column names (ie not valid XML tags)
# 4- Be human readable
# 5- Record both sets of column names
# 6- Capture metadata about the results (types hash)
# 7- Always make valid XML (or die with an error)

# I could have mirrored the phpPgAdmin format but I'm not sure if that is really what I want.
# It's pretty easy to transform between the two with XSLT in any case.

# I also need to consider supporting compression.  Can I rely on Apache to do that
# or do I need to compress the XML stream in Perl?
# Using mod_deflate in Apache seems the most sensible option

#What I'm talking about:
#   <resultset>
#	<field id="1"			//SQL starts at 1 for columns
#	       display_name = "foo"		//compulsory, maybe not unique - what appears on the HTML view
#	       internal_name = "bar"	//compulsory, unique
#		   type = "int8"    //Extract the type from the DB
#	/>
#	<row>
#	    <data>some data</data> //name matches field name above
#	</row>
#	<row>
#		<null /> // foo is null!
#	</row>
#   </resultset>
#
#   As well as 'data' and 'null' there may be a 'link' for special columns.

package GenQuery::ResultExporter::XML;

use XML::Writer;
# use Data::Dumper;
use GenQuery::ResultTable;

sub new
{
    my ($class, @params) = @_;

    my $this = { mimetype => 'text/xml', opts => $params[0] };
    
    bless $this => $class;
}

sub get
{
    (my $this, $_) = @_;

    /mimetype/ ? $this->{mimetype} : undef;
}

sub dump
{
    my ($this, $rs, $opts) = @_;
    $opts ||= $this->{opts};
    my $res;
    my $nn;

    #Note that opts is tainted at this point as it has come straight from the
    #page request.
    #Have an XML declaration by default
    $this->{opts}->{xmldecl} = ($this->{opts}->{xmldecl} || 'yes') ne 'no';

    my $xw = new XML::Writer(OUTPUT => \$res, NEWLINES => 1, DATA_MODE => 1);
    
    #Check columns
    my $names = $rs->get_display_headings();
    my $internalnames = $rs->get_internal_headings();
    my $flags = $rs->{column_flags};
    my $keeplinks = $opts->{keeplinks};

    my $types = $rs->get_types();

    #Knock out flags from internalnames or else add to names
    #depending on option to include the special columns
    if($keeplinks)
    {
	$nn = 0;
	$names = [map {$_ ? ( $_ == GenQuery::ResultTable::HIDE ? '_hide' : '_link' )
			  : shift(@$names)} @$flags];
    }
    else
    {
	$nn = 0;
	$internalnames = [grep {!$flags->[$nn++]} @$internalnames];
	$nn = 0;
	$types = [grep {!$flags->[$nn++]} @$types];
    }

    #Ensure that the internal names are unique - they should be anyway
    make_unique($internalnames);

    #A header?
    $xw->xmlDecl() if($opts->{xmldecl});
    
    #Start XML
    $xw->startTag('resultset');
    
    #Dump fields
    $nn = 0;
    for(@$names)
    {
	my $iname = $internalnames->[$nn];
	my $type = $types->[$nn]->{TYPE_NAME};
	
	$xw->emptyTag('field', id => $nn + 1,
			       display_name => $_,
			       internal_name => $iname,
			       type => $type );

	$nn++;
    }

    #Dump rows
    for my $row (@{$rs->{res}})
    {
	$xw->startTag('row');

	my $colcount = scalar(@$row);
	for($nn = 0 ; $nn < $colcount ; $nn++)
	{
	    if(!$flags->[$nn] || ($keeplinks && $flags->[$nn] == GenQuery::ResultTable::HIDE))
	    {
		    defined $row->[$nn] ?
			    $xw->dataElement(data => $row->[$nn]) :
			    $xw->emptyTag('null') ;
	    }
	    elsif($keeplinks)
	    {
		    $xw->dataElement(link => $row->[$nn]);
	    }
	    #else do nothing
	}

	$xw->endTag('row');
    }

    #Done XML
    $xw->endTag('resultset');
    $xw->end();

    $res;
}

#private sub
sub make_unique
{
    my $array = shift;

    #Hmmm, I'd like to have 'foo', 'bar', 'foo', 'foo' transformed into 'foo', 'bar', 'foo.1', 'foo.2'
    #I guess that something silly like 'foo', 'bar', 'foo', 'foo.1' becomes 'foo', 'bar', 'foo.1', 'foo.1.1'
    
    my %sub;

    for(@$array)
    {
	while(my $px = $sub{$_}++)
	{
	    $_ .= ".$px";
	}
    }
}

1;
