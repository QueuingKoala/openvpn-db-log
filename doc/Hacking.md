OpenVPN DB Log Hacking Intro
============================

New RDBMS schemas
-----------------

If you have an RDBMS that does not currently have a schema available, consider
providing one. Be aware the upgrade model requires any schema changes between
official release versions to have an incremental upgrade path.

Database backends not under active support may be re-located to a contrib/
sub-directory if there's a lack of interest or support to maintain contributed
schemas.

If you'd like to help maintain a schema that is not currently available, please
get in touch and some coordination can happen in preparation for releases.

SQL Code Changes
----------------

Changes to the SQL parts of the code proper should be made in a way that
supports all database backends. This generally means testing against the
backends, and avoiding changes that require features from a particular RDBMS.
