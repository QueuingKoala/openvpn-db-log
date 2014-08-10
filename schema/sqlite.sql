CREATE TABLE session (
	id integer primary key autoincrement,
	instance_id int NOT NULL,
	connect_time int NOT NULL,
	src_ip text NOT NULL,
	src_port int NOT NULL,
	cn text NOT NULL,
	vpn_ip4 text,
	disconnect_time int,
	duration int,
	bytes_in int,
	bytes_out int,
	CONSTRAINT unique_session UNIQUE (instance_id, connect_time, src_ip, src_port, cn)
);

CREATE TABLE instance (
	id integer primary key autoincrement,
	name text NOT NULL DEFAULT '',
	port int NOT NULL DEFAULT 0,
	protocol text NOT NULL DEFAULT '',
	CONSTRAINT unique_instance UNIQUE (name, port, protocol)
);

