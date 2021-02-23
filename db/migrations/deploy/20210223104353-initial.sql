-- generated with subzero-cli (https://github.com/subzerocloud/subzero-cli)
BEGIN;

--
-- PostgreSQL database cluster dump
--

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Roles
--

CREATE ROLE anonymous;
CREATE ROLE api;
CREATE ROLE proxy;
CREATE ROLE webuser;
--
-- User Configurations
--

--
-- User Config "authenticator"
--



--
-- Role memberships
--

GRANT anonymous TO authenticator;
GRANT api TO current_user;
GRANT proxy TO authenticator;
GRANT webuser TO authenticator;


--
-- PostgreSQL database cluster dump complete
--


--
-- PostgreSQL database dump
--

-- Dumped from database version 13.1 (Debian 13.1-1.pgdg100+1)
-- Dumped by pg_dump version 13.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: api; Type: SCHEMA; Schema: -; Owner: superuser
--

CREATE SCHEMA api;



--
-- Name: data; Type: SCHEMA; Schema: -; Owner: superuser
--

CREATE SCHEMA data;



--
-- Name: pgjwt; Type: SCHEMA; Schema: -; Owner: superuser
--

CREATE SCHEMA pgjwt;



--
-- Name: request; Type: SCHEMA; Schema: -; Owner: superuser
--

CREATE SCHEMA request;



--
-- Name: response; Type: SCHEMA; Schema: -; Owner: superuser
--

CREATE SCHEMA response;



--
-- Name: settings; Type: SCHEMA; Schema: -; Owner: superuser
--

CREATE SCHEMA settings;



--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--



--
-- Name: customer; Type: TYPE; Schema: api; Owner: superuser
--

CREATE TYPE api.customer AS (
	id integer,
	name text,
	email text,
	role text
);



--
-- Name: user_role; Type: TYPE; Schema: data; Owner: superuser
--

CREATE TYPE data.user_role AS ENUM (
    'webuser'
);



--
-- Name: login(text, text); Type: FUNCTION; Schema: api; Owner: superuser
--

CREATE FUNCTION api.login(email text, password text) RETURNS api.customer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
declare
    usr record;
    token text;
    jwt_lifetime int;
    jwt_secret text;
begin
    jwt_lifetime := coalesce(current_setting('pgrst.jwt_lifetimet',true)::int, 3600);
    jwt_secret := coalesce(settings.get('jwt_secret'), current_setting('pgrst.jwt_secret',true));

    select * from data."user" as u
    where u.email = $1 and u.password = public.crypt($2, u.password)
    into usr;

    if usr is NULL then
        raise exception 'invalid email/password';
    else
        token := pgjwt.sign(
            json_build_object(
                'role', usr.role,
                'user_id', usr.id,
                'exp', extract(epoch from now())::integer + jwt_lifetime
            ),
            jwt_secret
        );
        perform response.set_cookie('SESSIONID', token, jwt_lifetime, '/');
        return (
            usr.id,
            usr.name,
            usr.email,
            usr.role::text
        );
    end if;
end
$_$;



--
-- Name: logout(); Type: FUNCTION; Schema: api; Owner: superuser
--

CREATE FUNCTION api.logout() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
    perform response.delete_cookie('SESSIONID');
end
$$;



--
-- Name: me(); Type: FUNCTION; Schema: api; Owner: superuser
--

CREATE FUNCTION api.me() RETURNS api.customer
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
declare
    usr record;
begin

    select * from data."user"
    where id = request.user_id()
    into usr;

    return (
        usr.id,
        usr.name,
        usr.email,
        usr.role::text
    );
end
$$;



--
-- Name: on_oauth_login(text, json); Type: FUNCTION; Schema: api; Owner: superuser
--

CREATE FUNCTION api.on_oauth_login(provider text, profile json) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
    usr record;
    _email text;
    _name text;
    token text;
    jwt_lifetime int;
    jwt_secret text;
begin
    jwt_lifetime := coalesce(current_setting('pgrst.jwt_lifetimet',true)::int, 3600);
    jwt_secret := coalesce(settings.get('jwt_secret'), current_setting('pgrst.jwt_secret',true));

    -- check the jwt (generated in the proxy) is authorized to perform oauth logins
    if request.jwt_claim('oauth_login') != 'true' then
        raise exception 'unauthorized';
    end if;

    -- depending on oauth provider, extract needed information
    case provider
        when 'google'   then
            _email := profile->>'email';
            _name  := profile->>'name';
        when 'facebook' then
            _email := coalesce(profile->>'email', profile->>'id' || '@facebook.com');
            _name  := profile->>'name';
        when 'github'   then
            _email := profile->>'email';
            _name  := profile->>'name';
        else
            raise exception 'unknown oauth provider';
    end case;

    -- upsert the user to our database, we set the password to somethign random since the user will not be using only the outh login
    insert into data."user" as u
    (name, email, password) values (_name, _email, gen_random_uuid())
    on conflict (email) do nothing
   	returning *
    into usr;

    token := pgjwt.sign(
        json_build_object(
            'role', usr.role,
            'user_id', usr.id,
            'exp', extract(epoch from now())::integer + jwt_lifetime
        ),
        jwt_secret
    );

    -- set the session cookie and redirect to /
    perform response.set_cookie('SESSIONID', token, jwt_lifetime, '/');
    perform response.set_header('location', '/');
    perform set_config('response.status', '303', true);
end
$$;



--
-- Name: refresh_token(); Type: FUNCTION; Schema: api; Owner: superuser
--

CREATE FUNCTION api.refresh_token() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
declare
    usr record;
    token text;
    jwt_lifetime int;
    jwt_secret text;
begin
    jwt_lifetime := coalesce(current_setting('pgrst.jwt_lifetimet',true)::int, 3600);
    jwt_secret := coalesce(settings.get('jwt_secret'), current_setting('pgrst.jwt_secret',true));

    select * from data."user" as u
    where id = request.user_id()
    into usr;

    if usr is null then
        raise exception 'user not found';
    else
        token := pgjwt.sign(
            json_build_object(
                'role', usr.role,
                'user_id', usr.id,
                'exp', extract(epoch from now())::integer + jwt_lifetime
            ),
            jwt_secret
        );
        perform response.set_cookie('SESSIONID', token, jwt_lifetime, '/');
        return true;
    end if;
end
$$;



--
-- Name: user_id(); Type: FUNCTION; Schema: request; Owner: superuser
--

CREATE FUNCTION request.user_id() RETURNS integer
    LANGUAGE sql STABLE
    AS $$
    select 
    case coalesce(current_setting('request.jwt.claim.user_id', true),'')
    when '' then 0
    else current_setting('request.jwt.claim.user_id', true)::int
	end
$$;



SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: todo; Type: TABLE; Schema: data; Owner: superuser
--

CREATE TABLE data.todo (
    id integer NOT NULL,
    todo text NOT NULL,
    private boolean DEFAULT true,
    owner_id integer DEFAULT request.user_id()
);



--
-- Name: todos; Type: VIEW; Schema: api; Owner: api
--

CREATE VIEW api.todos AS
 SELECT todo.id,
    todo.todo,
    todo.private,
    (todo.owner_id = request.user_id()) AS mine
   FROM data.todo;


ALTER TABLE api.todos OWNER TO api;

--
-- Name: search_items(text); Type: FUNCTION; Schema: api; Owner: superuser
--

CREATE FUNCTION api.search_items(query text) RETURNS SETOF api.todos
    LANGUAGE sql STABLE
    AS $$
select * from api.todos where todo like query
$$;



--
-- Name: signup(text, text, text); Type: FUNCTION; Schema: api; Owner: superuser
--

CREATE FUNCTION api.signup(name text, email text, password text) RETURNS api.customer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
declare
    usr record;
    token text;
    cookie text;
    jwt_lifetime int;
    jwt_secret text;
begin
    jwt_lifetime := coalesce(current_setting('pgrst.jwt_lifetimet',true)::int, 3600);
    jwt_secret := coalesce(settings.get('jwt_secret'), current_setting('pgrst.jwt_secret',true));

    insert into data."user" as u
    (name, email, password) values ($1, $2, $3)
    returning *
   	into usr;

    token := pgjwt.sign(
        json_build_object(
            'role', usr.role,
            'user_id', usr.id,
            'exp', extract(epoch from now())::integer + jwt_lifetime
        ),
        jwt_secret
    );
    perform response.set_cookie('SESSIONID', token, jwt_lifetime, '/');
    return (
        usr.id,
        usr.name,
        usr.email,
        usr.role::text
    );
end
$_$;



--
-- Name: encrypt_pass(); Type: FUNCTION; Schema: data; Owner: superuser
--

CREATE FUNCTION data.encrypt_pass() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if new.password is not null then
  	new.password = public.crypt(new.password, public.gen_salt('bf'));
  end if;
  return new;
end
$$;



--
-- Name: algorithm_sign(text, text, text); Type: FUNCTION; Schema: pgjwt; Owner: superuser
--

CREATE FUNCTION pgjwt.algorithm_sign(signables text, secret text, algorithm text) RETURNS text
    LANGUAGE sql
    AS $$
WITH
  alg AS (
    SELECT CASE
      WHEN algorithm = 'HS256' THEN 'sha256'
      WHEN algorithm = 'HS384' THEN 'sha384'
      WHEN algorithm = 'HS512' THEN 'sha512'
      ELSE '' END)  -- hmac throws error
SELECT pgjwt.url_encode(public.hmac(signables, secret, (select * FROM alg)));
$$;



--
-- Name: sign(json, text, text); Type: FUNCTION; Schema: pgjwt; Owner: superuser
--

CREATE FUNCTION pgjwt.sign(payload json, secret text, algorithm text DEFAULT 'HS256'::text) RETURNS text
    LANGUAGE sql
    AS $$
WITH
  header AS (
    SELECT pgjwt.url_encode(convert_to('{"alg":"' || algorithm || '","typ":"JWT"}', 'utf8'))
    ),
  payload AS (
    SELECT pgjwt.url_encode(convert_to(payload::text, 'utf8'))
    ),
  signables AS (
    SELECT (SELECT * FROM header) || '.' || (SELECT * FROM payload)
    )
SELECT
    (SELECT * FROM signables)
    || '.' ||
    pgjwt.algorithm_sign((SELECT * FROM signables), secret, algorithm);
$$;



--
-- Name: url_decode(text); Type: FUNCTION; Schema: pgjwt; Owner: superuser
--

CREATE FUNCTION pgjwt.url_decode(data text) RETURNS bytea
    LANGUAGE sql
    AS $$
WITH t AS (SELECT translate(data, '-_', '+/')),
     rem AS (SELECT length((SELECT * FROM t)) % 4) -- compute padding size
    SELECT decode(
        (SELECT * FROM t) ||
        CASE WHEN (SELECT * FROM rem) > 0
           THEN repeat('=', (4 - (SELECT * FROM rem)))
           ELSE '' END,
    'base64');
$$;



--
-- Name: url_encode(bytea); Type: FUNCTION; Schema: pgjwt; Owner: superuser
--

CREATE FUNCTION pgjwt.url_encode(data bytea) RETURNS text
    LANGUAGE sql
    AS $$
    SELECT translate(encode(data, 'base64'), E'+/=\n', '-_');
$$;



--
-- Name: verify(text, text, text); Type: FUNCTION; Schema: pgjwt; Owner: superuser
--

CREATE FUNCTION pgjwt.verify(token text, secret text, algorithm text DEFAULT 'HS256'::text) RETURNS TABLE(header json, payload json, valid boolean)
    LANGUAGE sql
    AS $$
  SELECT
    convert_from(pgjwt.url_decode(r[1]), 'utf8')::json AS header,
    convert_from(pgjwt.url_decode(r[2]), 'utf8')::json AS payload,
    r[3] = pgjwt.algorithm_sign(r[1] || '.' || r[2], secret, algorithm) AS valid
  FROM regexp_split_to_array(token, '\.') r;
$$;



--
-- Name: cookie(text); Type: FUNCTION; Schema: request; Owner: superuser
--

CREATE FUNCTION request.cookie(c text) RETURNS text
    LANGUAGE sql STABLE
    AS $$
    select current_setting('request.cookie.' || c, true);
$$;



--
-- Name: env_var(text); Type: FUNCTION; Schema: request; Owner: superuser
--

CREATE FUNCTION request.env_var(v text) RETURNS text
    LANGUAGE sql STABLE
    AS $$
    select current_setting(v, true);
$$;



--
-- Name: header(text); Type: FUNCTION; Schema: request; Owner: superuser
--

CREATE FUNCTION request.header(h text) RETURNS text
    LANGUAGE sql STABLE
    AS $$
    select current_setting('request.header.' || h, true);
$$;



--
-- Name: jwt_claim(text); Type: FUNCTION; Schema: request; Owner: superuser
--

CREATE FUNCTION request.jwt_claim(c text) RETURNS text
    LANGUAGE sql STABLE
    AS $$
    select current_setting('request.jwt.claim.' || c, true);
$$;



--
-- Name: user_role(); Type: FUNCTION; Schema: request; Owner: superuser
--

CREATE FUNCTION request.user_role() RETURNS text
    LANGUAGE sql STABLE
    AS $$
    select current_setting('request.jwt.claim.role', true)::text;
$$;



--
-- Name: validate(boolean, text, text, text, text); Type: FUNCTION; Schema: request; Owner: superuser
--

CREATE FUNCTION request.validate(valid boolean, err text, details text DEFAULT ''::text, hint text DEFAULT ''::text, errcode text DEFAULT 'P0001'::text) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
begin
   if valid then
      return true;
   else
      RAISE EXCEPTION '%', err USING
      DETAIL = details, 
      HINT = hint, 
      ERRCODE = errcode;
   end if;
end
$$;



--
-- Name: delete_cookie(text); Type: FUNCTION; Schema: response; Owner: superuser
--

CREATE FUNCTION response.delete_cookie(name text) RETURNS void
    LANGUAGE sql STABLE
    AS $$
    select response.set_header('Set-Cookie', response.get_cookie_string(name, 'deleted', 0 ,'/'));
$$;



--
-- Name: get_cookie_string(text, text, integer, text); Type: FUNCTION; Schema: response; Owner: superuser
--

CREATE FUNCTION response.get_cookie_string(name text, value text, expires_after integer, path text) RETURNS text
    LANGUAGE sql STABLE
    AS $$
    with vars as (
        select
            case
                when expires_after > 0 
                then current_timestamp + (expires_after::text||' seconds')::interval
                else timestamp 'epoch'
            end as expires_on
    )
    select 
        name ||'=' || value || '; ' ||
        'Expires=' || to_char(expires_on, 'Dy, DD Mon YYYY HH24:MI:SS GMT') || '; ' ||
        'Max-Age=' || expires_after::text || '; ' ||
        'Path=' ||path|| '; HttpOnly'
    from vars;
$$;



--
-- Name: set_cookie(text, text, integer, text); Type: FUNCTION; Schema: response; Owner: superuser
--

CREATE FUNCTION response.set_cookie(name text, value text, expires_after integer, path text) RETURNS void
    LANGUAGE sql STABLE
    AS $$
    select response.set_header('Set-Cookie', response.get_cookie_string(name, value, expires_after, path));
$$;



--
-- Name: set_header(text, text); Type: FUNCTION; Schema: response; Owner: superuser
--

CREATE FUNCTION response.set_header(name text, value text) RETURNS void
    LANGUAGE sql STABLE
    AS $$
    select set_config(
        'response.headers', 
        jsonb_insert(
            (case coalesce(current_setting('response.headers',true),'')
            when '' then '[]'
            else current_setting('response.headers')
            end)::jsonb,
            '{0}'::text[], 
            jsonb_build_object(name, value))::text, 
        true
    );
$$;



--
-- Name: get(text); Type: FUNCTION; Schema: settings; Owner: superuser
--

CREATE FUNCTION settings.get(text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $_$
    select value from settings.secrets where key = $1
$_$;



--
-- Name: set(text, text); Type: FUNCTION; Schema: settings; Owner: superuser
--

CREATE FUNCTION settings.set(text, text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    AS $_$
	insert into settings.secrets (key, value)
	values ($1, $2)
	on conflict (key) do update
	set value = $2;
$_$;



--
-- Name: todo_id_seq; Type: SEQUENCE; Schema: data; Owner: superuser
--

CREATE SEQUENCE data.todo_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: todo_id_seq; Type: SEQUENCE OWNED BY; Schema: data; Owner: superuser
--

ALTER SEQUENCE data.todo_id_seq OWNED BY data.todo.id;


--
-- Name: user; Type: TABLE; Schema: data; Owner: superuser
--

CREATE TABLE data."user" (
    id integer NOT NULL,
    name text NOT NULL,
    email text NOT NULL,
    password text NOT NULL,
    role data.user_role DEFAULT 'webuser'::data.user_role NOT NULL,
    CONSTRAINT user_email_check CHECK ((email ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$'::text)),
    CONSTRAINT user_name_check CHECK ((length(name) > 2))
);



--
-- Name: user_id_seq; Type: SEQUENCE; Schema: data; Owner: superuser
--

CREATE SEQUENCE data.user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: user_id_seq; Type: SEQUENCE OWNED BY; Schema: data; Owner: superuser
--

ALTER SEQUENCE data.user_id_seq OWNED BY data."user".id;


--
-- Name: secrets; Type: TABLE; Schema: settings; Owner: superuser
--

CREATE TABLE settings.secrets (
    key text NOT NULL,
    value text NOT NULL
);



--
-- Name: todo id; Type: DEFAULT; Schema: data; Owner: superuser
--

ALTER TABLE ONLY data.todo ALTER COLUMN id SET DEFAULT nextval('data.todo_id_seq'::regclass);


--
-- Name: user id; Type: DEFAULT; Schema: data; Owner: superuser
--

ALTER TABLE ONLY data."user" ALTER COLUMN id SET DEFAULT nextval('data.user_id_seq'::regclass);


--
-- Name: todo todo_pkey; Type: CONSTRAINT; Schema: data; Owner: superuser
--

ALTER TABLE ONLY data.todo
    ADD CONSTRAINT todo_pkey PRIMARY KEY (id);


--
-- Name: user user_email_key; Type: CONSTRAINT; Schema: data; Owner: superuser
--

ALTER TABLE ONLY data."user"
    ADD CONSTRAINT user_email_key UNIQUE (email);


--
-- Name: user user_pkey; Type: CONSTRAINT; Schema: data; Owner: superuser
--

ALTER TABLE ONLY data."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (id);


--
-- Name: secrets secrets_pkey; Type: CONSTRAINT; Schema: settings; Owner: superuser
--

ALTER TABLE ONLY settings.secrets
    ADD CONSTRAINT secrets_pkey PRIMARY KEY (key);


--
-- Name: user user_encrypt_pass_trigger; Type: TRIGGER; Schema: data; Owner: superuser
--

CREATE TRIGGER user_encrypt_pass_trigger BEFORE INSERT OR UPDATE ON data."user" FOR EACH ROW EXECUTE FUNCTION data.encrypt_pass();


--
-- Name: todo todo_owner_id_fkey; Type: FK CONSTRAINT; Schema: data; Owner: superuser
--

ALTER TABLE ONLY data.todo
    ADD CONSTRAINT todo_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES data."user"(id);


--
-- Name: todo; Type: ROW SECURITY; Schema: data; Owner: superuser
--

ALTER TABLE data.todo ENABLE ROW LEVEL SECURITY;

--
-- Name: todo todo_access_policy; Type: POLICY; Schema: data; Owner: superuser
--

CREATE POLICY todo_access_policy ON data.todo TO api USING ((((request.user_role() = 'webuser'::text) AND (request.user_id() = owner_id)) OR (private = false))) WITH CHECK (((request.user_role() = 'webuser'::text) AND (request.user_id() = owner_id)));


--
-- PostgreSQL database dump complete
--


\ir 20210223104353-initial.0.end
COMMIT;