#!/usr/bin/perl

# Log openvpn connections to a DB.
# Handles both connect and disconnect events, keyed by exposed env-vars.

# Copyright Josh Cepek <josh.cepek@usa.net> 2014
# Available under the GPLv3 license:
# http://opensource.org/licenses/GPL-3.0

use strict;
use Getopt::Long;
use DBI;
Getopt::Long::Configure ("bundling");

my $db;
my ($host, $port) = ('', '');
my $user = undef;
my $pass = undef;
my $backend = "SQLite";
my $fork = 0;
my $silent = 0;
my %i = (
	name	=> '',
	proto	=> '',
	port	=> 0,
);
my %status = (
	need_success	=> 0,
	version		=> 3,
);
GetOptions(
	"fork|f!"		=> \$fork,
	"quiet|q!"		=> \$silent,
	"backend|b=s"		=> \$backend,
	"database|db|d=s"	=> \$db,
	"host|h=s"		=> \$host,
	"user|u=s"		=> \$user,
	"password|pass|p=s"	=> \$pass,
	"instance-name|n=s"	=> \$i{name},
	"instance-proto|r=s"	=> \$i{proto},
	"instance-port|o=i"	=> \$i{port},
	"status-file|S:s"	=> \$status{file},
	"status-version|V=i"	=> \$status{version},
	"status-need-success|N"	=> \$status{need_success},
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

my $dbh;

# Status file processing won't continue below
status_proc() if defined $status{file};

# Define env-vars to check, and shorter reference option names.
# Disconnect/update will add to this hash later if needed
my %o = (
	time		=> 'time_unix',
	src_port	=> 'trusted_port',
	vpn_ip4		=> 'ifconfig_pool_remote_ip',
	cn		=> 'common_name',
);

# Set var requirements and sub handler depending on script_type
my $type;
$type = $ENV{script_type}
	or failure("Missing required script_type env-var");
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
elsif ( $type =~ /^db-update$/) {
	$handler = \&update;
	# vars required for updates:
	%o = (
		%o,
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

# Need either trusted_ip or trusted_ip6 from env:
for $var (qw(trusted_ip trusted_ip6)) {
	defined $ENV{$var}
		and $o{src_ip} = $ENV{$var};
}
defined $o{src_ip}
	or failure("ERR: missing env-var: trusted_ip");

# When forking, exit success and continue SQL tasks as the child process
fork and exit 0 if $fork;

db_connect();

# CN may contain special chars:
$o{cn} = $dbh->quote($o{cn});

# Take the right DB update action depending on script type.
# Any database errors escape the eval to be handled below.
eval {
	$handler->();
};

# Handle any DB transaction errors from the handler sub
db_rollback($@) if ($@);

# Success otherwise
exit 0;

# Exit handler, for message display and return code control
sub failure {
	my ($msg) = @_;
	warn "$msg" if $msg and not $silent;
	exit 100;
};

# Generic DB error handler
sub db_rollback {
	my $msg = shift || "";
	eval { $dbh->rollback; };
	failure($msg);
}

# Connect to the SQL DB
sub db_connect {
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

	# DB-quote strings from instance options:
	$i{name} = $dbh->quote($i{name});
	$i{proto} = $dbh->quote($i{proto});
}

# Insert the connect data
sub connect {
	my $iid = get_instance(create => 1);
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
	my $iid = get_instance();
	my $id = match_session_id($iid);

	# Update session details with disconnect values:
	$o{disconnect_time} = $o{time} + $o{duration};
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

# Update a session
sub update {
	my %f_opt = (
		commit => 1,
		@_
	);
	my $iid = $f_opt{iid} || get_instance();
	my $update_time = $o{time_update} || time();
	my $sth;
	my $id = match_session_id($iid);

	# Calculate current duration, and basic sanity check:
	$o{duration} = $update_time - $o{time};
	$o{duration} >= 0 or die "Failed update: time has gone backwards";

	# Update session details with supplied values:
	$sth = $dbh->prepare(qq{
		UPDATE OR FAIL
			session
		SET
			duration = '$o{duration}',
			bytes_in = '$o{bytes_in}',
			bytes_out = '$o{bytes_out}'
		WHERE
			id = '$id'
	});
	$sth->execute;
	$dbh->commit if ( $f_opt{commit} );
}

# Get ID of an instance.
# When the `create` opt is true, will attempt to create if needed
sub get_instance {
	my %f_opt = (
		create	=> 0,
		@_
	);
	my $sth = $dbh->prepare(qq{
		SELECT	id
		FROM	instance
		WHERE
			name = $i{name}
		  AND	port = '$i{port}'
		  AND	protocol = $i{proto}
		ORDER BY
			id ASC
		LIMIT	1
	});
	$sth->execute;
	my $id = $sth->fetchrow_array;
	# Try to add instance details if none present
	if ( ! defined $id and ($f_opt{create}) ) {
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
			'$i{port}',
			$i{proto}
		)
	});
	return get_instance();
}

sub match_session_id {
	my ($iid) = @_;
	my $sth;
	# Associate with the connect session using env-vars:
	$sth = $dbh->prepare(qq{
		SELECT	id
		FROM	session
		WHERE
			disconnect_time IS NULL
		  AND	connect_time = '$o{time}'
		  AND	src_ip = '$o{src_ip}'
		  AND	src_port = '$o{src_port}'
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
	return $id;
}

# Process a status file
sub status_proc {
	my $input;
	my $delim;
	$delim = "\t" if ($status{version} == 3);
	$delim = "," if ($status{version} == 2);
	defined $delim or failure("Invalid status version: must be 2 or 3");

	if ( length($status{file}) > 0 ) {
		open($input, "<", $status{file})
			or failure("Failed to open '$status{file}' for reading");
	}
	else {
		open($input, "<-")
			or failure("Failed to open STDIN for status reading");
	}

	# DB setup:
	db_connect();
	# Pull the instance-ID out early to avoid re-quering each call to update()
	my $iid;
	eval {
		my $iid = get_instance();
	};
	failure($@) if ($@);

	my @fields;
	my $bad_lines = 0;
	while (<$input>) {
		chomp;
		# pull out time:
		if ( /^TIME$delim.*$delim([0-9]+)$/ ) {
			$o{time_update} = $1;
		}
		next unless defined $o{time_update};

		# Otherwise process client list lines.
		next unless /^CLIENT_LIST($delim.*){8}/;
		@fields = split /$delim/;
		shift @fields;

		# CN can have a comma, so process records from the right until then.
		for my $key (qw(user time junk bytes_out bytes_in vpn_ip4 remote)) {
			$o{$key} = pop @fields;
		}

		# Remainder is the CN:
		$o{cn} = $dbh->quote( join('', @fields) );

		# pull source IP/port:
		if ( $o{remote} =~ /^(.+):([0-9]+)$/ ) {
			$o{src_ip} = $1;
			$o{src_port} = $2;
		}
		else {
			$bad_lines += 1;
			next;
		}

		# Now perform the update, which uses values assigned to %o:
		eval {
			update(
				iid	=> $iid,
				commit	=> 0,
			);
		};
		# Error handling:
		# Only do a rollback when 100% success is required:
		db_rollback($@) if ($@) and ($status{need_success});
		# Otherwise just count the failure:
		$bad_lines += 1 if ($@);
	}

	# Final DB commit:
	eval {
		$dbh->commit();
	};
	# Error handling:
	db_rollback($@) if ($@);

	$bad_lines = 99 if ($bad_lines > 99);
	exit $bad_lines;
}

