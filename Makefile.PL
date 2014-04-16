use strict;
BEGIN {
        require 5.006;
}

use ExtUtils::MakeMaker;

WriteMakefile(
  META_MERGE => {
    resources => {
      repository => 'https://github.com/rfinnie/apache-vsl',
    },
  },
  NAME => 'apache-vsl',
  # Cannot use ABSTRACT_FROM here because MakeMaker is interpreting
  # "apache-vsl" as "apache::vsl", and cannot figure out the abstract.
  ABSTRACT => 'VirtualHost-splitting log daemon for Apache',
  VERSION_FROM => 'script/apache-vsl.in',
  AUTHOR => 'Ryan Finnie <ryan@finnie.org>',
  LICENSE => 'gpl',
  MIN_PERL_VERSION => 5.006,
  PREREQ_PM => {
    'Getopt::Long' => 0,
    'Pod::Usage' => 0,
    'IO::Select' => 0,
    'IO::Socket::INET' => 0,
    'Time::HiRes' => 0,
  },
  EXE_FILES => [
    'script/apache-vsl'
  ],
  PL_FILES => {
    'script/build.PL' => 'script/apache-vsl'
  },
  MAN1PODS => {
    'script/apache-vsl'  => 'blib/man1/apache-vsl.1p',
  },
  clean => {
    FILES => 'script/apache-vsl',
  },
);
