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
my %i = (
	name	=> '',
	proto	=> '',
	port	=> 0,
);
GetOptions(
	"fatal-failure|F!"	=> \$rc_fail,
	"quiet|q!"		=> \$silent,
	"backend|b=s"		=> \$backend,
	"database|db|d=s"	=> \$db,
	"host|h=s"		=> \$host,
	"user|u=s"		=> \$user,
	"password|pass|p=s"	=> \$pass,
	"instance-name|n=s"	=> \$i{name},
	"instance-proto|r=s"	=> \$i{proto},
	"instance-port|o=i"	=> \$i{port},
);

# Verify CLI opts
defined $db or
	failure("Options error: No database specified");
length($i{name}) <= 64
	or failure("Options error: instance-name too long (>64)");
length($i{proto}) <= 10
	or failure("Options error: instance-proto too long (>10)");
$i{port} >= 0 and $i{port} <= 65535
	or failure("Options error: instance-port out of range (1-65535)");

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

# Quote strings that may contain special chars:
$o{cn} = $dbh->quote($o{cn});
$i{name} = $dbh->quote($i{name});
$i{proto} = $dbh->quote($i{proto});

# Take the right DB update action depending on script type.
# Any database errors escape the eval to be handled below.
eval {
	$handler->();
};

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
	my $iid = get_instance();
	defined $iid or die "Failed to obtain instance";
	$dbh->do(qq{
		INSERT INTO
		session (
			connect_time,
			src_ip,
			src_port,
			vpn_ip4,
			cn,
			instance_id
		)
		VALUES (
			'$o{time}',
			'$o{src_ip}',
			'$o{src_port}',
			'$o{vpn_ip4}',
			$o{cn},
			'$iid'
		)

	});
	$dbh->commit;
}

# Insert the disconnect data
sub disconnect {
	my $sth;
	my $iid = get_instance('');
	defined $iid or die "Failed to obtain instance";
	# Associate with the connect session using env-vars:
	$sth = $dbh->prepare(qq{
		SELECT	id
		FROM	session
		WHERE
			disconnect_time is null
		  AND	connect_time = '$o{time}'
		  AND	vpn_ip4 = '$o{vpn_ip4}'
		  AND	cn = $o{cn}
		  AND	instance_id = '$iid'
		ORDER BY
			id DESC
		LIMIT	1
	});
	$sth->execute;
	my $id = $sth->fetchrow_array
		or die "No matching connection entry found";

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

sub get_instance {
	my ($init) = @_;
	defined $init or $init = 1;
	my $sth = $dbh->prepare(qq{
		SELECT	id
		FROM	instance
		WHERE
			name = $i{name}
		  AND	port = $i{port}
		  AND	protocol = $i{proto}
		ORDER BY
			id ASC
		LIMIT	1
	});
	$sth->execute;
	my $id = $sth->fetchrow_array;
	# Try to add instance details if none present
	if (! defined $id and $init) {
		$id = add_instance();
	}
	return $id if defined $id;
	die "Failed instance association";
}

sub add_instance {
	$dbh->do(qq{
		INSERT OR FAIL INTO instance (
			name,
			port,
			protocol
		)
		values (
			$i{name},
			$i{port},
			$i{proto}
		)
	});
	return get_instance('');
}

