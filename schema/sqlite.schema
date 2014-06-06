CREATE TABLE session (
	id integer primary key autoincrement,
	instance_id integer NOT NULL,
	connect_time bigint NOT NULL,
	src_ip varchar(39) NOT NULL,
	src_port unsigned smallint NOT NULL,
	vpn_ip4 varchar(15) NOT NULL,
	cn varchar(64) NOT NULL,
	disconnect_time bigint,
	duration integer,
	bytes_in unsigned bigint,
	bytes_out unsigned bigint,
	UNIQUE (instance_id, connect_time, vpn_ip4, cn)
);

CREATE TABLE instance (
	id integer primary key autoincrement,
	name varchar(64) NOT NULL DEFAULT '',
	port unsigned smallint NOT NULL DEFAULT 0,
	protocol varchar(10) NOT NULL DEFAULT '',
	UNIQUE (name, port, protocol)
);

