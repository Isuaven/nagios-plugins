#!/usr/bin/perl -w
#
#  Nagios plugin
#
#  DESCRIPTION: This Perl script tries to do 3-step common check of Oracle DB.
#               It analyzes each step and makes output in nagios format.
#               At the first step it checks listener status by checking if open DB port.
#               At the second step it checks status of DB by simple SQL query.
#               At the third step it checks occupancy of DB tablespaces by another SQL query.
#
#  AUTHOR:      Kirill Minkov <minkov.ke@gmail.com>
#  VERSION:     2.2
#  DATE:        2015-11-18
#
#
#  Copyright (C) 2015 Kirill Minkov aka Isuaven
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use lib qw(/home/scripts/perl_mods /usr/local/nagios/libexec);
use Inf::DBI_Custom;
use Data::Dumper;
use Getopt::Long qw(:config no_ignore_case);
use IO::Socket::PortState qw(check_ports);
use utils qw(%ERRORS $TIMEOUT);

# Version and similar info
my $VERSION = '2.2';
my $DATE    = '2015-11-18';
my $NAME    = $0;
my $AUTHOR  = 'Kirill Minkov';
my $CONTACT = 'minkov.ke@gmail.com';

# Usage text
my $USAGE = <<"END_USAGE";
Usage: $NAME [OPTION]...
END_USAGE

# Help text
my $HELP = <<'END_HELP';

GENERAL OPTIONS:

   -H, --hostname       Hostname or IP (default: localhost)
   -p, --port           Oracle Database port number (default: 1521)
   -S, --sid            Oracle Database SID. Mandatory argument (default: none)
   -U, --user           Oracle Database username. Mandatory argument (default: none)
   -P, --pass           Oracle Database password. Mandatory argument (default: none)
   -w, --warning        Warning threshold for tablespaces in percent (default: 90)
   -c, --critical       Critical threshold for tablespaces in percent (default: 95)
   -t, --timeout        Seconds before connection times out (default: 10)
   -?, --help           This help info
   -v, --version        Display version info
END_HELP

# Version and license text
my $LICENSE = <<"END_LICENSE";
   $NAME version $VERSION of $DATE.

   Copyright (C) 2015 $AUTHOR

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.

   Written by $AUTHOR <$CONTACT>
END_LICENSE

our $ERRORS =
{
        'OK'      => 0,
        'WARNING' => 1,
        'CRITICAL'=> 2,
        'UNKNOWN' => 3
};

sub HelpMessage() {
  print $USAGE, $HELP;
  exit($ERRORS{'UNKNOWN'});
}

sub VersionMessage() {
  print $LICENSE;
  exit($ERRORS{'UNKNOWN'});
}


my $host = "localhost";
my $sid = '';
my $user = '';
my $pass = '';
my $port = 1521;
my $warning = 90;
my $critical = 95;
my $timeout = 10;

die "$0: No arguments given. Use --help or -? for more information.\n" unless @ARGV;

GetOptions ("hostname|H=s"      => \$host,
            "sid|S=s"   => \$sid,
            "user|U=s"  => \$user,
            "pass|P=s"  => \$pass,
            "port|p=i"  => \$port,
            "timeout|t=i"       => \$timeout,
            "warning|w=i"       => \$warning,
            "critical|c=i"       => \$critical,
            "help|?|h"  => sub { HelpMessage() },
            "version|V"  => sub { VersionMessage() })
or die("$0: Unknown argument used, correct your syntax.!!!\n");

unless (length($sid) gt 0 || length($user) gt 0 || length($pass) gt 0) {
  print "$0: Mandatory argument required. Use --help or -? for more information.\n";
  exit($ERRORS{'UNKNOWN'});
}

#  Step 1: Checking listener port avalibility
my %porthash = (
tcp => {
         $port => {
            name => 'Oracle',
         },
      },
);

my $host_hr = check_ports($host,$timeout,\%porthash);
my $yesno = $host_hr->{tcp}{$port}{open} ? "yes" : "no";
unless ( $yesno = "yes" ) {
  print ("CRITICAL: No listener at port $port");
  exit($ERRORS{'CRITICAL'});
}

#  Establish DB connection for Step 1-2
my $dbh = new_connect Inf::DBI_Custom($host,$sid,$port,$user,$pass);

#  Step 2: Checking database status
my $QUERY_status="select status from v\$instance";
my $result = $dbh->queryone($QUERY_status);
my $db_status = $result->[0];

unless ( $db_status eq 'OPEN' ) {
  print "Status of database is $db_status";
  exit($ERRORS{'CRITICAL'});
}

#  Step 3: Checking tablespaces
my $QUERY_tablespaces="
SELECT  a.tablespace_name,
        CASE WHEN b.used_Mb is null then 0 else b.used_Mb end AS used_Mb, a.max_Mb,
        CASE WHEN b.used_Mb is null then 0 else round((b.used_Mb/a.max_Mb)*100,2) end AS used_per from
(SELECT a.tablespace_name,
        round(SUM( CASE WHEN a.autoextensible='YES' THEN a.maxbytes ELSE a.user_bytes END )/1048576) as max_Mb
        FROM sys.dba_data_files a JOIN sys.dba_tablespaces b ON a.tablespace_name=b.tablespace_name
        WHERE b.contents != 'UNDO' GROUP BY a.tablespace_name) a left join
(SELECT a.tablespace_name, round(SUM(a.bytes)/1048576) AS used_Mb FROM DBA_SEGMENTS a GROUP BY a.tablespace_name) b on a.tablespace_name=b.tablespace_name
";
my $ok_message = "DB status: $db_status; TBS OK: ";
my $err_message = "";
my $error = 0;
my $perfdata = "| ";
$result = $dbh->query($QUERY_tablespaces);
foreach (@$result) {
  my ($TBS_NAME,$USED_MB,$MAX_MB,$USED_PER) =  @$_;
  $perfdata .= "'$TBS_NAME'=${USED_MB}MB;0;0;0;$MAX_MB ";
  if ( $USED_PER > $warning && $USED_PER < $critical ) {
    $err_message .= "$TBS_NAME - used $USED_MB Mb($USED_PER%) of $MAX_MB Mb; ";
    if ( $error < 2 ) { $error = 1; }
  } elsif ($USED_PER > $critical) {
    $err_message .= "$TBS_NAME - used $USED_MB Mb($USED_PER%) of $MAX_MB Mb; ";
    $error = 2;
  } else {
    $ok_message .= "$TBS_NAME - used $USED_MB Mb($USED_PER%) of $MAX_MB Mb; ";
  }
}

if ($error == 2) {
  print "TBS CRITICAL: $err_message $perfdata";
  exit($ERRORS{'CRITICAL'});
} elsif ($error == 1) {
  print "TBS WARNING: $err_message $perfdata";
  exit($ERRORS{'WARNING'});
} else {
  print "$ok_message $perfdata";
  exit($ERRORS{'OK'});
}

#  Close DB connection
$dbh->disconnect;
