OpenVPN DB Log README
=====================

Overview
--------

This project logs OpenVPN connect / disconnect events to a database. The code is
in Perl, so adding support for new backend databases is fairly simple.

The OpenVPN DB Log project is licensed under the GPLv3 license:

* http://opensource.org/licenses/GPL-3.0

Current DB support
------------------

Multiple database backends are supported by available Perl DBI backends as
available on the local system. The SQLite backend is the default if another
backend is not specified as support is built-into recent Perl versions.

Versions and schema stability
-----------------------------

Running release-versions is the safest way to go as this project won't guarantee
schema stability for non-release versions.

If you're not comfortable adjusting database schema between versions if
necessary, a development branch is probably not for you.

