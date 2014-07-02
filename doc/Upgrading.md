OpenVPN DB Log Upgrades
=======================

In addition to any code changes, upgrades may require schema changes between
releases.

Schema upgade policy
--------------------

Any official releases that involve schema updates will include an incremental
upgrade path to convert older databases. All schema updates will need to be
applied incrementally if upgrading through multiple versions.

Unofficial releases (development or "alpha/beta" releases) may change schema as
required, and unofficial database support may not necessarily follow these
guidelines.

## Contributed schemas and upgrades

  For schemas listed under the contrib/ sub-directory, an effort will be made to
  contact an interested maintainer in advance of any prepared official releases.

