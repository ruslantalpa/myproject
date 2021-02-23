-- generated with subzero-cli (https://github.com/subzerocloud/subzero-cli)
BEGIN;


drop policy "comment_access_policy" on "data"."comment";

alter table "data"."comment" drop constraint "comment_todo_id_fkey";

alter table "data"."comment" drop constraint "comment_user_id_fkey";

drop view if exists "api"."comments";

alter table "data"."comment" drop constraint "comment_pkey";

drop index if exists "data"."comment_pkey";

drop table "data"."comment";

drop sequence if exists "data"."comment_id_seq";




COMMIT;