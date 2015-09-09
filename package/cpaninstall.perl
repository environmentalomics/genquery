#!/usr/bin/perl

# The instruction "install the required Perl modules on your system"
# is too much for some users.  The correct solution is to make .deb
# packages of all the requirements, but that is:
# a) Debian specific
# b) Hard work
# So instead here is a script which runs CPAN and forces it to
# non-interactively install the modules I need.  What is that you say?
# "That's a nasty hack and breaks all the Debian rules and you can't
# uninstall the things properly!".  Oh well, such is life...

# Note that if any version of the packages is found, this script will
# skip that package without checking the version.

use strict;
use CPAN;

my @modules_to_install = (
	"String::Tokenizer",
	"CGI::Application::Plugin::Forward",
);

$CPAN::Config = {
  'cpan_home' => '/root/.cpan_auto',
  'makepl_arg' => 'INSTALLDIRS=site',
  'histfile' => '/root/.cpan_auto/histfile',
  'unzip' => '/usr/bin/unzip',
  'show_upload_date' => '0',
  'dontload_hash' => {},
  'cpan_version_check' => '0',
  'mbuild_install_build_command' => 'sudo ./Build',
  'lynx' => '/usr/bin/lynx',
  'curl' => '/usr/bin/curl',
  'ncftp' => '',
  'urllist' => [
  		 'http://search.cpan.org/CPAN/',
		 'ftp://ftp.mirror.ac.uk/sites/ftp.funet.fi/pub/languages/perl/CPAN/',
		 'ftp://ftp.flirble.org/pub/CPAN/'
	       ],
  'gzip' => '/bin/gzip',
  'ncftpget' => '',
  'keep_source_where' => '/root/.cpan_auto/sources',
  'prefer_installer' => 'EUMM',
  'getcwd' => 'cwd',
  'make_install_make_command' => '/usr/bin/make',
  'no_proxy' => '',
  'build_cache' => '10',
  'make_arg' => '',
  'wget' => '/usr/bin/wget',
  'ftp_proxy' => '',
  'tar' => '/bin/tar',
  'inactivity_timeout' => '0',
  'scan_cache' => 'atstart',
  'mbuildpl_arg' => '',
  'cache_metadata' => '0',
  'ftp' => '/usr/bin/ftp',
  'shell' => '/bin/bash',
  'prerequisites_policy' => 'ignore',
  'make' => '/usr/bin/make',
  'gpg' => '/usr/bin/gpg',
  'mbuild_arg' => '',
  'inhibit_startup_message' => '0',
  'build_dir' => '/root/.cpan_auto/build',
  'index_expire' => '1',
  'mbuild_install_arg' => '',
  'bzip2' => '/usr/bin/bzip2',
  'pager' => '/bin/cat',
  'term_is_latin' => '0',
  'make_install_arg' => '',
  'http_proxy' => '',
  'histsize' => '0',
  mbuild_arg => '', 
  mbuild_install_arg => '', 
  mbuild_install_build_command => '', 
  mbuildpl_arg => ''
};
$CPAN::Config_loaded++;
$INC{"CPAN/Config.pm"} = "Hacked!";
$INC{"CPAN/MyConfig.pm"} = "Hacked!";

our $reload_index;

for my $mod (@modules_to_install)
{
    next if eval"require $mod";

    CPAN::Shell->reload('index') unless $reload_index++;

    #Notest only works on later CPAN :-(
    if(CPAN->VERSION() >= 1.8)
    {
		CPAN::Shell->notest(install => $mod);
    }
    else
    {
		CPAN::Shell->install($mod);
    }
}

