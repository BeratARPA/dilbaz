-- server_seq: the global sync cursor (docs/12-architecture.md §6).
begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

insert into auth.users (id, email)
values ('11111111-1111-4111-8111-111111111111', 'a@dilbaz.test');
insert into public.profiles (id, display_name)
values ('11111111-1111-4111-8111-111111111111', 'A');

select ok(
  (select server_seq from public.profiles) > 0,
  'an insert takes a server_seq from the sequence'
);

create temp table seen as select server_seq as profile_seq from public.profiles;

insert into public.courses (id, profile_id, l2, pair_pack)
values ('a1111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'en', 'tr-en');

select ok(
  (select server_seq from public.courses) > (select profile_seq from seen),
  'the sequence is shared by all synced tables'
);

update public.profiles set display_name = 'A2';

select ok(
  (select server_seq from public.profiles) > (select server_seq from public.courses),
  'an update takes a newer server_seq'
);

update seen set profile_seq = (select server_seq from public.courses);
update public.courses set active = false;

select ok(
  (select server_seq from public.courses) > (select profile_seq from seen),
  'course updates move the cursor too'
);

select matches(
  (
    select pg_get_expr(d.adbin, d.adrelid)
    from pg_attrdef d
    join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = 'public.profiles'::regclass and a.attname = 'server_seq'
  ),
  'nextval\(''(public\.)?sync_seq''',
  'server_seq defaults to the sync sequence'
);

select * from finish();
rollback;
