-- Creating a team and joining one with its invite code
-- (docs/13-data-model.md §4, docs/09-ux-motivation.md §7).
--
-- Row level security lets a user create a team in their own name and add
-- themselves to it, but never add themselves to another team. Joining
-- therefore runs as a SECURITY DEFINER function that checks the invite
-- code. Creating stays under the caller's own rights; the function only
-- makes the code on the server and writes both rows together.

create function public.create_team(p_name text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_id uuid := gen_random_uuid();
  v_name text := btrim(coalesce(p_name, ''));
  v_code text;
begin
  if v_name = '' then
    raise exception 'team_name_required';
  end if;
  loop
    -- Ten characters of a random UUID: 40 random bits, easy to read out.
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    begin
      insert into public.teams (id, name, invite_code, created_by)
      values (v_id, v_name, v_code, v_user);
      exit;
    exception when unique_violation then
      null;  -- The code is taken; draw another.
    end;
  end loop;
  insert into public.team_members (team_id, profile_id, role)
  values (v_id, v_user, 'owner');
  return jsonb_build_object('id', v_id, 'name', v_name, 'invite_code', v_code);
end;
$$;

create function public.join_team(p_invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_team public.teams%rowtype;
begin
  if v_user is null then
    raise exception 'not_signed_in';
  end if;
  select * into v_team
  from public.teams t
  where t.invite_code = upper(btrim(coalesce(p_invite_code, '')));
  if not found then
    raise exception 'invite_not_found';
  end if;
  insert into public.team_members (team_id, profile_id)
  values (v_team.id, v_user)
  on conflict (team_id, profile_id) do nothing;
  return jsonb_build_object('id', v_team.id, 'name', v_team.name);
end;
$$;

-- Functions are executable by everyone unless revoked.
revoke all on function public.create_team(text) from public, anon;
revoke all on function public.join_team(text) from public, anon;
grant execute on function public.create_team(text) to authenticated;
grant execute on function public.join_team(text) to authenticated;
