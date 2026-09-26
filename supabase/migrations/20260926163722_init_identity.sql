-- Dilbaz schema v1: sync cursor, identity, courses and teams
-- (docs/13-data-model.md §1, §2.1, §3, §4). Every table has RLS enabled and
-- denies by default; access is granted by the policies below only.

-- ---------------------------------------------------------------------------
-- Private schema: helpers and tables that the Data API never exposes.
-- ---------------------------------------------------------------------------
create schema private;
revoke all on schema private from public;
grant usage on schema private to authenticated, supabase_auth_admin;

-- ---------------------------------------------------------------------------
-- Sync cursor: inserts and updates of synced rows take the next value, so
-- sync_pull can return everything with server_seq > cursor (docs/12 §6).
-- ---------------------------------------------------------------------------
create sequence public.sync_seq;
revoke all on sequence public.sync_seq from anon;
grant usage on sequence public.sync_seq to authenticated, service_role;

create function private.touch_server_seq()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.server_seq := nextval('public.sync_seq');
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null,
  l1 text not null default 'tr',
  ui_locale text not null default 'tr',
  time_budget_min int not null default 30 check (time_budget_min between 5 and 120),
  weekly_days_goal int not null default 5 check (weekly_days_goal between 1 and 7),
  anchors jsonb not null default '[]',
  quiet_hours jsonb,
  goal_text text,
  interests text[] not null default '{}',
  scaffold_overrides jsonb not null default '{}',
  settings jsonb not null default '{}',
  updated_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  created_at timestamptz not null default now()
);

create table public.courses (
  id uuid primary key,
  profile_id uuid not null references public.profiles on delete cascade,
  l2 text not null,
  pair_pack text not null,
  level_estimates jsonb not null default '{}',
  vocab_estimate int,
  fsrs_params jsonb,
  desired_retention numeric not null default 0.90
    check (desired_retention between 0.80 and 0.97),
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  created_at timestamptz not null default now(),
  unique (profile_id, l2)
);

create index profiles_server_seq on public.profiles (server_seq);
create index courses_profile_server_seq on public.courses (profile_id, server_seq);

create trigger profiles_touch_server_seq
  before update on public.profiles
  for each row execute function private.touch_server_seq();
create trigger courses_touch_server_seq
  before update on public.courses
  for each row execute function private.touch_server_seq();

-- ---------------------------------------------------------------------------
-- Teams (a couple): partners never read each other's raw data (I-18).
-- ---------------------------------------------------------------------------
create table public.teams (
  id uuid primary key,
  name text not null,
  invite_code text unique not null,
  created_by uuid not null references public.profiles,
  created_at timestamptz not null default now()
);

create table public.team_members (
  team_id uuid references public.teams on delete cascade,
  profile_id uuid references public.profiles on delete cascade,
  role text not null default 'member',
  share_levels boolean not null default false,
  share_monthly boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (team_id, profile_id)
);

create index team_members_profile on public.team_members (profile_id);

-- Membership check used by policies. SECURITY DEFINER avoids policy
-- recursion on team_members; it lives in the private schema, so it is not
-- callable through the Data API.
create function private.is_team_member(p_team_id uuid)
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
      and m.profile_id = (select auth.uid())
  );
$$;
revoke all on function private.is_team_member(uuid) from public;
grant execute on function private.is_team_member(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;

revoke all on public.profiles, public.courses, public.teams, public.team_members
  from anon;

create policy profiles_select_own on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy courses_select_own on public.courses
  for select to authenticated using (profile_id = (select auth.uid()));
create policy courses_insert_own on public.courses
  for insert to authenticated with check (profile_id = (select auth.uid()));
create policy courses_update_own on public.courses
  for update to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy teams_select_member_or_creator on public.teams
  for select to authenticated
  using (created_by = (select auth.uid()) or private.is_team_member(id));
create policy teams_insert_creator on public.teams
  for insert to authenticated with check (created_by = (select auth.uid()));

-- Members see the member rows of their own teams; joining another team goes
-- through an invite-code function (F1-12), not a direct insert.
create policy team_members_select_team on public.team_members
  for select to authenticated using (private.is_team_member(team_id));
create policy team_members_insert_creator on public.team_members
  for insert to authenticated
  with check (
    profile_id = (select auth.uid())
    and exists (
      select 1 from public.teams t
      where t.id = team_id and t.created_by = (select auth.uid())
    )
  );
create policy team_members_update_own on public.team_members
  for update to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

-- A member may change only their own sharing switches.
revoke update on public.team_members from authenticated;
grant update (share_levels, share_monthly) on public.team_members to authenticated;

-- ---------------------------------------------------------------------------
-- Sign-up allowlist (docs/14 §2): the before-user-created auth hook rejects
-- every email that is not listed. Kept private so the addresses are never
-- readable through the API. Rows are added by the operator via SQL.
-- ---------------------------------------------------------------------------
create table private.signup_allowlist (
  email text primary key check (email = lower(email)),
  note text,
  created_at timestamptz not null default now()
);
alter table private.signup_allowlist enable row level security;
revoke all on private.signup_allowlist from public, anon, authenticated;
grant select on private.signup_allowlist to supabase_auth_admin;
create policy signup_allowlist_read_by_auth on private.signup_allowlist
  for select to supabase_auth_admin using (true);

create function private.hook_before_user_created(event jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  candidate text := lower(event -> 'user' ->> 'email');
begin
  if candidate is not null and exists (
    select 1 from private.signup_allowlist a where a.email = candidate
  ) then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object(
    'error',
    jsonb_build_object('http_code', 403, 'message', 'signup_not_allowed')
  );
end;
$$;
revoke execute on function private.hook_before_user_created(jsonb)
  from public, anon, authenticated;
grant execute on function private.hook_before_user_created(jsonb)
  to supabase_auth_admin;
