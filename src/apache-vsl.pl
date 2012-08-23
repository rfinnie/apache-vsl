#!/usr/bin/perl

########################################################################
# apache-vsl - VirtualHost-splitting log daemon for Apache
# Copyright (C) 2012 Ryan Finnie <ryan@finnie.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301, USA.
########################################################################

my $VERSION = '3.1.1';
my $EXTRAVERSION = '#EXTRAVERSION#';

use warnings;
use strict;
use Pod::Usage;
use POSIX qw/strftime/;
use Config::General;
use File::Path;
use File::Basename;
use File::Spec;
use Cwd qw/abs_path/;
use Getopt::Long;

my $versionstring = sprintf('%s%s',
  $VERSION,
  ($EXTRAVERSION eq ('#'.'EXTRAVERSION'.'#') ? '' : $EXTRAVERSION)
);

my(
  $opt_cfgfile,
  $opt_loggroup,
  $opt_debug,
  $opt_quiet,
  $opt_help,
);

$opt_cfgfile = "/etc/apache-vsl.conf";

Getopt::Long::Configure("bundling");
my($result) = GetOptions(
  'config|c=s' => \$opt_cfgfile,
  'loggroup|g=s' => \$opt_loggroup,
  'debug|d' => \$opt_debug,
  'quiet|q' => \$opt_quiet,
  'help|?' => \$opt_help,
);

if($opt_help) {
  print STDERR "apache-vsl - VirtualHost-splitting log daemon for Apache, version $versionstring\n";
  print STDERR "Copyright (C) 2012 Ryan Finnie <ryan\@finnie.org>\n";
  print STDERR "\n";
  pod2usage(2);
  #exit(1);
}

my(%cfg);
load_config();

$SIG{USR1} = \&process_SIGUSR1;
$SIG{TERM} = \&process_SIGTERM;

notice("apache-vsl - VirtualHost-splitting log daemon for Apache, version $versionstring -- configured");

# Loop through STDIN.  Duh.
my(%curlogfile, %handle, %lastaccess);
while(my $l = <STDIN>) {
  # Grab the time as soon as possible
  my $now = time;
  my @localtime = localtime($now);

  # Split input into supplied group name and the rest.  No processing is done
  # on the rest.
  my($groupname, $rest);
  if($opt_loggroup) {
    $groupname = $opt_loggroup;
    $rest = $l;
  } else {
    ($groupname, $rest) = split(/ /, $l, 2);
  }
  next unless($groupname && $rest);

  # Parse the group's configuration
  my(%group_config) = get_group_config($groupname);
  my($cfg_logfile, $cfg_prevlink, $cfg_symlink, @cfg_logchange);
  $cfg_logfile = $group_config{'LogFile'};
  next unless $cfg_logfile;
  $cfg_logfile =~ s/\%\{vsl:groupname\}/$groupname/g;
  $cfg_logfile = strftime($cfg_logfile, @localtime);
  $cfg_symlink = $group_config{'SymbolicLink'};
  $cfg_symlink =~ s/\%\{vsl:groupname\}/$groupname/g if $cfg_symlink;
  $cfg_prevlink = $group_config{'PreviousLink'};
  $cfg_prevlink =~ s/\%\{vsl:groupname\}/$groupname/g if $cfg_prevlink;
  @cfg_logchange = @{$group_config{'LogChange'}};

  # Analyze the symlink sitation, and determine if logs have rotated
  # and/or symlinks need to be updated.
  my($change_detected, $old_logfile);
  if($cfg_symlink) {
    ($change_detected, $old_logfile) = analyze_symlink($groupname, $cfg_logfile, $cfg_symlink);
  } else {
    ($change_detected, $old_logfile) = analyze_symlink($groupname, $cfg_logfile, undef);
  }

  if($change_detected) {
    if($old_logfile && (scalar(@cfg_logchange) > 0)) {
      # Rotate has been detected and we know what the old logfile is.
      # Execute the LogChange programs.
      $SIG{CHLD} = 'IGNORE';
      my($pid);
      if(!defined($pid = fork())) {
        # Something bad happened.
      } elsif($pid == 0) {
        # CHILD
        foreach my $lcexec (@cfg_logchange) {
          next unless $lcexec;
          $lcexec =~ s/\%\{vsl:groupname\}/$groupname/g;
          debug(sprintf("[%s] Running: %s %s %s %s", $groupname, $lcexec, $groupname, $old_logfile, $cfg_logfile));
          system($lcexec, $groupname, $old_logfile, $cfg_logfile);
        }
        exit(0);
      } else {
        # MASTER
      }
    }

    # If we need to set a "previous" symlink, now's the time.
    if($cfg_prevlink) {
      if((-e $cfg_prevlink) || (-l $cfg_prevlink)) {
        debug(sprintf("[%s] Removing: %s", $groupname, $cfg_prevlink));
        unless(unlink($cfg_prevlink)) {
          error("Cannot unlink $cfg_prevlink: $!");
        }
      }
      if($old_logfile) {
        mkpath(dirname($cfg_prevlink)) unless(-d dirname($cfg_prevlink));
        unless(rel_symlink($groupname, $old_logfile, $cfg_prevlink)) {
          error("Cannot symlink $old_logfile to $cfg_prevlink: $!");
        }
      }
    }

    if($cfg_symlink) {
      # If the file exists, do a few more tests.  If not, go ahead and symlink.
      if(-e $cfg_symlink || -l $cfg_symlink) {
        # If the file is not a symlink or doesn't point to the correct month,
        # re-create it.
        if(
          !(-l $cfg_symlink) ||
          !(abs_path(rel_readlink($cfg_symlink)) eq abs_path($cfg_logfile))
        ) {
          unless(unlink($cfg_symlink)) {
            error("Cannot unlink $cfg_symlink: $!");
          }
          mkpath(dirname($cfg_symlink)) unless(-d dirname($cfg_symlink));
          unless(rel_symlink($groupname, $cfg_logfile, $cfg_symlink)) {
            error("Cannot symlink $cfg_logfile to $cfg_symlink: $!");
          }
        }
      } else {
        mkpath(dirname($cfg_symlink)) unless(-d dirname($cfg_symlink));
        unless(rel_symlink($groupname, $cfg_logfile, $cfg_symlink)) {
          error("Cannot symlink $cfg_logfile to $cfg_symlink: $!");
        }
      }
    }

  }

  # Open the filehandle (unless the filehandle is already open)
  # and set a few vars to recall later
  $lastaccess{$groupname} = $now;
  $curlogfile{$groupname} = $cfg_logfile;
  unless($handle{$groupname}) {
    mkpath(dirname($cfg_logfile)) unless(-d dirname($cfg_logfile));
    debug(sprintf("[%s] Opening: %s", $groupname, $cfg_logfile));
    if(open($handle{$groupname}, ">> $cfg_logfile")) {
      # Unbuffer the filehandle.
      select((select($handle{$groupname}), $| = 1)[0]);
    } else {
      error("Cannot open $cfg_logfile for writing: $!");
      next;
    }
  }
  
  # Finally!
  my $h = $handle{$groupname};
  print $h $rest;

  # "Stale" filehandle cleanup
  foreach my $v (keys %lastaccess) {
    my(%v_config) = get_group_config($groupname);
    my $timeout = $v_config{'Timeout'};
    $timeout = 300 unless $timeout;
    # If the handle hasn't been used recently, close it, and remove
    # from the database.
    if(($now - $lastaccess{$v}) > $timeout) {
      debug(sprintf("[%s] Closing: %s (%d > %d)", $v, $curlogfile{$v}, ($now - $lastaccess{$v}), $timeout));
      close($handle{$v});
      delete($handle{$v});
      delete($lastaccess{$v});
    }
  }

}

notice("Reached EOF, shutting down");
prep_shutdown();
exit(0);

### BEGIN SUBS ###

sub load_config {
  # (Re-)read config file
  debug("Opening config file $opt_cfgfile");
  my($conf_general);
  eval {
    $conf_general = new Config::General(
      -ConfigFile => $opt_cfgfile,
      -ApacheCompatible => 1
    );
  };
  if($conf_general) {
    %cfg = $conf_general->getall;
  } else {
    error("Cannot open config file $opt_cfgfile: $@");
  }
}

sub get_group_config {
  my($groupname) = shift;
  my(%group_config) = ();

  # Use the group-specific configuration block, otherwise '_default_'
  if($cfg{'LogGroup'} && $cfg{'LogGroup'}->{$groupname}) {
    %group_config = %{$cfg{'LogGroup'}->{$groupname}};
  } elsif($cfg{'LogGroup'} && $cfg{'LogGroup'}->{'_default_'}) {
    %group_config = %{$cfg{'LogGroup'}->{'_default_'}};
  }

  # Config::General is pretty loose about what type options are.  If they
  # appear once, it's a string.  If multiple, an array.
  foreach my $key (keys %group_config) {
    if($key eq 'LogChange') {
      # 'LogChange' must be a array
      unless(ref($group_config{$key}) eq "ARRAY") {
        $group_config{$key} = [$group_config{$key}];
      }
    } elsif($key eq 'Timeout') {
      # 'Timeout' must be a singular number
      if(ref($group_config{$key}) eq "ARRAY") {
        $group_config{$key} = $group_config{$key}[0];
      }
      $group_config{$key} = $group_config{$key} + 0;
    } else {
      # Everything else must be singular
      if(ref($group_config{$key}) eq "ARRAY") {
        $group_config{$key} = $group_config{$key}[0];
      }
    }
  }
  unless($group_config{'LogChange'}) {
    # If no LogChange items were specified, create an empty array
    $group_config{'LogChange'} = [];
  }
  return(%group_config);
}

sub rel_symlink {
  my($groupname) = shift;
  my($target) = shift;
  my($linkdest) = shift;
  my $rel_target = File::Spec->abs2rel($target, dirname($linkdest));
  debug(sprintf("[%s] Symlink: %s -> %s", $groupname, $rel_target, $linkdest));
  return(symlink($rel_target, $linkdest));
}

sub rel_readlink {
  my($link) = shift;
  my $target = readlink($link);
  return() unless $target;
  return(File::Spec->rel2abs($target, dirname($link)));
}

sub analyze_symlink {
  my $groupname = shift;
  my $cfg_logfile = shift;
  my $cfg_symlink = shift;

  if($curlogfile{$groupname}) {
    # NB: Do not use abs_path() here, to save a few syscalls,
    # since we know $curlogfile{$groupname} and $cfg_logfile
    # are in the same (possibly mangled) format.
    if($curlogfile{$groupname} eq $cfg_logfile) {
      # If the computed filenames match (previously opened), return
      # immediately (we don't want to waste a stat on the symlink).
      return(0, undef);
    } else {
      # Computed filenames don't match
      if($handle{$groupname}) {
        # If the handle is open and the computed filenames don't match, delete
        # the handle and indicate we want to rotate.
        close($handle{$groupname});
        delete($handle{$groupname});
        delete($lastaccess{$groupname});
      }
      return(1, $curlogfile{$groupname});
    }
  }

  # At this point, we know that this process has never seen the group
  # before.  Do some symlink checks to see if some logs were written in
  # a previous life, and whether they signify a need to rotate.
  if($cfg_symlink && (-l $cfg_symlink)) {
    # Symlink exists, and is actually a symlink
    my($symlink_dest) = rel_readlink($cfg_symlink);
    if(-e $symlink_dest) {
      # Symlink dest exists
      unless(abs_path($symlink_dest) eq abs_path($cfg_logfile)) {
        # Symlink dest does not match computed logfile.  Rotate.
        return(1, $symlink_dest);
      } else {
        # Symlink dest matches computed logfile.  Woo!
        return(0, undef);
      }
    } else {
      # Symlink file points to a non-existent file.  Recreate.
      return(1, undef);
    }
  } elsif($cfg_symlink && (-e $cfg_symlink)) {
    # Symlink exists, but not as a symlink.  Recreate.
    return(1, undef);
  } elsif($cfg_symlink) {
    # Symlink doesn't exist, but should.  Create
    return(1, undef);
  }

  return(0, undef);
}

sub prep_shutdown {
  foreach my $v (keys %lastaccess) {
    debug(sprintf("[%s] Closing: %s (shutdown)", $v, $curlogfile{$v}));
    close($handle{$v});
    delete($handle{$v});
    delete($lastaccess{$v});
  }
}

sub process_SIGUSR1 {
  notice("Caught SIGUSR1, reloading config");
  load_config();
}

sub process_SIGTERM {
  notice("Caught SIGTERM, shutting down");
  prep_shutdown();
  exit(0);
}

sub messagelog_output {
  my $message = shift;
  my $level = shift;
  print STDERR sprintf("[%s] [%s] VSL: %s\n", strftime("%a %b %d %H:%M:%S %Y", localtime()), $level, $message);
}

sub error {
  my $message = shift;
  messagelog_output($message, 'error');
}

sub debug {
  my $message = shift;
  messagelog_output($message, 'debug') if $opt_debug;
}

sub notice {
  my $message = shift;
  messagelog_output($message, 'notice') unless $opt_quiet;
}

### END SUBS ###

__END__

=head1 NAME

apache-vsl - VirtualHost-splitting log daemon for Apache

=head1 SYNOPSIS

B<apache-vsl> S<[ B<-c> I<apache-vsl.conf> ]> S<[ B<-d> ]> S<[ B<-q> ]> S<[ B<-h> ]>

=head1 DESCRIPTION

B<apache-vsl> is a logging program, intended to be run from Apache.  It 
is designed to be configurable, versatile, efficient and scalable.

apache-vsl is designed to serve multiple Apache VirtualHosts using only 
one logging daemon.  This logging daemon is started and managed by 
Apache itself, requiring little maintenance.  It uses strftime-like 
template strings to specify time-based formats of log filenames, 
automatically takes care of writing to the proper log file, maintains 
current and previous symlinks, and can run multiple trigger programs 
when a log change is performed.

apache-vsl is optimized for Apache installations with high traffic or 
many VirtualHosts.  It keeps file handles loaded in memory between log 
lines, to efficiently handle high traffic VirtualHosts, but will also 
close file handles that have not been logged to in a (configurable) 
amount of time, to efficiently handle a large number of VirtualHosts.

=head1 USAGE

apache-vsl is installed as an Apache-wide CustomLog declaration 
dependant on an environment variable.  For example:

    LogFormat "%v %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" vsl_combined
    CustomLog "|/usr/bin/apache-vsl -c /etc/apache-vsl.conf" vsl_combined env=vsl-enabled

The contents of I</etc/apache-vsl.conf> are described in 
B<CONFIGURATION FILE>, but a suitable default would be:

    <LogGroup _default_>
        LogFile      "/var/log/apache/%{vsl:groupname}/access_log.%Y-%m"
        SymbolicLink "/var/log/apache/%{vsl:groupname}/access_log"
    </LogGroup>

Then, instead of specifying a CustomLog in the Apache <VirtualHost> 
block, you would use "SetEnv vsl-enabled yes".  For example:

    <VirtualHost *:80>
        ServerName www.example.com
        ServerAlias example.com
        DocumentRoot /srv/www/www.example.com/htdocs
        SetEnv vsl-enabled yes
    </VirtualHost>

This matches the CustomLog vsl_combined, which is a pipe to apache-vsl.  
The first argument of the LogFormat is the canonical ServerName value 
(so, in the above example, it would always be "www.example.com" even if 
you visited http://example.com/), while the rest is a standard combined 
CLF format.  This is passed to apache-vsl, which interprets the first 
word as the log group name, and the rest as the actual log.  The log 
group name is matched against the apache-vsl.conf file in <LogGroup> 
blocks, looking for the specific entry, or falling back to "_default_" 
if no match is found.  The log is then written to the file parsed by 
the apache-vsl.conf LogFile format.  In this case, assuming the month 
to be January 2012, the log would be written to:

    /var/log/apache/www.example.com/access_log.2012-01

and a symlink to that file would be created as:

    /var/log/apache/www.example.com/access_log

Other features are vailable, such as PreviousLink (a symlink to the 
previous logfile) and LogChange (programs to run when the logs change).

Whenever the parsing of LogFile changes (i.e. a month change in this 
case), SymbolicLink and PreviousLink are updated, and LogChange 
programs are run.

=head1 OPTIONS

=over

=item B<-c> I<apache-vsl.conf>

=item B<--config>=I<apache-vsl.conf>

Location of configuration file.  See B<CONFIGURATION FILE> for the 
format of the file.  If not specified, the system default is 
I</etc/apache-vsl.conf>.

=item B<-g> I<groupname>

=item B<--loggroup>=I<groupname>

Do not parse the first word of each input line for a log group.  
Instead, use I<groupname> as the log group, and treat input lines as 
verbatim.  Useful for individual VirtualHost ErrorLog pipes.

=item B<-d>

=item B<--debug>

Debug mode.  Events such as opening or closing log files are logged to 
STDERR.  Due to configurable timeouts, the overall debug log traffic is 
fairly low, and is recommended when first deploying an apache-vsl 
installation.

=item B<-q>

=item B<--quiet>

Quiet mode.  Events such as startup notification and signals received, 
normally logged to STDERR, will be surpressed.  Errors will still be 
sent to STDERR during quiet mode.

=item B<-?>

=item B<--help>

Displays a help synopsis and exits.

=back

=head1 CONFIGURATION FILE

The apache-vsl configuration file is in an Apache-style format.  
Variable and block names are case sensitive.  Currently, no 
global-level options are available, and all configuration is done 
inside <LogGroup> blocks.  However, like Apache, B<Include> statements 
may be given to include other files, and may point to individual files, 
or directories or file globs.

The configuration file may be reloaded by either reloading/restarting 
Apache itself, which will stop and then start apache-vsl, or SIGUSR1 
may be sent to the running apache-vsl process to force a configuration 
file reload.

In the event the configuration file cannot be parsed, apache-vsl 
B<will> still start, but will not log.  An error will be logged to 
STDERR, which will be sent to the global Apache ErrorLog.  This 
behavior is to prevent a restart thrash within Apache, as Apache will 
automatically restart any pipe that stops within a logging process.

=head2 <LogGroup>

<LogGroup> blocks require an argument, with the argument being the log 
group name being passed to apache-vsl, or "_default_" to match any 
unnamed groups.  Specifically named group blocks do B<not> inherit from 
_default_, so, for example, if Timeout is set to 60 on _default_ but 
not specified in a specific group's block, it instead assumes the 
built-in default of 300.

=over

=item B<LogFile> "I</path/to/log/file>"

The log file to be written to.  This file will be parsed by strftime, 
and can use any percent-encoded variable available.  Additionally, it 
recognizes I<%{vsl:groupname}>, which is replaced with the group name.

If this option is not specified, no logs will be written.

=item B<SymbolicLink> "I</path/to/symlink>"

The current symlink, which always links to the file valued by 
B<LogFile>. It, like B<PreviousLink>, will replace I<%{vsl:groupname}> 
with the group name, but strftime variables will not be processed.

Whenever a rollover is detected (either by remembering the previous 
logfile in-memory, or comparing B<SymbolicLink> to the currently 
computer B<LogFile>), B<SymbolicLink> and B<PreviousLink> are updated.

If this option is not specified, the ability to detect rollovers will 
be reduced.  apache-vsl will do its best to remember the previous file 
it had written to, but if B<SymbolicLink> is not being created, and 
apache-vsl is not running during a rollover (for example, if log files 
are split along months and apache-vsl is not running between the end of 
the previous month and the beginning of the current month), apache-vsl 
will not be able to recognize if a rollover has occurred.

=item B<PreviousLink> "I</path/to/prevlink>"

A symlink to the previous log, updated whenever a rollover occurs.  It, 
like B<SymbolicLink>, will replace I<%{vsl:groupname}> with the group 
name, but strftime variables will not be processed.

=item B<LogChange> "I</path/to/program>"

When a rollover occurs, B<LogChange> programs, either scripts or full 
compiled programs, will be run.  This value must be the name of an 
actual executable; shell interpretation will not be performed.  
I<%{vsl:groupname}>, if present in the program name, will be replaced 
with the group name.  Several command-line parameters will be passed to 
the program:

    "/path/to/program" "$group_name" "$old_logfile" "$new_logfile"

An example shell script to gzip compress the old logfile would be:

    #!/bin/sh

    [ -n "$1" -a -e "$2" ] || exit 1
    nice gzip -9 "$2"

Multiple B<LogChange> lines may be specified, however, the order in 
which they are executed is not defined.  If you need to perform 
multiple steps in sequence, it is recommended you create a shell script 
that executes them in the desired sequence, and use that as a single 
B<LogChange>.

In fact, very little can be assumed about the execution timing.  
B<LogChange> programs are forked and then not monitored, so it is 
likely multiple B<LogChange> programs, if specified, will be running 
parallel.  The symbolic links may or may not be updated by the time the 
B<LogChange> programs are running.  The new logfile may or may not be 
created by this time as well.

B<LogChange> programs are run the first time a logging event comes in 
after the rollover occurs.  If the group is not logged to often, this 
could be seconds/minutes/hours/days after the rollover.

This option is completely optional.

=item B<Timeout> I<300>

The number of seconds of a log group's inactivity before the log's 
filehandle is closed.  This is desirable on a server with many 
VirtualHosts, not all of which may be visited regularly, so all 
filehandles are not open all the time.

Whenever a log line is processed (on any group), apache-vsl will 
examine its cache of open filehandles and see when the last time a line 
had been written to each filehandle.  If it is longer than the group's 
B<Timeout> value, the filehandle is closed.  If a log file is written 
to often, within the timeout threshold, it will never be closed.

If this option is not specified, a built-in default of 300 seconds is 
used.  Again, remember log group blocks do not cascade, so if _default_ 
has a B<Timeout> set and a specific group does not, the built-in 
default is used, not _default_'s.

=back

=head1 CAVEATS

=head2 CustomLog is in the root level

apache-vsl's premise relies on there being a single pipe to apache-vsl, 
to be more efficient at logging.  The downside is this CustomLog 
declaration is in Apache's root level, and there are no CustomLogs 
defined in the Apache VirtualHost itself.  When this happens, Apache 
will process all root-level CustomLogs.  If apache-vsl is the only 
CustomLog, this is not a problem.  However, many distros will set a 
CustomLog as a fallback for when the user does not set a CustomLog in 
the VirtualHost.  For example, in Debian, this is in 
I</etc/apache2/apache2.conf>:

    # Define an access log for VirtualHosts that don't define their own logfile
    CustomLog /var/log/apache2/other_vhosts_access.log vhost_combined

This will also be triggered, along with apache-vsl.  This is not bad 
per se, but is probably unwanted.  Commenting out or removing this line 
will prevent logs from going to two places.

=head2 Multiple log groups must not point to the same log file

apache-vsl relies on a one-to-one relationship between log groups and 
log files.  The result of two log groups resolving to the same log file 
are undefined and likely destructive.

However, there are many cases when you would want multiple Apache 
VirtualHosts to log to the same file.  There are several ways you can 
accomplish this.  You may elect to log to the main site, and use Apache 
redirects from the other sites to the main site.  For example:

    <VirtualHost *:80>
        ServerName www.example.com
        DocumentRoot /srv/www/www.example.com/htdocs
        SetEnv vsl-enabled yes
    </VirtualHost>

    <VirtualHost *:80>
        ServerName example.com
        Redirect permanent / http://www.example.com/
    </VirtualHost>

Or you may specify an arbitrary descriptor as the log group name, and 
use Apache environment variables to set it:

    LogFormat "%{vsl-group}e %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" vsl_combined
    CustomLog "|/usr/bin/apache-vsl -c /etc/apache-vsl.conf" vsl_combined env=vsl-enabled-custom-group

    <VirtualHost *:80>
        ServerName www.example-1.com
        DocumentRoot /srv/www/www.example-1.com/htdocs
        SetEnv vsl-enabled-custom-group yes
        SetEnv vsl-group custom-example
    </VirtualHost>

    <VirtualHost *:80>
        ServerName www.example-2.com
        DocumentRoot /srv/www/www.example-2.com/htdocs
        SetEnv vsl-enabled-custom-group yes
        SetEnv vsl-group custom-example
    </VirtualHost>

Then in I</etc/apache-vsl.conf>:

    <LogGroup _default_>
        LogFile      "/var/log/apache/%{vsl:groupname}/access_log.%Y-%m"
        SymbolicLink "/var/log/apache/%{vsl:groupname}/access_log"
    </LogGroup>

    <LogGroup custom-example>
        LogFile      "/var/log/apache/www.example.com/access_log.%Y-%m"
        SymbolicLink "/var/log/apache/www.example.com/access_log"
    </LogGroup>

As you can see, while the log group name in apache-vsl is often equal 
to the canonical VirtualHost name, it is in fact completely arbitrary, 
and is just used for mapping to log group blocks.

=head2 Default configuration file can interfere with tab completion

A minor annoyance, but the default configuration file is 
B</etc/apache-vsl.conf>, to be as generic as possible.  This interrupts 
tab completion in some cases with Apache itself.  apache-vsl's author 
uses Debian-based systems frequently, which has Apache configuration 
files in B</etc/apache2/>, so he instead puts the apache-vsl 
configuration file in B</etc/apache2/vsl.conf>, and uses the B<-c> 
parameter to pass this to apache-vsl.

=head1 BUGS

None known, many assumed.

=head1 AUTHOR

B<apache-vsl> was written by Ryan Finnie <ryan@finnie.org>.

=cut
