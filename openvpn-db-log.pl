#!/usr/bin/perl

# Log openvpn connections to a DB.
# Handles both connect and disconnect events, keyed by exposed env-vars.

# Copyright Josh Cepek <josh.cepek@usa.net> 2014
# Available under the GPLv3 license:
# http://opensource.org/licenses/GPL-3.0

use strict;
use Getopt::Long;
use DBI;

my $db;
my ($host, $port) = ('', '');
my $user = undef;
my $pass = undef;
my $backend = "SQLite";
my $rc_fail = 0;
my $silent = '';
GetOptions(
	"fatal-failure|F!"	=> \$rc_fail,
	"quiet|q!"		=> \$silent,
	"backend|b=s"		=> \$backend,
	"database|db|d=s"	=> \$db,
	"host|h=s"		=> \$host,
	"user|u=s"		=> \$user,
	"password|pass|p=s"	=> \$pass,
);

defined $db or
	failure("Options error: No database specified");

# Define env-vars to check, and shorter reference option names.
# Disconnect will add to this hash later if needed
my %o = (
	time		=> 'time_unix',
	src_ip		=> 'trusted_ip',
	src_port	=> 'trusted_port',
	vpn_ip4		=> 'ifconfig_pool_remote_ip',
	cn		=> 'common_name',
);

# Set var requirements and sub handler depending on script_type
my $type = $ENV{script_type}
	or failure("ERR: script_type is unset");
my $handler = \&connect;
if ( $type =~ /^client-disconnect$/ ) {
	$handler = \&disconnect;
	# add some additional vars used during disconnect
	%o = (
		%o,
		duration	=> 'time_duration',
		bytes_in	=> 'bytes_received',
		bytes_out	=> 'bytes_sent',
	);
}
elsif ( $type !~ /^client-connect$/ ) {
	failure("Invalid script_type: '$type'");
}

# Verify and set env-var values
# In each case, the actual value is assigned to %o.
my $var;
for my $key (keys %o) {
	$var = $o{$key};
	defined $ENV{$var}
		or failure("ERR: missing env-var: $var");
	$o{$key} = $ENV{$var};
}

# On disconnect, the event time must be calculaed
$type =~ /^client-disconnect$/
	and $o{disconnect_time} = $o{time} + $o{duration};

# Connect to the SQL DB
my $dbh;
$dbh = DBI->connect(
	"dbi:$backend:database=$db;host=$host;port=$port",
	$user,
	$pass, {
		AutoCommit	=> 0,
		PrintError	=> 0,
	}
);
# Handle DB connect errors
defined $dbh
	or failure("DB connection failed: ($DBI::errstr)");
$dbh->{RaiseError} = 1;

# In certain OpenVPN modes the common_name may have special chars.
# Quote it according to the database needs
$o{cn} = $dbh->quote($o{cn});

# Take the right DB update action depending on script type.
# Any database errors escape the eval to be handled below.
eval $handler->();

# Handle any DB transaction errors from the handler sub
if ($@) {
	my $msg = "$@";
	eval { $dbh->rollback; };
	failure($msg);
}

# Exit handler, for message display and return code control
sub failure {
	my ($msg) = @_;
	warn "$msg" if $msg and not $silent;
	exit $rc_fail;
};

# Insert the connect data
sub connect {
	$dbh->do(qq{
		INSERT INTO
		session (
			connect_time,
			src_ip,
			src_port,
			vpn_ip4,
			cn
		)
		VALUES (
			'$o{time}',
			'$o{src_ip}',
			'$o{src_port}',
			'$o{vpn_ip4}',
			$o{cn}
		)

	});
	$dbh->commit;
}

# Insert the disconnect data
sub disconnect {
	my $sth;
	# Associate with the connect session using env-vars:
	$sth = $dbh->prepare(qq{
		SELECT	id
		FROM	session
		WHERE
			disconnect_time is null
		  AND	connect_time = '$o{time}'
		  AND	vpn_ip4 = '$o{vpn_ip4}'
		  AND	cn = $o{cn}
		ORDER BY
			id DESC
		LIMIT	1
	});
	$sth->execute;
	my $id = $sth->fetchrow_array
		or failure("No matching connection entry found");

	# Update session details with disconnect values:
	$sth = $dbh->prepare(qq{
		UPDATE OR FAIL
			session
		SET
			disconnect_time = '$o{disconnect_time}',
			duration = '$o{duration}',
			bytes_in = '$o{bytes_in}',
			bytes_out = '$o{bytes_out}'
		WHERE
			id = '$id'
	});
	$sth->execute;
	$dbh->commit;
}

