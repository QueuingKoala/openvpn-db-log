OpenVPN DB Log README
=====================

OpenVPN DB Log is a project to log OpenVPN connect and disconnect events to a
database.

Overview
--------

This project logs OpenVPN connect / disconnect events to a database. The code is
in Perl, so adding support for new backend databases is fairly simple.

The OpenVPN DB Log project is licensed under the GPLv3 license:

* http://opensource.org/licenses/GPL-3.0

Requirements
------------

To use this project meaningfully, you will need:

 * OpenVPN, without which this project won't be of much use
 * Perl installed, and available to execute this project's script
 * The DBI Perl module, plus the relevant DBD:: module for your database
 * The SQL server you are connecting to must be configured for access
 * If this is a new setup, you must load the project schema into the database

Quickstart
----------

For the impatient, a minimal setup includes a connect and disconnect association
with OpenVPN, plus telling it about the database you want to use. This example
uses SQLite, but you're free to use any available backend.

You'll need to create a new database with the schema. For SQLite, you can do:

    sqlite3 /var/db/vpn.sqlite < ./schema/sqlite.sql

Then add the following 2 lines in your OpenVPN config file to provide a basic
logging setup, using the same database (lines wrapped for readability)

    client-connect /usr/local/bin/openvpn-db-log.pl -b SQLite
      -d /var/db/vpn.sqlite

    client-disconnect /usr/local/bin/openvpn-db-log.pl -b SQLite
      -d /var/db/vpn.sqlite

Additional features for database backends, recording the server program
instance, and live-client-updates are described in more detail below.

Databases supported
-------------------

Multiple databases are supported by available Perl DBD backends as available on
the local system. So long as you have the DBD driver available and a schema, the
code should work with most standard SQL systems.

Most database backends will require a server, database name, and user
credentials. See the `Database options` help output for the program flags for
each. If your particular database doesn't require one of these, simply omit the
option.

If there isn't a schema available for your preferred RDBMS, consider creating
and contributing one (more info in docs/Hacking.md.)

## Database credentials

  If your database backend requires credentials, you can supply them either with
  the --user / --pass options, or with a --credentials (-C) file. When used, the
  first 2 lines of a credentials file will be taken as the user and password.

Standard features
-----------------

In addition to database connection options, some standard features are
available.

## Forking: allow user connections if logging fails

  Normally, on-connect processing will report a non-zero status if SQL logging
  fails. This will cause OpenVPN to reject the connection when the script is
  called using the --client-connect OpenVPN directive.

  Where this is undesirable and you want to allow the client connection anyway
  (simply unlogged) you should enable the --fork (-f) option.

  This causes backgrounding of the logging before the SQL connection, returning
  code 0 (success) to OpenVPN so the client connection may continue.

  Note that the script may still exit non-zero if a failure occurs before
  reaching the SQL connect stage. Read about the `Zero` feature to avoid this.

## Zero Return: always exit code 0 no matter what

  Some implementations may want a 0 exit code in the face of fatal problems,
  such as missing env-vars or bogus command options.

  For this, enable the --zero (-z) flag. Error messages are still printed to
  standard error.

## Quiet: do not print error text

  To disable printing of error messages, pass the --quiet (-q) flag.

  The exit code is not changed, but can be combined with the --zero flag.

Custom database DSN options
---------------------------

As an advanced/alternative form to provide database values like the database
name, host, port, etc, the --dsn command line option allows you to set any DSN
attribute you would like. This also works for non-standard values if your
specific database backend requires one.

The form of this option is: `--dsn opt=value`

This method can NOT be used to define the backend driver (-b) or the user/pass
(-u/-p) options. This is only valid for the database DSN options.

For example, the following two calls are identical:

    openvpn-db-log -b mysql -d vpn_db -H localhost -t 3306 -u db_user -p db_pass

    openvpn-db-log -b mysql --dsn database=vpn_db --dsn host=localhost \
      --dsn port=3306 -u db_user -p db_pass

Processing status files
-----------------------

In order to provide more up-to-date logs and session data, it is possible to
parse an OpenVPN status-file and update the duration and byte-transfer fields
for connected clients. This allows a "partial-update" to occur, even though the
time of disconnect is not yet known.

This is especially useful in environments where long-lived connections are
common. When an OpenVPN server is terminated (or the app/OS crashes) there will
be no disconnect event despite a partial database row for the connection.

## Status file requirements

  In order to do partial-updates of status files, you must:
    * Enable the `--status-file` OpenVPN directive
    * Set the `--status-version` to version 2 or 3 (v1 is not supported)
    * Enable regular processing of the status file (see below)

## Sending the status file for log processing

  You will need to set up some regular process by which the program is told to
  parse a status file from OpenVPN; this could be cron, or some other on-demand
  event that suits your needs.

  The --status-file (-S) flag is the file path and the --status-version (-V)
  flag must match the OpenVPN setting by the same name (v3 is the default.)

  As an advanced feature, the -N flag mandates that every client line must be
  successfully matched and added to the database in order for the transaction to
  go through.  This is probably only useful for people processing the real-time
  output of a `status` command from OpenVPN using the STDIN input support; and
  only then when this is desired behavior.

## Allowable status file age

  The --status-age (-A) flag sets a maximum allowable increase between the
  status file timestamp and the current system clock, in seconds. If an OpenVPN
  server has terminated, the status file is often left as-is; this option
  prevents needless database connections.

Instance support: logging for multiple servers
----------------------------------------------

Some environments have multiple OpenVPN servers and would like to log them to a
single backend. Common examples include running on TCP + UDP, leveraging
multiple CPU cores, or even separate servers being logged centrally.

In order to identify the correct source of connections in a multi-instance
environment, 3 optional instance descriptors are available:

  * `Name`: a textual name or description, up to 64 characters
  * `Protocol`: a textual protocol, up to 10 characters
  * `Port`: a TCP/UDP port in the range of 1-65535

These options default to empty strings and the pseudo-value `0` respectively.

When using this feature, the **unique** combination of these 3 values defines a
separate instance. This means that if you log some connections with name=Blue,
then other connections with name=Blue port=1195, these would be stored
internally with different instance IDs.

## Changing instance values

  Once an instance association has been added to the database, the unique
  combination appears in the `instances` table. This means updating values is
  possible without much effort, but will require an update to the table entry
  for the instance definition.

  This may eventually be made easier through a utility script. Note that this
  information is stored in the `instances` table alone, and referenced as an ID
  from the `sessions` table.

Versions and schema stability
-----------------------------

Running release-versions is the safest way to go as this project won't guarantee
schema stability for non-release versions. Official releases will contain
incremental SQL upgrade scripts for any schema changes.

If you're not comfortable adjusting database schema between versions as
necessary, a development branch is probably not for you.

