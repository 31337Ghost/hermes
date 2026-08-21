#!/usr/bin/with-contenv bash
set -euo pipefail

profile=/config/chromium-profile
owner_marker=/config/.chromium-profile-owner
uid="$(id -u abc)"
gid="$(id -g abc)"
expected_owner="$uid:$gid"
current_owner=""

install -d -m 700 -o "$uid" -g "$gid" "$profile"
rm -f "$profile"/SingletonCookie "$profile"/SingletonLock "$profile"/SingletonSocket

if [[ -f "$owner_marker" ]]; then
  current_owner="$(<"$owner_marker")"
fi
if [[ "$current_owner" != "$expected_owner" ]]; then
  chown -R "$uid:$gid" "$profile"
  printf '%s\n' "$expected_owner" > "$owner_marker"
  chown "$uid:$gid" "$owner_marker"
  chmod 600 "$owner_marker"
fi
