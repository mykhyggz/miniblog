DROP TABLE users;
CREATE TABLE users ( id integer not null primary key, username nvarchar, password nvarchar, role character, email nvarchar, site_config text, last_session_id char(32));
INSERT INTO users VALUES(0,"Admin",NULL,"Admin","mykhyggz@netscape.net",NULL,NULL); 
SELECT * from users;
