# 

package Inf::DBI_Custom;

use DBI;
use strict;
$ENV{'SYBASE'} = "/usr/local";

sub new_connect {
  my ($this,$host,$sid,$port,$user,$pass) = @_;
  if ( !(my $dbh_m = DBI->connect("dbi:Oracle:host=$host;sid=$sid;port=$port", $user, $pass)) ) {
    print ("CRITICAL: $DBI::errstr");
    exit 2;
  } else {
    bless {dbh =>$dbh_m}, shift;
  }
}
sub new_mssql {
  my ($this,$host,$user,$pass) = @_;
  if ( !(my $dbh_m = DBI->connect ("dbi:Sybase:server=$host", $user, $pass)) ) {
    print ("CRITICAL: $DBI::errstr");
    exit 2;
  } else {
    bless {dbh =>$dbh_m}, shift;
  }
}

sub query {
  my ($this, $Query) = @_;
  if ( !(my $arr = $this->{dbh}->selectall_arrayref($Query)) ) {
    print ("CRITICAL: $DBI::errstr");
    exit 2;
  } else {
    return $arr;
  }
}

sub queryone {
  my ($this, $Query) = @_;
  if ( !(my $arr = $this->{dbh}->selectall_arrayref($Query)) ) {
    print ("CRITICAL: $DBI::errstr");
    exit 2;
  } else {
    return $arr->[0];
  }
}

sub do {
  my ($this, $Query) = @_;
  if ( !(my $sth = $this->{dbh}->do($Query)) ) {
    print ("CRITICAL: $DBI::errstr");
    exit 2;
  }
}

sub prepare {
  my ($this, $Query) = @_;
  if ( !(my $arr = $this->{dbh}->prepare_cached($Query)) ) {
    print ("CRITICAL: $DBI::errstr");
    exit 2;
  } else {
    return $arr;
  }
}

sub commit {
  my ($this) = @_;
  $this->{dbh}->commit();
  $this->{dbh}->{'AutoCommit'} = 1;
}

sub do_without_die {
 my ($this, $Query) = @_;
 my $sth = $this->{dbh}->do($Query);
}

sub disconnect {
 my ($this) = @_;
 $this->{dbh}->disconnect;
}
1;
