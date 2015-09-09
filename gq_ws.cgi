#!/usr/bin/perl
use strict; use warnings;


use SOAP::Lite;

#The GenQuery web services server endpoint

# I have big plans for this, but right now there is nothing...

# SOAP is just too much of a pain, and the default data bindings can't cope with
# anything as fiddly as a row set.  This would be better off as a simplified 
# REST WebQuery that took URLs and returned results in CSV,XML or WebRowSet.
#
# As a bonus I could accept input in XML - eg.
# <query id="12" output_format="XML">
#   <FOO>bar</FOO>
#   <FOO2>array</FOO2>
#   <FOO2>of</FOO2>
#   <FOO2>things</FOO2>
# </query>
# But there is nobody wanting to use this just now, and WebQuery will suffice.
