-- generated with subzero-cli (https://github.com/subzerocloud/subzero-cli)
BEGIN;


create sequence "data"."comment_id_seq";

create table "data"."comment" (
    "id" integer not null default nextval('data.comment_id_seq'::regclass),
    "body" text not null,
    "todo_id" integer not null,
    "user_id" integer default request.user_id()
);


alter table "data"."comment" enable row level security;

alter sequence "data"."comment_id_seq" owned by "data"."comment"."id";

CREATE UNIQUE INDEX comment_pkey ON data.comment USING btree (id);

alter table "data"."comment" add constraint "comment_pkey" PRIMARY KEY using index "comment_pkey";

alter table "data"."comment" add constraint "comment_todo_id_fkey" FOREIGN KEY (todo_id) REFERENCES data.todo(id);

alter table "data"."comment" add constraint "comment_user_id_fkey" FOREIGN KEY (user_id) REFERENCES data."user"(id);

create or replace view "api"."comments" as  SELECT comment.id,
    comment.body,
    comment.todo_id,
    comment.user_id
   FROM data.comment;


create policy "comment_access_policy"
on "data"."comment"
as permissive
for all
to api
using ((request.user_role() = 'webuser'::text))
with check ((request.user_role() = 'webuser'::text) AND (request.user_id() = user_id));




\ir 20210223141125-comments_model_and_endpoint.0.end
COMMIT;