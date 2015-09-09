#!/bin/sh

# Add two modules which we need but are not available via APT.
# If any version of the module is available, use it.
# Otherwise dump in the module file.
# This is a bit nasty, but the previous CPAN hack was even worse,
# and I stall can't be bothered to package this stuff properly.

modules_to_install='/usr/share/genquery/extra_modules/*'
target_dir='/usr/share/perl5'
alias perl_version="perl -le '"'print eval("require $_;$_->VERSION") || exit(1) for shift'"'"


for mod in $modules_to_install ; do

    #Needed for empty list
    test -e $mod || echo "Nothing to do"
    test -e $mod || break

    modname=`basename $mod .pm`
    filename=${modname##*::}.pm
    dest_dir="$target_dir"/`echo ${modname%::*} | tr -s : /`

    current_version=`perl_version $modname`
    if [ -z "$current_version" ] ; then
	install -vDT $mod $dest_dir/$filename
    else
	echo "Version $current_version of $modname already available."
    fi
done

