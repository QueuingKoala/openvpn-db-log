OpenVPN DB Log project Release Notes
====================================

Important changes and information between release versions will be listed here.

## 0.9.0

  This is the first official release version, supporting MySQL, PostgreSQL, and
  SQLite as backends.

  **Note** that due to current upstream limitations no logging is available for
  IPv6 addresses assigned to VPN clients. This information is not provided to
  scripts, and cannot be entered into the database as a result. Support for this
  feature will be added when OpenVPN supports it. However, connections made to
  the VPN server over IPv6 are logged with the correct client IPv6 source.

