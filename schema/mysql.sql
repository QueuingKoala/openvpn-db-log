CREATE TABLE session (
	id bigint unsigned NOT NULL AUTO_INCREMENT UNIQUE PRIMARY KEY,
	instance_id bigint unsigned NOT NULL,
	connect_time bigint NOT NULL,
	src_ip varchar(39) NOT NULL,
	src_port smallint unsigned NOT NULL,
	vpn_ip4 varchar(15) NOT NULL,
	cn varchar(64) NOT NULL,
	disconnect_time bigint,
	duration integer,
	bytes_in bigint unsigned,
	bytes_out bigint unsigned,
	UNIQUE (instance_id, connect_time, vpn_ip4, cn)
);

CREATE TABLE instance (
	id bigint unsigned NOT NULL AUTO_INCREMENT UNIQUE PRIMARY KEY,
	name varchar(64) NOT NULL DEFAULT '',
	port smallint unsigned NOT NULL DEFAULT 0,
	protocol varchar(10) NOT NULL DEFAULT '',
	UNIQUE (name, port, protocol)
);
