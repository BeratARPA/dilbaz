"""A test user on the LOCAL Supabase stack for the live check.

Reads the local stack's URL and keys from `supabase status -o env` (local
test keys only), puts the test e-mail on the local sign-up allowlist,
creates a confirmed user with a random password and a profile that agreed
to the AI data use (as the real learner did). Writes what the live test
needs to <out>; prints no key or password.

Usage: python -I make_live_user.py <repo> <out-env-file>
"""

import json
import secrets
import subprocess
import sys
import urllib.request

repo, out = sys.argv[1], sys.argv[2]
EMAIL = "canli-test@dilbaz.test"


def npx(*args: str) -> str:
    return subprocess.run(
        ["npx.cmd", "supabase", *args],
        cwd=repo,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    ).stdout


env = {}
for line in npx("status", "-o", "env").splitlines():
    if "=" in line:
        key, _, value = line.partition("=")
        env[key.strip()] = value.strip().strip('"')
url, service, anon = env["API_URL"], env["SERVICE_ROLE_KEY"], env["ANON_KEY"]
assert url.startswith("http://127.0.0.1:"), "local stack only"

npx(
    "db", "query", "--local",
    f"insert into private.signup_allowlist (email, note) values ('{EMAIL}', 'local live check') on conflict do nothing",
)

password = secrets.token_urlsafe(18)
headers = {
    "apikey": service,
    "Authorization": f"Bearer {service}",
    "Content-Type": "application/json",
}


def call(method: str, path: str, body: dict | None = None) -> dict:
    request = urllib.request.Request(
        url + path,
        method=method,
        headers=headers,
        data=None if body is None else json.dumps(body).encode(),
    )
    with urllib.request.urlopen(request) as response:
        return json.loads(response.read() or b"{}")


users = call("GET", "/auth/v1/admin/users?per_page=200").get("users", [])
existing = next((u for u in users if u.get("email") == EMAIL), None)
if existing:
    user_id = existing["id"]
    call("PUT", f"/auth/v1/admin/users/{user_id}", {"password": password})
else:
    user_id = call(
        "POST",
        "/auth/v1/admin/users",
        {"email": EMAIL, "password": password, "email_confirm": True},
    )["id"]

settings = json.dumps({"ai_data_consent": {"granted": True}})
npx(
    "db", "query", "--local",
    "insert into public.profiles (id, display_name, settings) "
    f"values ('{user_id}', 'Canli test', '{settings}'::jsonb) "
    "on conflict (id) do update set settings = excluded.settings",
)

with open(out, "w", encoding="utf-8") as fh:
    fh.write(f"DILBAZ_LIVE_URL={url}\n")
    fh.write(f"DILBAZ_LIVE_ANON={anon}\n")
    fh.write(f"DILBAZ_LIVE_EMAIL={EMAIL}\n")
    fh.write(f"DILBAZ_LIVE_PASSWORD={password}\n")
print("local test user ready:", EMAIL, "(id", user_id[:8] + "…)")
