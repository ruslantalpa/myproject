create table comment (
  id           serial primary key,
  body         text not null,
  todo_id      int not null references todo(id),
  user_id     int references "user"(id) default request.user_id()
);
alter table comment enable row level security;
