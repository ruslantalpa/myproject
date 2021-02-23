-- generated with subzero-cli (https://github.com/subzerocloud/subzero-cli)
BEGIN;


drop trigger if exists "user_encrypt_pass_trigger" on "data"."user";

drop policy "todo_access_policy" on "data"."todo";

alter table "data"."todo" drop constraint "todo_owner_id_fkey";

alter table "data"."user" drop constraint "user_email_check";

alter table "data"."user" drop constraint "user_email_key";

alter table "data"."user" drop constraint "user_name_check";

drop function if exists "api"."login"(email text, password text);

drop function if exists "api"."logout"();

drop function if exists "api"."me"();

drop function if exists "api"."on_oauth_login"(provider text, profile json);

drop function if exists "api"."refresh_token"();

drop function if exists "api"."search_items"(query text);

drop function if exists "api"."signup"(name text, email text, password text);

drop view if exists "api"."todos";

drop function if exists "data"."encrypt_pass"();

drop function if exists "pgjwt"."algorithm_sign"(signables text, secret text, algorithm text);

drop function if exists "pgjwt"."sign"(payload json, secret text, algorithm text);

drop function if exists "pgjwt"."url_decode"(data text);

drop function if exists "pgjwt"."url_encode"(data bytea);

drop function if exists "pgjwt"."verify"(token text, secret text, algorithm text);

drop function if exists "request"."cookie"(c text);

drop function if exists "request"."env_var"(v text);

drop function if exists "request"."header"(h text);

drop function if exists "request"."jwt_claim"(c text);

drop function if exists "request"."user_id"();

drop function if exists "request"."user_role"();

drop function if exists "request"."validate"(valid boolean, err text, details text, hint text, errcode text);

drop function if exists "response"."delete_cookie"(name text);

drop function if exists "response"."get_cookie_string"(name text, value text, expires_after integer, path text);

drop function if exists "response"."set_cookie"(name text, value text, expires_after integer, path text);

drop function if exists "response"."set_header"(name text, value text);

drop function if exists "settings"."get"(text);

drop function if exists "settings"."set"(text, text);

alter table "data"."todo" drop constraint "todo_pkey";

alter table "data"."user" drop constraint "user_pkey";

alter table "settings"."secrets" drop constraint "secrets_pkey";

drop index if exists "data"."todo_pkey";

drop index if exists "data"."user_email_key";

drop index if exists "data"."user_pkey";

drop index if exists "settings"."secrets_pkey";

drop table "data"."todo";

drop table "data"."user";

drop table "settings"."secrets";

drop sequence if exists "data"."todo_id_seq";

drop sequence if exists "data"."user_id_seq";

drop type "data"."user_role";

drop extension if exists "pgcrypto";

drop schema if exists "api";

drop schema if exists "data";

drop schema if exists "pgjwt";

drop schema if exists "request";

drop schema if exists "response";

drop schema if exists "settings";




COMMIT;