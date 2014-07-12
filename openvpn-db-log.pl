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

sub usage {
	printf <<EOM;
OPTIONS:

Database options:
  --backend, -b
      The Perl DBI backend to use. Mandatory.
  --database, --db -d
      The database to connect to.
  --host, -H
      Database host to connect to.
  --port, -t
      Port number to connect to.
  --user, -u
      Database username.
  --password, pass, -p
      Database password.
  --credentials, --cred, -C
      File for database authentication, user/pass on first 2 lines.
  --dsn
      An advanced method to define DB DSN options in the form: opt=value
      See docs for details.

Basic options:
  --fork, -f
      After basic option checking, exit code 0 and fork for SQL processing.
  --quiet, -q
      Do not report any errors to STDERR (does not change the exit code.)
  --zero, -z
      Failure exits with code 0, primarily for systems lacking Perl fork().
  --help, --usage, -h
      You're reading it.

Instance options:
  --instance-name, -n (up to 64 chars)
  --instance-proto, -r (up to 10 chars)
  --instance-port, -o
      Optional values to identify a unique OpenVPN instance (see docs.)

Status file processing:
  --status-file, -S
      Path to the status file. Supply an empty string argument for STDIN.
  --status-version, -V
      OpenVPN status format version. Must be 2 or 3, and defaults to 3.
  --status-need-success, -N
      Refuse the update if any client entries fail (see docs.)
  --status-age, -A
      Maximum allowable age in seconds of the status file timestamp.
  --status-info, -I
      Print extra info to STDERR for ignored client lines (see docs.)
EOM
        exit 0;
}

# Database vars:
my %dsn;
my %db = (
	user	=> "",
	pass	=> "",
);
# Common config vars:
my %conf = (
	fork	=> 0,
	quiet	=> 0,
	rc_zero	=> 0,
);
# Instance vars:
my %instance = (
	name	=> '',
	proto	=> '',
	port	=> 0,
);
# Status file vars:
my %status = (
	need_success	=> 0,
	version		=> 3,
	verb		=> 0,
);
GetOptions(
	"fork|f!"		=> \$conf{fork},
	"quiet|q!"		=> \$conf{quiet},
	"zero|z!"		=> \$conf{rc_zero},
	"backend|b=s"		=> \$db{driver},
	"user|u=s"		=> \$db{user},
	"password|pass|p=s"	=> \$db{pass},
	"credentials|creds|C=s"	=> \$db{creds},
	"database|db|d=s"	=> \$dsn{database},
	"host|H=s"		=> \$dsn{host},
	"port|t=i"		=> \$dsn{port},
	"dsn=s"			=> \%dsn,
	"instance-name|n=s"	=> \$instance{name},
	"instance-proto|r=s"	=> \$instance{proto},
	"instance-port|o=i"	=> \$instance{port},
	"status-file|S:s"	=> \$status{file},
	"status-version|V=i"	=> \$status{version},
	"status-need-success|N"	=> \$status{need_success},
	"status-age|A=i"	=> \$status{age},
	"status-info|I+"	=> \$status{verb},
	"help|usage|h"          => \&usage,
);

# Verify CLI opts
defined $db{driver}
	or failure("Options error: no backend driver provided");
length($instance{name}) <= 64
	or failure("Options error: instance-name too long (>64)");
length($instance{proto}) <= 10
	or failure("Options error: instance-proto too long (>10)");
$instance{port} >= 0 and $instance{port} <= 65535
	or failure("Options error: instance-port out of range (1-65535)");

read_creds() if defined $db{creds};

# Status file processing won't continue below
status_proc() if defined $status{file};

# Define required env-vars, keyed by shorter reference names.
# Disconnect/update will add to this hash later if needed
my %data;
env_opt(src_port	=> 'trusted_port');
env_opt(cn		=> 'common_name');
env_opt(vpn_ip4		=> 'ifconfig_pool_remote_ip', "");

# Append to mandatory env-vars and set sub handler depending on script_type
my $type;
$type = $ENV{script_type}
	or failure("Missing required script_type env-var");
my $handler = \&connect;
if ( $type =~ /^client-disconnect$/ ) {
	$handler = \&disconnect;
	# add some additional vars used during disconnect
	env_opt(time		=> 'time_unix');
	env_opt(duration	=> 'time_duration');
	env_opt(bytes_in	=> 'bytes_received');
	env_opt(bytes_out	=> 'bytes_sent');
}
elsif ( $type =~ /^client-connect$/ ) {
	env_opt(time		=> 'time_unix');
}
elsif ( $type =~ /^db-update$/) {
	$handler = \&update;
	# vars required for updates:
	env_opt(bytes_in	=> 'bytes_received');
	env_opt(bytes_out	=> 'bytes_sent');
}
else {
	failure("Invalid script_type: '$type'");
}

# Need either trusted_ip or trusted_ip6 from env:
$data{src_ip} = $ENV{trusted_ip} || $ENV{trusted_ip6}
	or failure("ERR: missing env-var: trusted_ip");

# When forking, exit success and continue SQL tasks as the child process
db_fork() if ( $conf{fork} );

db_connect();

# Take the right DB update action depending on script type.
# Any database errors escape the eval to be handled below.
eval {
	$handler->();
	$db{dbh}->commit();
};

# Handle any DB transaction errors from the handler sub
db_rollback($@) if ($@);

# Success otherwise
exit 0;

# Exit handler, for message display and return code control
sub failure {
	my ($msg) = @_;
	warn "$msg" if $msg and not $conf{quiet};
	exit 0 if $conf{rc_zero};
	exit 100;
};

# Env-var option helper
# Call as: env_opt( 'opt_name', 'env_var' [, 'default-when-optional']
sub env_opt {
	my ($opt, $env, $default) = @_;
	return if ( $data{$opt} = $ENV{$env} );
	defined $default
		or failure("Error: missing env-var: $env");
	$data{$opt} = $default;
}

# Credentials processing
sub read_creds {
	open(my $fh, "<", $db{creds})
		or failure("Unable to open credentials file");
	($db{user}, $db{pass}) = grep( defined, map(<$fh>, 1..2) );
	defined $db{pass} or failure("Invalid credentials file");
	chomp %db;
}

# Fork handler; closes standard file handles
sub db_fork {
	open(STDIN, "<", "/dev/null");
	open(STDOUT, ">", "/dev/null");
	open(STDERR, ">", "/dev/null");
	fork and exit 0;
}

# Generic DB error handler
sub db_rollback {
	my $msg = shift || "";
	eval { $db{dbh}->rollback; };
	failure($msg);
}

# Connect to the SQL DB
sub db_connect {
	my $driver_dsn = "";
	for my $key (keys %dsn) {
		next unless defined $dsn{$key};
		$driver_dsn .= "$key=$dsn{$key};";
	}
	$driver_dsn =~ s/;$//;
	$db{dbh} = DBI->connect(
		"dbi:$db{driver}:$driver_dsn",
		$db{user},
		$db{pass}, {
			AutoCommit	=> 0,
			PrintError	=> 0,
		}
	);

	# Handle DB connect errors
	defined $db{dbh}
		or failure("DB connection failed: ($DBI::errstr)");
	$db{dbh}->{RaiseError} = 1;
}

# Insert the connect data
sub connect {
	my $iid = get_instance(create => 1);
	$db{dbh}->do(qq{
		INSERT INTO
		session (
			connect_time,
			src_ip,
			src_port,
			vpn_ip4,
			cn,
			instance_id
		)
		VALUES (?, ?, ?, ?, ?, ?)
		},
		undef,
		$data{time},
		$data{src_ip},
		$data{src_port},
		$data{vpn_ip4},
		$data{cn},
		$iid,
	);
}

# Insert the disconnect data
sub disconnect {
	my $sth;
	my $iid = get_instance();
	my $id = match_session_id(iid => $iid);

	# Update session details with disconnect values:
	$data{disconnect_time} = $data{time} + $data{duration};
	$sth = $db{dbh}->do(qq{
		UPDATE
			session
		SET
			disconnect_time = ?,
			duration = ?,
			bytes_in = ?,
			bytes_out = ?
		WHERE
			id = ?
		},
		undef,
		$data{disconnect_time},
		$data{duration},
		$data{bytes_in},
		$data{bytes_out},
		$id,
	);
}

# Update a session
sub update {
	my %f_opt = ( @_ );
	my $iid = $f_opt{iid} || get_instance();
	my $update_time = $f_opt{time_update} || time();

	my $id = match_session_id( iid => $iid );

	# Calculate current duration, and basic sanity check:
	$data{duration} = $update_time - $data{time};
	$data{duration} >= 0 or die "Failed update: time has gone backwards";

	# Prepare update query, unless we have one
	defined $db{sth_update} or $db{sth_update} = $db{dbh}->prepare(qq{
		UPDATE
			session
		SET
			duration = ?,
			bytes_in = ?,
			bytes_out = ?
		WHERE
			id = ?
	});

	# Update session details with supplied values:
	$db{sth_update}->execute(
		$data{duration},
		$data{bytes_in},
		$data{bytes_out},
		$id,
	);
}

# Get ID of an instance.
# When the `create` opt is true, will attempt to create if needed
sub get_instance {
	my %f_opt = (
		create	=> 0,
		@_
	);
	my $sth = $db{dbh}->prepare(qq{
		SELECT	id
		FROM	instance
		WHERE
			name = ?
		  AND	port = ?
		  AND	protocol = ?
		ORDER BY
			id ASC
		LIMIT	1
	});
	$sth->execute(
		$instance{name},
		$instance{port},
		$instance{proto},
	);
	my $id = $sth->fetchrow_array;

	# Try to add instance details if none present
	if ( ! defined $id and ($f_opt{create}) ) {
		$id = add_instance();
	}
	return $id if defined $id;
	die "Failed instance association";
}

sub add_instance {
	$db{dbh}->do(qq{
		INSERT INTO
		instance (
			name,
			port,
			protocol
		)
		values (?, ?, ?)
		},
		undef,
		$instance{name},
		$instance{port},
		$instance{proto},

	);
	return get_instance();
}

# Associate with the connect session using env-vars:
sub match_session_id {
	my %f_opt = ( @_ );
	my @query_opts;
	my $vpn_ip_query = "= ?";
	my $sth_name = "sth_session";
	if (not defined $data{vpn_ip4} or length($data{vpn_ip4}) == 0) {
		$vpn_ip_query = "IS NULL";
		$sth_name .= "_null";
	}
	else {
		push @query_opts, $data{vpn_ip4};
	}
	# Prepare session query, unless we have one
	defined $db{$sth_name} or $db{$sth_name} = $db{dbh}->prepare(qq{
		SELECT	id
		FROM	session
		WHERE
			disconnect_time IS NULL
		  AND	vpn_ip4 $vpn_ip_query
		  AND	connect_time = ?
		  AND	src_ip = ?
		  AND	src_port = ?
		  AND	cn = ?
		  AND	instance_id = ?
		ORDER BY
			id DESC
		LIMIT	1
	});

	# Then run the query on the client option data
	push @query_opts, (
		$data{time},
		$data{src_ip},
		$data{src_port},
		$data{cn},
		$f_opt{iid},
	);
	$db{$sth_name}->execute(@query_opts);

	my $id = $db{$sth_name}->fetchrow_array
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

	db_fork() if ( $conf{fork} );

	my @fields;
	my $iid;
	my $time_update;
	my $bad_lines = 0;
	while (<$input>) {
		chomp;
		# pull out time:
		if ( /^TIME$delim.*$delim([0-9]+)$/ ) {
			if ( defined $status{age} ) {
				( time() - $1 <= $status{age} )
					or failure("Status file exceeds aging limit");
			}
			$time_update = $1;
		}
		next unless defined $time_update;

		# Otherwise process client list lines.
		next unless /^CLIENT_LIST($delim.*){8}/;
		%o = ();
		@fields = split /$delim/;
		shift @fields;

		# CN can have a comma, so process records from the right until then.
		for my $key (qw(user time junk bytes_out bytes_in vpn_ip4 remote)) {
			$data{$key} = pop @fields;
		}

		# Remainder is the CN:
		$data{cn} = join('', @fields);

		# pull source IP/port:
		if ( $data{remote} =~ /^(.+):([0-9]+)$/ ) {
			$data{src_ip} = $1;
			$data{src_port} = $2;
		}
		else {
			warn "bad IP/port in input" if ( $status{verb} >= 1 );
			warn " bad line: $_" if ( $status{verb} >= 2 );
			$bad_lines += 1;
			next;
		}

		# Do any delayed DB setup tasks now that we have a real line:
		if ( ! defined $db{dbh} ) {
			eval {
				db_connect();
				$iid = get_instance();
			};
			failure ($@) if ($@);
		}

		# Now perform the update, which uses values assigned to %o:
		eval {
			update( iid => $iid, time_update => $time_update );
		};
		# Error handling:
		# Only do a rollback when 100% success is required:
		db_rollback($@) if ($@) and ($status{need_success});
		# Otherwise just count the failure:
		if ($@) {
			warn "bad input: $@" if ( $status{verb} >= 1 );
			warn " bad line: $_" if ( $status{verb} >= 2 );
			$bad_lines += 1 if ($@);
		}
	}

	# Final DB commit if anything happened:
	eval {
		$db{dbh}->commit() if defined $db{dbh};
	};
	# Error handling:
	db_rollback($@) if ($@);

	exit 0 if $conf{rc_zero};
	$bad_lines = 99 if ($bad_lines > 99);
	exit $bad_lines;
}

