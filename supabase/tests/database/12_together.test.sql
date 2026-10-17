-- Together (F2-07): invitations between partners and presence on the
-- team's channel; nobody outside the team sees or joins either (I-18).
begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'a@dilbaz.test'),
  ('22222222-2222-4222-8222-222222222222', 'b@dilbaz.test'),
  ('33333333-3333-4333-8333-333333333333', 'c@dilbaz.test');
insert into public.profiles (id, display_name) values
  ('11111111-1111-4111-8111-111111111111', 'A'),
  ('22222222-2222-4222-8222-222222222222', 'B'),
  ('33333333-3333-4333-8333-333333333333', 'C');
insert into public.teams (id, name, invite_code, created_by) values
  ('70000000-0000-4000-8000-000000000001', 'Biz', 'KAHVE7',
   '11111111-1111-4111-8111-111111111111'),
  ('70000000-0000-4000-8000-000000000002', 'Onlar', 'CAY123',
   '33333333-3333-4333-8333-333333333333');
insert into public.team_members (team_id, profile_id) values
  ('70000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111'),
  ('70000000-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222'),
  ('70000000-0000-4000-8000-000000000002', '33333333-3333-4333-8333-333333333333');

select table_privs_are('public', 'pair_invites', 'authenticated',
  array['SELECT', 'INSERT'], 'pair_invites: read and send; no table-wide update');
select column_privs_are('public', 'pair_invites', 'state', 'authenticated',
  array['SELECT', 'INSERT', 'UPDATE'], 'the state can be answered');
select column_privs_are('public', 'pair_invites', 'to_profile', 'authenticated',
  array['SELECT', 'INSERT'], 'the addressee cannot be changed');
select table_privs_are('public', 'pair_invites', 'anon', '{}'::text[], 'anon: nothing');
select ok(
  exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'pair_invites'
  ),
  'invitations reach open apps over Realtime'
);

-- A invites B.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);
select lives_ok(
  $$insert into public.pair_invites (id, team_id, from_profile, to_profile, activity, task_ref)
    values ('90000000-0000-4000-8000-000000000001', '70000000-0000-4000-8000-000000000001',
            '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
            'chat', 'en.chat.chat_food')$$,
  'a partner invites the other'
);
select throws_ok(
  $$insert into public.pair_invites (id, team_id, from_profile, to_profile, activity)
    values ('90000000-0000-4000-8000-000000000002', '70000000-0000-4000-8000-000000000001',
            '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333',
            'chat')$$,
  '42501', null,
  'nobody outside the team can be invited'
);
select throws_ok(
  $$insert into public.pair_invites (id, team_id, from_profile, to_profile, activity)
    values ('90000000-0000-4000-8000-000000000003', '70000000-0000-4000-8000-000000000001',
            '22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111',
            'chat')$$,
  '42501', null,
  'an invitation cannot be sent in the partner''s name'
);
select throws_ok(
  $$insert into public.pair_invites (id, team_id, from_profile, to_profile, activity, state)
    values ('90000000-0000-4000-8000-000000000004', '70000000-0000-4000-8000-000000000001',
            '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
            'chat', 'accepted')$$,
  '42501', null,
  'an invitation is sent open, not already answered'
);
select throws_ok(
  $$update public.pair_invites set state = 'accepted'
    where id = '90000000-0000-4000-8000-000000000001'$$,
  '42501', null,
  'the one who invited cannot accept for the partner'
);

-- B sees and answers it.
select set_config('request.jwt.claims',
  '{"sub": "22222222-2222-4222-8222-222222222222", "role": "authenticated"}', true);
select is((select count(*)::int from public.pair_invites), 1, 'the invited partner sees it');
select lives_ok(
  $$update public.pair_invites set state = 'accepted', answered_at = now()
    where id = '90000000-0000-4000-8000-000000000001'$$,
  'the invited partner accepts'
);
select is(
  (select state from public.pair_invites where id = '90000000-0000-4000-8000-000000000001'),
  'accepted',
  'the answer is kept'
);
update public.pair_invites set state = 'declined'
  where id = '90000000-0000-4000-8000-000000000001';
select is(
  (select state from public.pair_invites where id = '90000000-0000-4000-8000-000000000001'),
  'accepted',
  'an answered invitation stays answered'
);

-- C, in another team, sees nothing.
select set_config('request.jwt.claims',
  '{"sub": "33333333-3333-4333-8333-333333333333", "role": "authenticated"}', true);
select is((select count(*)::int from public.pair_invites), 0, 'outsiders do not see invitations');
select is(
  public.my_team() -> 'members',
  '[{"id": "33333333-3333-4333-8333-333333333333", "name": "C"}]'::jsonb,
  'one''s own team only, with its members'' names'
);

select set_config('request.jwt.claims',
  '{"sub": "22222222-2222-4222-8222-222222222222", "role": "authenticated"}', true);
select is(
  (select jsonb_agg(m ->> 'name' order by m ->> 'name')
   from jsonb_array_elements(public.my_team() -> 'members') m),
  '["A", "B"]'::jsonb,
  'partners know each other by name'
);
select is(public.my_team() ->> 'name', 'Biz', 'the team''s name');

-- Presence: only the team's own channel, and only presence.
select set_config('request.jwt.claims',
  '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);
select ok(
  private.may_use_team_topic('team:70000000-0000-4000-8000-000000000001'),
  'a member may use their team''s channel'
);
select ok(
  not private.may_use_team_topic('team:70000000-0000-4000-8000-000000000002'),
  'not another team''s'
);
select ok(
  not private.may_use_team_topic('team:not-a-uuid')
    and not private.may_use_team_topic('pair:70000000-0000-4000-8000-000000000001')
    and not private.may_use_team_topic(null),
  'nor a malformed or other topic'
);

reset role;
select policies_are('realtime', 'messages',
  array['team_presence_listen', 'team_presence_track'],
  'the channel''s only policies are presence on the team''s topic');
select ok(
  (select bool_and(qual like '%presence%' or with_check like '%presence%')
   from pg_policies where schemaname = 'realtime' and tablename = 'messages'),
  'both are for presence alone'
);

select * from finish();
rollback;
