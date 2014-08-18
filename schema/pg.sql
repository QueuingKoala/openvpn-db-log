CREATE TABLE session (
	id bigserial UNIQUE PRIMARY KEY,
	instance_id bigint NOT NULL,
	connect_time bigint NOT NULL,
	src_ip inet NOT NULL,
	src_port integer NOT NULL,
	cn varchar(64) NOT NULL,
	vpn_ip4 inet,
	vpn_ip6 inet,
	disconnect_time bigint,
	duration integer,
	bytes_in bigint ,
	bytes_out bigint ,
	CONSTRAINT unique_session UNIQUE (instance_id, connect_time, src_ip, src_port, cn)
);

CREATE TABLE instance (
	id bigserial UNIQUE PRIMARY KEY,
	name varchar(64) NOT NULL DEFAULT '',
	port integer NOT NULL DEFAULT 0,
	protocol varchar(10) NOT NULL DEFAULT '',
	CONSTRAINT unique_instance UNIQUE (name, port, protocol)
);
