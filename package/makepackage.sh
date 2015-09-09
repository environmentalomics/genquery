#!/usr/bin/fakeroot /bin/bash

# Constructs the Debian package.  Saves me faffing about with working out which files
# were modified.

#This is a good idea unless restoring your hosed system is your idea of fun.
#Actually, using fakeroot is an even better idea!
set -u
#And this will pick up runtime problems
#set -e

#You must be root because we need to fudge permissions on the files
if [[ `id -u` != "0" ]] ; then
    echo "You are not root.  You need to be root or fakeroot."
    exit
fi

#Subroutine to collect all the files up
collectfiles ()
{
    mkdir -p $CONFIGDIR $SHAREDDIR $WWWDIR $CGIDIR $PERLDIR $DOCDIR $BINDIR

    echo "Clearing out $WWWDIR and $CGIDIR"
    rm -r $WWWDIR/* $CGIDIR/*

    echo "Clearing out $SHAREDDIR and $CONFIGDIR"
    rm -r $SHAREDDIR/* $CONFIGDIR/*

    echo "Clearing out $PERLDIR and $BINDIR and $DOCDIR"
    rm -r $PERLDIR/* $DOCDIR/* $BINDIR/*

    echo "Putting *pm in place"
    install -v -g root -o root ../gq_rerun.perl ../gq_ws.cgi $CGIDIR
    install -v -g root -o root ../gq_default.cgi $CGIDIR/gq.cgi
    install -vd -g root -o root $PERLDIR/GenQuery
    install -vd -g root -o root $PERLDIR/GenQuery/Util
    install -vd -g root -o root $PERLDIR/GenQuery/ResultExporter
    install -v -g root -o root -m644 ../GenQuery/*pm $PERLDIR/GenQuery
    install -v -g root -o root -m644 ../GenQuery/Util/*pm $PERLDIR/GenQuery/Util
    install -v -g root -o root -m644 ../GenQuery/ResultExporter/*pm $PERLDIR/GenQuery/ResultExporter

    echo "Putting gq_edit in place"
    install -v -g root -o root ../gq_edit $BINDIR

    echo "Putting genquery_conf.xml in place"
    install -v -g root -o root -m644 ../genquery_conf_default.xml $CONFIGDIR/genquery_conf.xml

    echo "Putting templates in place"
    install -vd -g root -o root $CONFIGDIR/template
    #I don't want to preserve symlinks here.
    install -v -g root -o root -m644 ../template/*.html ../template/*.tmpl $CONFIGDIR/template

    echo "Putting in stylesheets, icons and .js stuff"
    install -vd -g root -o root $WWWDIR/gfx
    install -v -g root -o root -m644 ../www/gqstyle.css ../www/gqbuttons.css $WWWDIR/
    install -v -g root -o root -m644 ../www/gfx/* $WWWDIR/gfx
    echo cp -r --no-preserve=all ~/public_html/cal $WWWDIR/
    cp -r --no-preserve=all ../www/cal $WWWDIR/

    echo "Grabbing genquery.sql"
#     echo "If you need to update this run ??? - erm, some script on bioinf2"
    install -v -g root -o root -m644 ../SQL/make_tables.sql $SHAREDDIR/

    echo "The crufty CPAN script and the still-cruft shell script"
    install -v -g root -o root -m744 cpaninstall.perl addmodules.sh $SHAREDDIR/
    install -vd -g root -o root  $SHAREDDIR/extra_modules/
    install -v -g root -o root extra_modules/* $SHAREDDIR/extra_modules/

    echo "Putting in LICENSE, README, INSTALL, guide.odt"
    install -v -g root -o root -m644 LICENSE README INSTALL $DOCDIR
    install -v -g root -o root -m644 ~/Documents/genquery/guide.odt $DOCDIR

    echo "Renaming LICENSE to copyright as per Debian spec"
    mv $DOCDIR/LICENSE $DOCDIR/copyright
}

#Run the file collector for the Deb package
CGIDIR=bio-linux-genquery/usr/lib/cgi-bin/genquery/
WWWDIR=bio-linux-genquery/var/www/genquery/
SHAREDDIR=bio-linux-genquery/usr/share/genquery/
DOCDIR=bio-linux-genquery/usr/share/doc/genquery/
PERLDIR=bio-linux-genquery/usr/share/perl5/
CONFIGDIR=bio-linux-genquery/etc/genquery/
BINDIR=bio-linux-genquery/usr/bin/
collectfiles

#And again for the regular tarball
CGIDIR=genquery-src/cgi-bin/
WWWDIR=genquery-src/www/
SHAREDDIR=genquery-src/share/
DOCDIR=genquery-src/doc/
PERLDIR=genquery-src/perl5/
CONFIGDIR=genquery-src/config/
BINDIR=genquery-src/bin/
collectfiles

echo "Removing old .deb and tarball"
rm bio-linux-genquery*.deb
rm genquery.tar.gz bio-linux-genquery.tar.gz

echo "Building .deb"
#TODO - why not just:
dpkg -b bio-linux-genquery .
#vers=`perl -l -ne '/^Version: (.+)/ && print $1' bio-linux-genquery/DEBIAN/control`
#dpkg -b bio-linux-genquery "bio-linux-genquery_${vers}_i386.deb"

echo "Setting ownership on .deb"
chown --reference=$0 bio-linux-genquery*.deb

echo "Packing up tarball to go on Envgen for packaging"
tar --owner root --group root -cvzf bio-linux-genquery.tar.gz bio-linux-genquery
chown --reference=$0 bio-linux-genquery.tar.gz

echo "Packing up tarball to go on Envgen for release"
tar --owner root --group root -cvzf genquery.tar.gz genquery-src
chown --reference=$0 genquery.tar.gz
