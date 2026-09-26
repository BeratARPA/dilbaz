-- Local development only (supabase db reset). Test addresses that may sign
-- in with an email code; production entries are added by the operator.
insert into private.signup_allowlist (email, note) values
  ('dev1@dilbaz.test', 'local test user'),
  ('dev2@dilbaz.test', 'local test user')
on conflict do nothing;
