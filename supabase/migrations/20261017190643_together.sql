-- Together (F2-07; docs/05 §6, docs/09 §7, A14): "birlikte yapalım mı?"
-- invitations and the partners' presence on their team's channel.
--
-- An invitation is delivered in the app (user decision 2026-10-17): over
-- Realtime while the partner's app is open, on its Today screen at the next
-- opening. Only the two partners see it (I-18); the invited one answers,
-- the inviting one may take it back. Presence says who is in the app now,
-- nothing more, on the private channel `team:<team id>`.

create table public.pair_invites (
  id uuid primary key,
  team_id uuid not null references public.teams on delete cascade,
  from_profile uuid not null references public.profiles on delete cascade,
  to_profile uuid not null references public.profiles on delete cascade,
  -- What to do together: a chat card (A14) for now.
  activity text not null check (activity in ('chat')),
  task_ref text check (char_length(task_ref) <= 120),
  state text not null default 'sent'
    check (state in ('sent', 'accepted', 'declined', 'cancelled')),
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  check (from_profile <> to_profile)
);

create index pair_invites_to_profile_created_at_idx
  on public.pair_invites (to_profile, created_at desc);
create index pair_invites_from_profile_created_at_idx
  on public.pair_invites (from_profile, created_at desc);

-- Whether [p_profile] is a member of [p_team]: a team's other member, for
-- an invitation's addressee. SECURITY DEFINER, as `is_team_member`: the
-- caller may only read their own team's rows.
create function private.team_has_member(p_team_id uuid, p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.team_members m
    where m.team_id = p_team_id
      and m.profile_id = p_profile_id
  );
$$;

revoke all on function private.team_has_member(uuid, uuid) from public;
grant execute on function private.team_has_member(uuid, uuid) to authenticated;

alter table public.pair_invites enable row level security;

revoke all on public.pair_invites from anon, authenticated;
grant select, insert on public.pair_invites to authenticated;
-- Answering changes the state and its time, nothing else.
grant update (state, answered_at) on public.pair_invites to authenticated;
grant select, insert, update, delete on public.pair_invites to service_role;

create policy pair_invites_select_own on public.pair_invites
  for select to authenticated
  using (
    from_profile = (select auth.uid()) or to_profile = (select auth.uid())
  );

-- Sent in one's own name, to a member of one's own team.
create policy pair_invites_insert_own on public.pair_invites
  for insert to authenticated
  with check (
    from_profile = (select auth.uid())
    and state = 'sent'
    and answered_at is null
    and private.is_team_member(team_id)
    and private.team_has_member(team_id, to_profile)
  );

-- An invitation still open is answered by the invited partner, or taken
-- back by the one who sent it.
create policy pair_invites_update_answer on public.pair_invites
  for update to authenticated
  using (
    state = 'sent'
    and (to_profile = (select auth.uid()) or from_profile = (select auth.uid()))
  )
  with check (
    (to_profile = (select auth.uid()) and state in ('accepted', 'declined'))
    or (from_profile = (select auth.uid()) and state = 'cancelled')
  );

-- Changes reach the partners' open apps (RLS applies to them).
alter publication supabase_realtime add table public.pair_invites;

-- ---------------------------------------------------------------------------
-- Presence on `team:<team id>` (Realtime Authorization, private channels)
-- ---------------------------------------------------------------------------

-- Whether the signed-in user may use channel [p_topic]: `team:<id>` of a
-- team they are a member of. Any other topic, or a malformed one, is not.
create function private.may_use_team_topic(p_topic text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_team uuid;
begin
  if p_topic is null or p_topic not like 'team:%' then
    return false;
  end if;
  begin
    v_team := substr(p_topic, 6)::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  return private.is_team_member(v_team);
end;
$$;

revoke all on function private.may_use_team_topic(text) from public;
grant execute on function private.may_use_team_topic(text) to authenticated;

create policy team_presence_listen on realtime.messages
  for select to authenticated
  using (
    realtime.messages.extension = 'presence'
    and private.may_use_team_topic((select realtime.topic()))
  );

create policy team_presence_track on realtime.messages
  for insert to authenticated
  with check (
    realtime.messages.extension = 'presence'
    and private.may_use_team_topic((select realtime.topic()))
  );

-- ---------------------------------------------------------------------------
-- The caller's team and its members' names (the Together tab)
-- ---------------------------------------------------------------------------

-- The caller's first team, with each member's display name: partners know
-- each other by name, nothing more of the profile (I-18, docs/14 §3).
-- Null without a team.
create function public.my_team()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.id,
    'name', t.name,
    'members', (
      select jsonb_agg(
        jsonb_build_object('id', p.id, 'name', p.display_name)
        order by m.joined_at, p.id
      )
      from public.team_members m
      join public.profiles p on p.id = m.profile_id
      where m.team_id = t.id
    )
  )
  from public.teams t
  where exists (
    select 1 from public.team_members m
    where m.team_id = t.id and m.profile_id = (select auth.uid())
  )
  order by t.created_at
  limit 1;
$$;

revoke all on function public.my_team() from public, anon;
grant execute on function public.my_team() to authenticated;
