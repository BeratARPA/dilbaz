-- Owners read and write their own profile and courses only (docs/13 §4).
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'a@dilbaz.test'),
  ('22222222-2222-4222-8222-222222222222', 'b@dilbaz.test');
insert into public.profiles (id, display_name) values
  ('11111111-1111-4111-8111-111111111111', 'A'),
  ('22222222-2222-4222-8222-222222222222', 'B');
insert into public.courses (id, profile_id, l2, pair_pack) values
  ('a1111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'en', 'tr-en'),
  ('b2222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-222222222222', 'en', 'tr-en');

-- Signed in as A.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);

select results_eq(
  'select display_name from public.profiles',
  $$values ('A')$$,
  'a user sees only their own profile'
);
select results_eq(
  'select id::text from public.courses',
  $$values ('a1111111-1111-4111-8111-111111111111')$$,
  'a user sees only their own courses'
);

update public.profiles set display_name = 'hacked'
where id = '22222222-2222-4222-8222-222222222222';
update public.profiles set time_budget_min = 45
where id = '11111111-1111-4111-8111-111111111111';

select results_eq(
  'select time_budget_min from public.profiles',
  $$values (45)$$,
  'a user updates their own profile'
);

select throws_ok(
  $$insert into public.profiles (id, display_name)
    values ('33333333-3333-4333-8333-333333333333', 'X')$$,
  '42501', null,
  'a user cannot create a profile for someone else'
);
select throws_ok(
  $$insert into public.courses (id, profile_id, l2, pair_pack)
    values ('c3333333-3333-4333-8333-333333333333', '22222222-2222-4222-8222-222222222222', 'de', 'tr-de')$$,
  '42501', null,
  'a user cannot create a course for someone else'
);
select throws_ok(
  $$update public.profiles set time_budget_min = 200
    where id = '11111111-1111-4111-8111-111111111111'$$,
  '23514', null,
  'the time budget stays within 5..120 minutes'
);
select throws_ok(
  $$update public.courses set desired_retention = 0.99$$,
  '23514', null,
  'desired retention stays within 0.80..0.97'
);

-- Anonymous callers get nothing.
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

select throws_ok('select * from public.profiles', '42501', null, 'anon cannot read profiles');
select throws_ok('select * from public.courses', '42501', null, 'anon cannot read courses');

-- Checked with full privileges: B was not touched by A.
reset role;
select results_eq(
  $$select display_name from public.profiles where id = '22222222-2222-4222-8222-222222222222'$$,
  $$values ('B')$$,
  'another user''s profile cannot be updated'
);
select is(
  (select count(*)::int from public.profiles),
  2,
  'no profile was created by the rejected inserts'
);

select * from finish();
rollback;
