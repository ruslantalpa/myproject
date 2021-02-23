create or replace view comments as
select id, body, todo_id, user_id
from data.comment;
