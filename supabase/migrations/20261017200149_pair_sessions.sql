-- Information gap sessions (F2-08, A15; ADR-0012): two partners, two roles,
-- one answer each.
--
-- The task's content and its answer key are in the language pack; the
-- server keeps who plays which role, where the session is and each
-- partner's answer. Only the two partners read a session (I-18). Nobody
-- writes the table directly: the functions below start, join, answer and
-- cancel, each changing only what the caller may change.

create table public.pair_sessions (
  id uuid primary key,
  team_id uuid not null references public.teams on delete cascade,
  task_ref text not null check (char_length(task_ref) <= 120),
  created_by uuid not null references public.profiles on delete cascade,
  participants uuid[] not null check (cardinality(participants) = 2),
  -- {"<profile id>": "a" | "b"}
  roles jsonb not null,
  state text not null default 'invited'
    check (state in ('invited', 'active', 'done', 'cancelled')),
  -- {"<profile id>": <answer>}; a choice or the lines marked.
  answers jsonb not null default '{}'::jsonb
    check (pg_column_size(answers) <= 4096),
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create index pair_sessions_participants_idx
  on public.pair_sessions using gin (participants);

alter table public.pair_sessions enable row level security;

revoke all on public.pair_sessions from anon, authenticated;
grant select on public.pair_sessions to authenticated;
grant select, insert, update, delete on public.pair_sessions to service_role;

create policy pair_sessions_select_participant on public.pair_sessions
  for select to authenticated
  using ((select auth.uid()) = any (participants));

alter publication supabase_realtime add table public.pair_sessions;

-- Starts session [p_id] on task [p_task_ref] with [p_partner], the caller in
-- role [p_role] ('a' or 'b') and the partner in the other; both must be in
-- one team. Asking again with the same id answers with the same session.
create function public.pair_start(
  p_id uuid,
  p_task_ref text,
  p_partner uuid,
  p_role text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_team uuid;
  v_session public.pair_sessions%rowtype;
begin
  if v_user is null then
    raise exception 'not_signed_in';
  end if;
  select * into v_session from public.pair_sessions s where s.id = p_id;
  if found then
    if v_session.created_by <> v_user then
      raise exception 'session_not_found';
    end if;
    return to_jsonb(v_session);
  end if;
  if p_role not in ('a', 'b') or p_partner = v_user then
    raise exception 'invalid_session';
  end if;
  select m.team_id into v_team
  from public.team_members m
  join public.team_members p on p.team_id = m.team_id and p.profile_id = p_partner
  where m.profile_id = v_user
  limit 1;
  if v_team is null then
    raise exception 'not_partners';
  end if;
  insert into public.pair_sessions (id, team_id, task_ref, created_by, participants, roles)
  values (
    p_id, v_team, btrim(coalesce(p_task_ref, '')), v_user, array[v_user, p_partner],
    jsonb_build_object(
      v_user::text, p_role,
      p_partner::text, case p_role when 'a' then 'b' else 'a' end
    )
  )
  returning * into v_session;
  return to_jsonb(v_session);
end;
$$;

-- The invited partner joins session [p_id]: it becomes active.
create function public.pair_join(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_session public.pair_sessions%rowtype;
begin
  update public.pair_sessions s
  set state = 'active'
  where s.id = p_id
    and v_user = any (s.participants)
    and s.created_by <> v_user
    and s.state = 'invited'
  returning * into v_session;
  if not found then
    select * into v_session from public.pair_sessions s
    where s.id = p_id and v_user = any (s.participants);
    if not found then
      raise exception 'session_not_found';
    end if;
  end if;
  return to_jsonb(v_session);
end;
$$;

-- The caller's answer [p_answer] in session [p_id], once it is active;
-- when both partners have answered, the session is done.
create function public.pair_answer(p_id uuid, p_answer jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_session public.pair_sessions%rowtype;
begin
  update public.pair_sessions s
  set answers = s.answers || jsonb_build_object(v_user::text, p_answer)
  where s.id = p_id
    and v_user = any (s.participants)
    and s.state = 'active'
  returning * into v_session;
  if not found then
    raise exception 'session_not_active';
  end if;
  if (select count(*) from jsonb_object_keys(v_session.answers)) = 2 then
    update public.pair_sessions s
    set state = 'done', ended_at = now()
    where s.id = p_id
    returning * into v_session;
  end if;
  return to_jsonb(v_session);
end;
$$;

-- Either partner cancels session [p_id] before it is done.
create function public.pair_cancel(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_session public.pair_sessions%rowtype;
begin
  update public.pair_sessions s
  set state = 'cancelled', ended_at = now()
  where s.id = p_id
    and v_user = any (s.participants)
    and s.state in ('invited', 'active')
  returning * into v_session;
  if not found then
    select * into v_session from public.pair_sessions s
    where s.id = p_id and v_user = any (s.participants);
    if not found then
      raise exception 'session_not_found';
    end if;
  end if;
  return to_jsonb(v_session);
end;
$$;

revoke all on function public.pair_start(uuid, text, uuid, text) from public, anon;
revoke all on function public.pair_join(uuid) from public, anon;
revoke all on function public.pair_answer(uuid, jsonb) from public, anon;
revoke all on function public.pair_cancel(uuid) from public, anon;
grant execute on function public.pair_start(uuid, text, uuid, text) to authenticated;
grant execute on function public.pair_join(uuid) to authenticated;
grant execute on function public.pair_answer(uuid, jsonb) to authenticated;
grant execute on function public.pair_cancel(uuid) to authenticated;
