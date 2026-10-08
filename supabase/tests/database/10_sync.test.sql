-- Phase 1 tables, sync_push and sync_pull (docs/12-architecture.md §6,
-- docs/13-data-model.md §2–§6): owners only, events never change, state
-- rows are last-writer-wins, and a pull pages through the learner's rows.
begin;
create extension if not exists pgtap with schema extensions;
select plan(60);

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
select table_privs_are('public', 'devices', 'authenticated',
  array['SELECT', 'INSERT', 'UPDATE'], 'devices: read, add and update own rows');
select table_privs_are('public', 'personal_items', 'authenticated',
  array['SELECT', 'INSERT', 'UPDATE'], 'personal_items: read, add and update own rows');
select table_privs_are('public', 'cards', 'authenticated',
  array['SELECT', 'INSERT', 'UPDATE'], 'cards: read, add and update own rows');
select table_privs_are('public', 'gap_entries', 'authenticated',
  array['SELECT', 'INSERT', 'UPDATE'], 'gap_entries: read, add and update own rows');
select table_privs_are('public', 'recordings', 'authenticated',
  array['SELECT', 'INSERT', 'UPDATE'], 'recordings: read, add and update own rows');
select table_privs_are('public', 'attempts', 'authenticated',
  array['SELECT', 'INSERT'], 'attempts: an event, read and add only');
select table_privs_are('public', 'attempt_amendments', 'authenticated',
  array['SELECT', 'INSERT'], 'attempt_amendments: an event, read and add only');
select table_privs_are('public', 'assessments', 'authenticated',
  array['SELECT', 'INSERT'], 'assessments: an event, read and add only');
select table_privs_are('public', 'sessions', 'authenticated',
  array['SELECT', 'INSERT'], 'sessions: an event, read and add only');
select table_privs_are('public', 'content_reports', 'authenticated',
  array['SELECT', 'INSERT'], 'content_reports: read and add only');
select is(
  (
    select count(*)::int
    from unnest(array['devices', 'personal_items', 'cards', 'attempts',
                      'attempt_amendments', 'gap_entries', 'recordings',
                      'assessments', 'sessions', 'content_reports']) t,
         unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) p
    where not has_table_privilege('service_role', 'public.' || t, p)
  ),
  0,
  'the service role reads and writes the new tables'
);
select ok(
  not has_function_privilege('anon', 'public.sync_push(uuid, jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.sync_pull(bigint, int)', 'execute'),
  'anon cannot call the sync functions'
);
select ok(
  has_function_privilege('authenticated', 'public.sync_push(uuid, jsonb)', 'execute')
    and has_function_privilege('authenticated', 'public.sync_pull(bigint, int)', 'execute'),
  'signed-in users call the sync functions'
);

-- ---------------------------------------------------------------------------
-- Two learners, one course each
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'a@dilbaz.test'),
  ('22222222-2222-4222-8222-222222222222', 'b@dilbaz.test');
insert into public.profiles (id, display_name, updated_at) values
  ('11111111-1111-4111-8111-111111111111', 'A', '2026-09-01T00:00:00Z'),
  ('22222222-2222-4222-8222-222222222222', 'B', '2026-09-01T00:00:00Z');
insert into public.courses (id, profile_id, l2, pair_pack) values
  ('a1111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'en', 'tr-en'),
  ('b2222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-222222222222', 'en', 'tr-en');
insert into public.cards (id, profile_id, course_id, item_ref, mode, fsrs_card_id, state, due)
values ('0192f5a0-0000-7000-8000-00000000bc01', '22222222-2222-4222-8222-222222222222',
        'b2222222-2222-4222-8222-222222222222', 'zz.word.bada', 'speak', 1, 1,
        '2026-10-02T09:00:00Z');
insert into public.personal_items (id, profile_id, course_id, kind, text_l2, source)
values ('0192f5a0-0000-7000-8000-00000000b101', '22222222-2222-4222-8222-222222222222',
        'b2222222-2222-4222-8222-222222222222', 'sentence', 'Bada kolu.', 'gap');
insert into storage.objects (bucket_id, name)
values ('audio-private', '22222222-2222-4222-8222-222222222222/2026/10/b.m4a');

-- Signed in as A.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);

-- ---------------------------------------------------------------------------
-- sync_push
-- ---------------------------------------------------------------------------
select set_config('t.batch', $${
  "device": {"platform": "android", "app_version": "0.1.0"},
  "attempts": [
    {"id": "0192f5a0-0000-7000-8000-000000000a01",
     "profile_id": "22222222-2222-4222-8222-222222222222",
     "course_id": "a1111111-1111-4111-8111-111111111111",
     "device_id": "d1111111-1111-4111-8111-111111111111",
     "activity": "card.produce_speak", "item_ref": "zz.word.bada",
     "card_id": "0192f5a0-0000-7000-8000-000000000c01",
     "prompt": {"prompt_l1": "Bada de."}, "response": {"text": "bada", "source": "typed"},
     "verdict": "correct", "target_ok": true, "error_tags": ["zz.form"],
     "hints_used": 0, "hint_max_level": 0, "rating": 3, "latency_ms": 1200,
     "card_state_after": {"state": 2},
     "created_at_client": "2026-10-01T09:00:00Z", "created_at": "2026-10-01T09:00:01Z"},
    {"id": "0192f5a0-0000-7000-8000-000000000a02",
     "course_id": "b2222222-2222-4222-8222-222222222222",
     "device_id": "d1111111-1111-4111-8111-111111111111",
     "activity": "card.produce_type", "prompt": {}, "response": {},
     "created_at_client": "2026-10-01T09:00:00Z"}
  ],
  "attempt_amendments": [
    {"id": "0192f5a0-0000-7000-8000-000000000e01",
     "attempt_id": "0192f5a0-0000-7000-8000-000000000a01",
     "kind": "user_dispute", "payload": {"answer": "bada"}},
    {"id": "0192f5a0-0000-7000-8000-000000000e02",
     "attempt_id": "0192f5a0-0000-7000-8000-000000000a99",
     "kind": "llm_resolved", "payload": {}}
  ],
  "sessions": [
    {"id": "0192f5a0-0000-7000-8000-000000000501",
     "course_id": "a1111111-1111-4111-8111-111111111111",
     "device_id": "d1111111-1111-4111-8111-111111111111",
     "started_at": "2026-10-01T08:50:00Z", "ended_at": "2026-10-01T09:05:00Z",
     "active_ms": 600000, "strand_ms": {"language": 600000}}
  ],
  "assessments": [
    {"id": "0192f5a0-0000-7000-8000-000000000b01",
     "course_id": "a1111111-1111-4111-8111-111111111111",
     "kind": "placement", "results": {"version": 1}}
  ],
  "content_reports": [
    {"id": "0192f5a0-0000-7000-8000-000000000f01", "item_ref": "zz.word.bada",
     "reason": "meaning", "status": "fixed", "context": {"carrier": "zz.sent.1"}}
  ],
  "cards": [
    {"id": "0192f5a0-0000-7000-8000-000000000c01",
     "course_id": "a1111111-1111-4111-8111-111111111111",
     "item_ref": "zz.word.bada", "mode": "speak", "fsrs_card_id": 1, "state": 2,
     "stability": 3.2, "difficulty": 5.1, "due": "2026-10-04T09:00:00Z",
     "last_review": "2026-10-01T09:00:00Z", "reps": 1, "lapses": 0,
     "suspended": false, "updated_at": "2026-10-01T09:00:00Z"}
  ],
  "personal_items": [
    {"id": "0192f5a0-0000-7000-8000-000000000101",
     "course_id": "a1111111-1111-4111-8111-111111111111",
     "kind": "sentence", "text_l2": "Bada kolu.", "lemmas": ["bada"],
     "source": "task_correction", "updated_at": "2026-10-01T09:00:00Z"}
  ],
  "gap_entries": [
    {"id": "0192f5a0-0000-7000-8000-000000000201",
     "course_id": "a1111111-1111-4111-8111-111111111111",
     "l1_text": "Bunu nasıl derim?", "context": "daily", "status": "new",
     "personal_item_ids": [], "updated_at": "2026-10-01T09:00:00Z"}
  ],
  "recordings": [
    {"id": "0192f5a0-0000-7000-8000-000000000301",
     "course_id": "a1111111-1111-4111-8111-111111111111",
     "task_ref": "zz.task.home", "duration_ms": 70000, "outcome": "done",
     "audio_path": "11111111-1111-4111-8111-111111111111/2026/10/0192f5a0-0000-7000-8000-000000000301.m4a",
     "updated_at": "2026-10-01T09:00:00Z"}
  ]
}$$, true);

select set_config('t.first', public.sync_push(
  'd1111111-1111-4111-8111-111111111111', current_setting('t.batch')::jsonb)::text, true);

select is(
  (current_setting('t.first')::jsonb ->> 'accepted')::int,
  9,
  'a push stores every row the learner may write'
);
select results_eq(
  $$select c ->> 'table', c ->> 'id', c ->> 'reason'
    from jsonb_array_elements(current_setting('t.first')::jsonb -> 'conflicts') c
    order by 1$$,
  $$values
    ('attempt_amendments', '0192f5a0-0000-7000-8000-000000000e02', 'unknown_attempt'),
    ('attempts', '0192f5a0-0000-7000-8000-000000000a02', 'unknown_course')$$,
  'rows of another course and amendments without their attempt come back as conflicts'
);
select results_eq(
  $$select profile_id::text, created_at from public.attempts$$,
  $$values ('11111111-1111-4111-8111-111111111111', '2026-10-01T09:00:01Z'::timestamptz)$$,
  'a pushed row belongs to the caller and keeps the time it was made'
);
select is(
  (select status from public.content_reports),
  'open',
  'a report always starts open'
);
select results_eq(
  $$select platform, app_version, last_sync_at is not null from public.devices$$,
  $$values ('android', '0.1.0', true)$$,
  'the device is registered with its last sync'
);

-- The same batch again: an event is stored once.
select lives_ok(
  $$select public.sync_push('d1111111-1111-4111-8111-111111111111',
      current_setting('t.batch')::jsonb)$$,
  'a batch can be pushed again'
);
select results_eq(
  $$select (select count(*) from public.attempts)::int,
           (select count(*) from public.attempt_amendments)::int,
           (select count(*) from public.sessions)::int,
           (select count(*) from public.assessments)::int,
           (select count(*) from public.content_reports)::int$$,
  $$values (1, 1, 1, 1, 1)$$,
  'pushing again adds no event (idempotent)'
);

-- Cards: the later review wins.
select set_config('t.card_seq', (select server_seq from public.cards
  where id = '0192f5a0-0000-7000-8000-000000000c01')::text, true);
select set_config('t.stale', public.sync_push('d1111111-1111-4111-8111-111111111111', $${
  "cards": [
    {"id": "0192f5a0-0000-7000-8000-000000000c01",
     "course_id": "a1111111-1111-4111-8111-111111111111",
     "item_ref": "zz.word.bada", "mode": "speak", "fsrs_card_id": 1, "state": 2,
     "due": "2026-10-03T09:00:00Z", "last_review": "2026-09-30T09:00:00Z",
     "reps": 9, "updated_at": "2026-10-05T09:00:00Z"}
  ]}$$)::text, true);
select is(
  current_setting('t.stale')::jsonb -> 'conflicts',
  '[{"id": "0192f5a0-0000-7000-8000-000000000c01", "table": "cards", "reason": "stale"}]'::jsonb,
  'an earlier review of a card comes back as stale'
);
select is(
  (select reps from public.cards where id = '0192f5a0-0000-7000-8000-000000000c01'),
  1,
  'a stale card does not overwrite the later review'
);
select lives_ok($q$select public.sync_push('d1111111-1111-4111-8111-111111111111', $${
  "cards": [
    {"id": "0192f5a0-0000-7000-8000-000000000c01",
     "course_id": "a1111111-1111-4111-8111-111111111111",
     "item_ref": "zz.word.bada", "mode": "speak", "fsrs_card_id": 1, "state": 2,
     "due": "2026-10-09T09:00:00Z", "last_review": "2026-10-02T09:00:00Z",
     "reps": 2, "updated_at": "2026-10-02T09:00:00Z"}
  ]}$$)$q$, 'a later review is pushed');
select results_eq(
  $$select reps, server_seq > current_setting('t.card_seq')::bigint
    from public.cards where id = '0192f5a0-0000-7000-8000-000000000c01'$$,
  $$values (2, true)$$,
  'a later review replaces the card and takes a new sequence number'
);
select set_config('t.duplicate', public.sync_push('d1111111-1111-4111-8111-111111111111', $${
  "cards": [
    {"id": "0192f5a0-0000-7000-8000-000000000c02",
     "course_id": "a1111111-1111-4111-8111-111111111111",
     "item_ref": "zz.word.bada", "mode": "speak", "fsrs_card_id": 7, "state": 1,
     "due": "2026-10-03T09:00:00Z", "last_review": "2026-10-03T09:00:00Z"}
  ]}$$)::text, true);
select is(
  current_setting('t.duplicate')::jsonb -> 'conflicts',
  '[{"id": "0192f5a0-0000-7000-8000-000000000c02", "table": "cards", "reason": "duplicate"}]'::jsonb,
  'a second card of the same item and mode comes back as a duplicate'
);
select is(
  (select count(*)::int from public.cards where item_ref = 'zz.word.bada'),
  1,
  'the duplicate card is not stored'
);

-- Other state rows: the later change wins.
select lives_ok($q$select public.sync_push('d1111111-1111-4111-8111-111111111111', $${
  "personal_items": [
    {"id": "0192f5a0-0000-7000-8000-000000000101",
     "course_id": "a1111111-1111-4111-8111-111111111111",
     "kind": "sentence", "text_l2": "Older.", "source": "task_correction",
     "updated_at": "2026-09-30T09:00:00Z"}
  ]}$$)$q$, 'an earlier change of a personal item is pushed');
select is(
  (select text_l2 from public.personal_items where id = '0192f5a0-0000-7000-8000-000000000101'),
  'Bada kolu.',
  'an earlier change does not overwrite a later one'
);
select lives_ok($q$select public.sync_push('d1111111-1111-4111-8111-111111111111', $${
  "personal_items": [
    {"id": "0192f5a0-0000-7000-8000-000000000101",
     "course_id": "a1111111-1111-4111-8111-111111111111",
     "kind": "sentence", "text_l2": "Bada kolu!", "source": "task_correction",
     "deprecated": true, "updated_at": "2026-10-02T09:00:00Z"}
  ]}$$)$q$, 'a later change of a personal item is pushed');
select results_eq(
  $$select text_l2, deprecated from public.personal_items
    where id = '0192f5a0-0000-7000-8000-000000000101'$$,
  $$values ('Bada kolu!', true)$$,
  'a later change replaces the row'
);

-- The profile and courses.
select lives_ok($q$select public.sync_push('d1111111-1111-4111-8111-111111111111', $${
  "profiles": [
    {"id": "11111111-1111-4111-8111-111111111111", "display_name": "A2",
     "time_budget_min": 20, "settings": {"silent_mode": true},
     "updated_at": "2026-10-02T09:00:00Z"},
    {"id": "22222222-2222-4222-8222-222222222222", "display_name": "hacked",
     "updated_at": "2030-01-01T00:00:00Z"}
  ]}$$)$q$, 'a profile change is pushed');
select results_eq(
  $$select display_name, time_budget_min, settings from public.profiles$$,
  $$values ('A2', 20, '{"silent_mode": true}'::jsonb)$$,
  'the later profile replaces the stored one'
);
select lives_ok($q$select public.sync_push('d1111111-1111-4111-8111-111111111111', $${
  "profiles": [
    {"id": "11111111-1111-4111-8111-111111111111", "display_name": "A0",
     "updated_at": "2026-09-15T09:00:00Z"}
  ]}$$)$q$, 'an earlier profile is pushed');
select is(
  (select display_name from public.profiles),
  'A2',
  'an earlier profile does not overwrite a later one'
);
select set_config('t.courses', public.sync_push('d1111111-1111-4111-8111-111111111111', $${
  "courses": [
    {"id": "a1111111-1111-4111-8111-1111111111de", "l2": "de", "pair_pack": "tr-de",
     "updated_at": "2026-10-02T09:00:00Z", "created_at": "2026-10-02T09:00:00Z"},
    {"id": "a1111111-1111-4111-8111-1111111111ee", "l2": "en", "pair_pack": "tr-en"}
  ],
  "sessions": [
    {"id": "0192f5a0-0000-7000-8000-000000000502",
     "course_id": "a1111111-1111-4111-8111-1111111111de",
     "device_id": "d1111111-1111-4111-8111-111111111111",
     "started_at": "2026-10-02T09:00:00Z"}
  ]}$$)::text, true);
select is(
  current_setting('t.courses')::jsonb,
  '{"accepted": 2, "conflicts": [{"id": "a1111111-1111-4111-8111-1111111111ee", "table": "courses", "reason": "duplicate"}]}'::jsonb,
  'a new course and its rows go in together; a second course of a language does not'
);
select results_eq(
  $$select l2 from public.courses order by l2$$,
  $$values ('de'), ('en')$$,
  'the learner has one course per language'
);

-- Limits and identity.
select throws_ok(
  $$select public.sync_push('d1111111-1111-4111-8111-111111111111',
      jsonb_build_object('attempts',
        (select jsonb_agg(jsonb_build_object('id', gen_random_uuid()))
         from generate_series(1, 501))))$$,
  '54000', 'batch_too_large',
  'a batch holds at most 500 rows'
);

-- ---------------------------------------------------------------------------
-- sync_pull
-- ---------------------------------------------------------------------------
select set_config('t.pull', public.sync_pull(0)::text, true);
select is(
  (
    select count(*)::int
    from jsonb_each(current_setting('t.pull')::jsonb -> 'rows') t,
         jsonb_array_elements(t.value) x
    where coalesce(x ->> 'profile_id', x ->> 'id') <> '11111111-1111-4111-8111-111111111111'
  ),
  0,
  'a pull returns the learner''s own rows only'
);
select is(
  (select array_agg(t order by t)
   from jsonb_object_keys(current_setting('t.pull')::jsonb -> 'rows') t),
  array['assessments', 'attempt_amendments', 'attempts', 'cards', 'content_reports',
        'courses', 'gap_entries', 'personal_items', 'profiles', 'recordings', 'sessions'],
  'a pull covers every synced table'
);
select is(
  current_setting('t.pull')::jsonb -> 'more',
  'false'::jsonb,
  'one page holds everything here'
);
select is(
  (current_setting('t.pull')::jsonb -> 'rows' -> 'cards' -> 0 ->> 'reps')::int,
  2,
  'a pull returns the latest state of a row'
);
select set_config('t.page', public.sync_pull(0, 2)::text, true);
select results_eq(
  $$select (select sum(jsonb_array_length(value))::int
            from jsonb_each(current_setting('t.page')::jsonb -> 'rows')),
           current_setting('t.page')::jsonb -> 'more'$$,
  $$values (2, 'true'::jsonb)$$,
  'a page holds at most the limit and says there is more'
);
select is(
  (
    select sum(jsonb_array_length(value))::int
    from jsonb_each(public.sync_pull(
      (current_setting('t.page')::jsonb ->> 'next')::bigint) -> 'rows')
  ),
  (
    select sum(jsonb_array_length(value))::int - 2
    from jsonb_each(current_setting('t.pull')::jsonb -> 'rows')
  ),
  'the next page starts after the cursor'
);
select is(
  public.sync_pull((current_setting('t.pull')::jsonb ->> 'next')::bigint),
  jsonb_build_object('rows', '{}'::jsonb,
                     'next', (current_setting('t.pull')::jsonb ->> 'next')::bigint,
                     'more', false),
  'nothing new: the cursor stays'
);
select lives_ok($q$select public.sync_push('d1111111-1111-4111-8111-111111111111', $${
  "gap_entries": [
    {"id": "0192f5a0-0000-7000-8000-000000000201",
     "course_id": "a1111111-1111-4111-8111-111111111111",
     "l1_text": "Bunu nasıl derim?", "context": "daily", "status": "dismissed",
     "updated_at": "2026-10-03T09:00:00Z"}
  ]}$$)$q$, 'a capture changes after the pull');
select is(
  public.sync_pull((current_setting('t.pull')::jsonb ->> 'next')::bigint)
    -> 'rows' -> 'gap_entries' -> 0 ->> 'status',
  'dismissed',
  'a changed row comes back in the next pull'
);

-- ---------------------------------------------------------------------------
-- Row level security on the tables themselves
-- ---------------------------------------------------------------------------
select throws_ok(
  $$update public.attempts set verdict = 'wrong'$$,
  '42501', null,
  'an attempt cannot be changed (I-03)'
);
select throws_ok(
  $$delete from public.cards$$,
  '42501', null,
  'a card cannot be deleted through the Data API'
);
select throws_ok(
  $$insert into public.cards (id, profile_id, course_id, item_ref, mode, fsrs_card_id, state, due)
    values ('0192f5a0-0000-7000-8000-00000000bc02', '22222222-2222-4222-8222-222222222222',
            'b2222222-2222-4222-8222-222222222222', 'zz.word.kolu', 'speak', 2, 1, now())$$,
  '42501', null,
  'a card cannot be written for someone else'
);
select is(
  (select count(*)::int from public.cards
   where profile_id = '22222222-2222-4222-8222-222222222222'),
  0,
  'another learner''s cards cannot be read'
);
update public.personal_items set text_l2 = 'hacked'
where id = '0192f5a0-0000-7000-8000-00000000b101';
select throws_ok(
  $$insert into public.content_reports (id, profile_id, item_ref, reason, status)
    values ('0192f5a0-0000-7000-8000-000000000f02', '11111111-1111-4111-8111-111111111111',
            'zz.word.bada', 'other', 'fixed')$$,
  '42501', null,
  'a learner cannot close a report'
);

-- The private audio bucket.
select lives_ok(
  $$insert into storage.objects (bucket_id, name)
    values ('audio-private', '11111111-1111-4111-8111-111111111111/2026/10/a.m4a')$$,
  'a learner uploads audio into their own folder'
);
select throws_ok(
  $$insert into storage.objects (bucket_id, name)
    values ('audio-private', '22222222-2222-4222-8222-222222222222/2026/10/x.m4a')$$,
  '42501', null,
  'a learner cannot upload into someone else''s folder'
);
select is(
  (select array_agg(name) from storage.objects where bucket_id = 'audio-private'),
  array['11111111-1111-4111-8111-111111111111/2026/10/a.m4a'],
  'a learner sees their own audio only'
);

-- Signed in without a user.
select set_config('request.jwt.claims', '{"role": "authenticated"}', true);
select throws_ok(
  $$select public.sync_push('d1111111-1111-4111-8111-111111111111', '{}'::jsonb)$$,
  '42501', 'not signed in',
  'a push needs a signed-in user'
);
select throws_ok(
  $$select public.sync_pull(0)$$,
  '42501', 'not signed in',
  'a pull needs a signed-in user'
);

-- Signed in as B: A's rows stay A's.
select set_config('request.jwt.claims',
  '{"sub": "22222222-2222-4222-8222-222222222222", "role": "authenticated"}', true);
select is(
  (
    select count(*)::int
    from jsonb_each(public.sync_pull(0) -> 'rows') t,
         jsonb_array_elements(t.value) x
    where coalesce(x ->> 'profile_id', x ->> 'id') <> '22222222-2222-4222-8222-222222222222'
  ),
  0,
  'another learner pulls nothing of A'
);

-- Checked with full privileges.
reset role;
select results_eq(
  $$select display_name from public.profiles
    where id = '22222222-2222-4222-8222-222222222222'$$,
  $$values ('B')$$,
  'a push cannot change another learner''s profile'
);
select is(
  (select text_l2 from public.personal_items where id = '0192f5a0-0000-7000-8000-00000000b101'),
  'Bada kolu.',
  'another learner''s personal item cannot be updated'
);
select results_eq(
  $$select id, public, file_size_limit from storage.buckets where id = 'audio-private'$$,
  $$values ('audio-private'::text, false, 10485760::bigint)$$,
  'the audio bucket is private and limited to 10 MB a file'
);

select * from finish();
rollback;
