-- "Tüm verimi sil" (docs/14-security-privacy.md §4, docs/13 §2.7): the
-- learner's rows, all of them, in one transaction.
--
-- - Every user table hangs off the profile (on delete cascade), so the
--   profile goes last. Usage counts stay without a name (on delete set
--   null).
-- - A team the learner made goes too: its partner keeps their own data.
-- - The audio in Storage is removed by the app through the Storage API
--   before this runs; Storage does not allow direct deletes.
-- - The account stays, so the learner can start again.
create function public.delete_my_data()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  delete from public.teams where created_by = v_uid;
  delete from public.profiles where id = v_uid;
end;
$$;

revoke execute on function public.delete_my_data() from public, anon;
grant execute on function public.delete_my_data() to authenticated;
