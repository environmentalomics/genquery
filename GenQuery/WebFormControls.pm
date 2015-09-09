#!perl
use strict;
=head1 NAME

GenQuery::WebFormControls

=head1 AUTHOR

Tim Booth <tbooth@ceh.ac.uk>

=head1 CREATED

25/04/07 11:43:47 BST

=head1 SYNOPSIS

	use GenQuery::WebFormControls;
	my $q = new CGI;
	my $control_maker = new GenQuery::WebFormControls($q);

	my $acontrol = $control_maker->param_to_control($query_object, $param_id);

	if($control_maker->date_picker_used())
	{
		#...set up the date picker
	}

=head1 SUMMARY

This module contains the logic for making form controls based on the settings read
from the query_param table.  To modify or add to the supported param types only this code needs to
be modified.

I have moved the code to generate web form controls into this
module, as these definitions are likely to be subject to change,
and it is also a lot of cruft to be sitting in the already crufty
WebQuery.pm module.

=head1 METHODS

=over 4

=item * B<new()>

The constructor must be passed a CGI object which will be used to generate the form control code.

=item * B<param_to_control($qobj, $id)>

	$qobj is a GenQuery::QueryInstance
	$id is the parameter number

Returns some HTML form elements to show this parameter.

=item * B<date_picker_used()>

If a date field has been included the module will include code to integrate the date picker with the input box.
The caller can check this flag to see if the date picker was ever used within the life of the WebFormControls
object and therefore if it needs to bother integrating the JS code into the page.

=cut

package GenQuery::WebFormControls;
(our $VERSION = '2.$Revision: 1.1 $') =~ y/[0-9.]//cd;

#This needs to match the declaration in GenQuery::WebQuery
our $ALL = $GenQuery::WebQuery::ALL || "ALL\240"; #ie. "ALL&nbsp;" avoids unlikely collision with a literal "ALL"
#How many items to allow in a radio group before switching to a dropdown
our $DEFAULT_MENU_CUTOFF = 4;

use warnings;

sub new
{
    my $class = shift;
    my $this = bless({q => shift} => $class);

    #I just need a tame query object to operate
    ref($this->{q}) eq 'CGI' or die 
	    "WebFormControls object must be instantiated with a CGI query object.";

    $this->{menu_cutoff} = $DEFAULT_MENU_CUTOFF; #ie how many items in a menu before using a combobox?

    ($this->{add_defaults}) = @_; #Flag to set default text in TEXT controls.  
				  #I don't want them going in if the query is being run.

    $this;
}

#This is a little private helper function
#Extracts odd elements from a list
sub odd
{
    my $x;
    grep {$x=!$x} @_;
}

sub param_to_control
{
	my $this = shift;
    my $q = $this->{q};
    #This is only used within add_query_to_tmpl but is moved out here to
    #avoid massive indenting and to aid testing.
    #It turns a query parameter into a control on an HTML form

    #To avoid name clashes with internal CGI fields all query params
    #get the 'qp_' prefix bolted on the front.
    my ($qobj, $id) = @_;

    my $info = $qobj->get_param_info($id);
    my @allvalues = $qobj->get_param_values($id);

    my $qp_name = "qp_$info->{param_name}";
	my @option_all = $info->{suppress_all} ? () : ($ALL);

    my $new_element;
    for($info->{param_type})
    {
    my $pt = uc($_); #pt = param_type

    if($pt =~ /MENU/)
    {
        #auto-choose between radio or dropdown (over 4 means dropdown)
        $pt =~ s/MENU/(scalar(@allvalues) > $this->{menu_cutoff} ? 'DROPDOWN' : 'RADIO')/e;
    }

    if($pt =~ /DROPDOWN/)
    {
        #If any of these starts with L then it is the explicitly 'Labelled' version
        if($pt =~ /^L/)
        {
        $new_element = $q->popup_menu( -name => $qp_name,
                           -values => [@option_all, odd(@allvalues)],
                           -labels => { @allvalues } );
        }else{
        $new_element = $q->popup_menu( -name => $qp_name,
                           -values => [@option_all, @allvalues] );
        }
    }
    elsif($pt =~ /RADIO/)
    {
        if($pt =~ /^L/)
        {
        $new_element = $q->radio_group( -name => $qp_name,
                        -values => [@option_all, odd(@allvalues)],
                        -labels => { @allvalues },
                        -columns => 3 );
        }else{
        $new_element = $q->radio_group( -name => $qp_name,
                        -values => [@option_all, @allvalues],
                        -columns => 3 );
        }
    }
    elsif($pt =~ /MULTI/)
    {
        if($pt =~ /^L/)
        {
        $new_element = $q->checkbox_group( -name => $qp_name,
                           -values => [odd(@allvalues)],
                           -labels => { @allvalues },
                         #  -defaults => \@allvalues,
                           -columns => 3 );
        }else{
        #TODO - consider JavaScript widget to turn all off or on.
        $new_element = $q->checkbox_group( -name => $qp_name,
                           -values => \@allvalues,
                         #  -defaults => \@allvalues,
                           -columns => 3 );
        }
    }
    elsif($pt =~ /YESNO/)
    {
        #This was the original, but older CGI.pm does not like it:
#       $new_element = $q->radio_group( -name => $qp_name,
#                       -values => [ 'yes', '' ],
#                       -labels => { yes => 'yes', '' => 'no'},
#                       -default => '' );

        #This order is more sensible anyway.
            $new_element = $q->radio_group( -name => $qp_name,
                                            -values => [ '', 'yes' ],
                                            -labels => { ''=>'no', yes=>'yes' } );

    }
    elsif($pt =~ /DATE/)
    {
        #Have added a date type as suggested by NH.
        #To make the picker work the JS code must be loaded with appropriate directives
        #at the top of the HTML, and it is up to the user to put these in the template.
        #I provide a hint that the calendar should be loaded, so you don't have to serve it
		#with every single page:
        $this->{date_picker_used}++;

        #I need some unique number for each button so just use a global counter.  Under mod_perl
	#this will just keep going up.
        our $calid; $calid++;

	#By default the calendar will show today's date, but maybe I want something else
	#Note - to work this needed the fix to calendar-setup.js given here:
	# http://www.dynarch.com/forums/2112
	my $defdate = "";
	if($allvalues[0])
	{
	    $defdate = qq#  date : Date.parseDate("$allvalues[0]", "\%Y-\%m-\%d"),#;
	}

        my $calscript = qq#
	  $defdate
	  Calendar.setup({
	    inputField     :    "calendar_$calid",
	    ifFormat       :    "\%Y-\%m-\%d",
	    $defdate
	    button         :    "calendar_popup_$calid"
	  });#;

        $new_element = $q->span(
	    $q->textfield({ -name => $qp_name,
			    -id => "calendar_$calid"}) .
	    $q->Button({-type => "button",
			-class => "date_picker_icon",
			-onClick => "alert('Calendar feature has not been loaded!')",
			-id => "calendar_popup_$calid" },
			"..." ) .
	    $q->script({-type => "text/javascript"},
		   $calscript)
	   );
    }
    else #You get a textbox then! =~/TEXT/
    {
	my $defval = $this->{add_defaults} ? $allvalues[0] : undef;

        if($pt =~ /BIG/)
        {
          $new_element = $q->textarea({ -name => $qp_name,
					-default => $defval,
					-class => "bigtext",
                                        -rows=>6,
					-columns=>50 });
        }
        elsif($pt =~ /HUGE/)
        {
          $new_element = $q->textarea({ -name => $qp_name,
                        -style => "width:90%",
                        -class => "hugetext",
						-default => $defval,
                        -rows=>10,
                        -columns=>300 });
        }
        else
        {
          $new_element = $q->textfield({ -name => $qp_name,
					 -default => $defval,
					 -width => 30 });  #TODO, fix that hard-coding
        }
    }

    }

    $new_element;
}

sub date_picker_used
{
	$_[0]->{date_picker_used};
}

1;
