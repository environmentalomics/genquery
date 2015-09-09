#!/usr/bin/perl
use strict; use warnings;

# Demonstrates how to call a query in GQ from code and deal with the results.

use CGI;		# To formulate the request
use LWP::UserAgent;	# To make the request
use HTTP::Request;
use XML::DOM::XPath;	# To interpret the request

# First, formulate the request you want to send:
my $endpoint = 'http://barsukas.nwl.ac.uk/~tbooth/cgi-bin/genquery/gq.cgi';
my $q = new CGI({
	#Ensure XML output
	rm => 'dl',
	fmt => 'WebRowSet', 
	#Set database and query
	'0:db_name' => 'test_barcode',
	queryname => 'Show Users',
    });

#Add parameters to query
my %params = (
	qp_INST => 'CEH Oxford',
	qp_ONLYBARCODES => undef,
);
while(my @item = each %params){ $q->param(@item) };

print "Sending this:\n" . "$endpoint?" . $q->query_string, "\n";

# Fire off query
my $res = LWP::UserAgent->new->request( HTTP::Request->new(GET=>("$endpoint?" . $q->query_string)) );
$res->is_success() or die("Request failed " . $res->status_line . "\n");
my $doc = eval{ XML::DOM::Parser->new()->parse($res->content) };
$doc or
    die "Failed to parse this:" . $res->content();

# Extract data from XML
my @headings = map {$_->getData} $doc->findnodes('//column-name/text()');
my @data;
for($doc->findnodes('//currentRow'))
{
    push @data, [];
    for($_->findnodes('columnValue'))
    {
	push @{$data[-1]}, ($_->findnodes('null') ? '/NULL/' : $_->getFirstChild()->getData());
    }
}

# Print
no warnings;
$" = ','; $, = $\ = "\n";
print "@headings", map {"@$_"} @data;
