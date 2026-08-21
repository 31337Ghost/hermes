#!/usr/bin/env bash
set -euo pipefail

if docker compose version >/dev/null 2>&1; then
  compose=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  compose=(docker-compose)
else
  echo "browser-check: Docker Compose is unavailable" >&2
  exit 1
fi

compose+=( -f docker-compose.yml -f docker-compose.browser.yml )
container_id="$("${compose[@]}" ps -q browser)"
cdp_proxy_id="$("${compose[@]}" ps -q cdp-proxy)"
if [[ -z "$container_id" ]] || [[ "$(docker inspect -f '{{.State.Running}}' "$container_id")" != "true" ]]; then
  echo "browser-check: browser container is not running" >&2
  exit 1
fi
if [[ -z "$cdp_proxy_id" ]] || [[ "$(docker inspect -f '{{.State.Running}}' "$cdp_proxy_id")" != "true" ]]; then
  echo "browser-check: cdp-proxy container is not running" >&2
  exit 1
fi

container_env="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container_id")"
username="$(sed -n 's/^CUSTOM_USER=//p' <<<"$container_env" | head -n1)"
password="$(sed -n 's/^PASSWORD=//p' <<<"$container_env" | head -n1)"
proxy_url="$(sed -n 's/^HTTPS_PROXY=//p' <<<"$container_env" | head -n1)"
expected_country="$(sed -n 's/^BROWSER_EXPECTED_COUNTRY=//p' <<<"$container_env" | head -n1)"
country_url="$(sed -n 's/^BROWSER_COUNTRY_CHECK_URL=//p' <<<"$container_env" | head -n1)"
expected_puid="$(sed -n 's/^PUID=//p' <<<"$container_env" | head -n1)"
harden_desktop="$(sed -n 's/^HARDEN_DESKTOP=//p' <<<"$container_env" | head -n1)"
sharing="$(sed -n 's/^SELKIES_ENABLE_SHARING=//p' <<<"$container_env" | head -n1)"
command_enabled="$(sed -n 's/^SELKIES_COMMAND_ENABLED=//p' <<<"$container_env" | head -n1)"
ui_files="$(sed -n 's/^SELKIES_UI_SIDEBAR_SHOW_FILES=//p' <<<"$container_env" | head -n1)"
ui_apps="$(sed -n 's/^SELKIES_UI_SIDEBAR_SHOW_APPS=//p' <<<"$container_env" | head -n1)"

if [[ -z "$username" || -z "$password" || -z "$proxy_url" || -z "$expected_country" || -z "$country_url" || -z "$expected_puid" ]]; then
  echo "browser-check: required browser environment is missing" >&2
  exit 1
fi
if [[ "$harden_desktop" != "true" || "$sharing" != "false|locked" \
  || "$command_enabled" != "false|locked" || "$ui_files" != "false|locked" || "$ui_apps" != "false|locked" ]]; then
  echo "browser-check: desktop hardening, sharing lock, or tools lock is missing" >&2
  exit 1
fi

published="$("${compose[@]}" port browser 3001 | head -n1)"
if [[ -z "$published" ]]; then
  echo "browser-check: HTTPS port 3001 is not published" >&2
  exit 1
fi
if [[ "$published" == 0.0.0.0:* ]]; then
  published="127.0.0.1:${published##*:}"
fi
url="https://${published}"

unauth_status=""
for _ in {1..30}; do
  unauth_status="$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 2 "$url/" 2>/dev/null || true)"
  [[ "$unauth_status" == "401" ]] && break
  sleep 1
done
[[ "$unauth_status" == "401" ]] || { echo "browser-check: HTTPS did not become ready within 30 seconds (last status: ${unauth_status:-unreachable})" >&2; exit 1; }

auth_status="$(curl -ksS -u "$username:$password" -o /dev/null -w '%{http_code}' --max-time 15 "$url/" 2>/dev/null || true)"
[[ "$auth_status" == "200" ]] || { echo "browser-check: expected authenticated 200, got ${auth_status:-unreachable}" >&2; exit 1; }

processes=""
browser_ready=false
for _ in {1..30}; do
  processes="$(docker exec "$container_id" pgrep -af chromium 2>/dev/null || true)"
  if grep -Fq -- "--proxy-server=$proxy_url" <<<"$processes" \
    && grep -Fq -- "--user-data-dir=/config/chromium-profile" <<<"$processes" \
    && grep -Fq -- "--remote-debugging-port=9222" <<<"$processes" \
    && grep -Fq -- "--ozone-platform=wayland" <<<"$processes" \
    && docker exec "$container_id" test -f /config/chromium-profile/Default/Preferences; then
    browser_ready=true
    break
  fi
  sleep 1
done

if [[ "$browser_ready" != "true" ]]; then
  [[ -n "$processes" ]] || { echo "browser-check: Chromium did not start within 30 seconds" >&2; exit 1; }
  grep -Fq -- "--proxy-server=$proxy_url" <<<"$processes" || { echo "browser-check: Chromium proxy flag is missing" >&2; exit 1; }
  grep -Fq -- "--user-data-dir=/config/chromium-profile" <<<"$processes" || { echo "browser-check: dedicated persistent profile flag is missing" >&2; exit 1; }
  grep -Fq -- "--remote-debugging-port=9222" <<<"$processes" || { echo "browser-check: Chromium CDP flag is missing" >&2; exit 1; }
  grep -Fq -- "--ozone-platform=wayland" <<<"$processes" || { echo "browser-check: Chromium is not using the graphical Wayland display" >&2; exit 1; }
  echo "browser-check: persistent Chromium profile was not created within 30 seconds" >&2
  exit 1
fi

if grep -Eq -- '(^|[[:space:]])--headless([=[:space:]]|$)' <<<"$processes"; then
  echo "browser-check: Chromium unexpectedly runs headless" >&2
  exit 1
fi

profile_uid="$(docker exec "$container_id" stat -c '%u' /config/chromium-profile)"
[[ "$profile_uid" == "$expected_puid" ]] || {
  echo "browser-check: persistent Chromium profile has the wrong owner" >&2
  exit 1
}
relay_pid="$(docker exec "$container_id" sh -c 'read -r pid < /tmp/browser-cdp-relay.pid; printf "%s" "$pid"' 2>/dev/null || true)"
relay_user="$(docker exec "$container_id" ps -o user= -p "$relay_pid" 2>/dev/null | tr -d '[:space:]' || true)"
[[ "$relay_user" == "abc" ]] || {
  echo "browser-check: CDP relay is missing or did not drop privileges" >&2
  exit 1
}

origin_status="$(docker exec "$container_id" curl --noproxy '*' -sS -o /dev/null -w '%{http_code}' \
  -H 'Origin: https://untrusted.example' --max-time 5 http://cdp-proxy:9223/json/version 2>/dev/null || true)"
[[ "$origin_status" == "403" ]] || {
  echo "browser-check: CDP proxy did not reject a browser Origin header" >&2
  exit 1
}

browser_country=""
for _ in {1..30}; do
  browser_country="$(docker exec -i -e COUNTRY_URL="$country_url" "$container_id" \
    env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
    python3 - < scripts/browser-cdp-check.py 2>/dev/null | tr -d '\r\n[:space:]' || true)"
  [[ -n "$browser_country" ]] && break
  sleep 1
done
[[ -n "$browser_country" ]] || {
  echo "browser-check: Chromium CDP attach or country-page navigation failed" >&2
  exit 1
}
[[ "$browser_country" == "$expected_country" ]] || {
  echo "browser-check: expected Chromium egress $expected_country, got ${browser_country:-empty}" >&2
  exit 1
}

printf 'browser-check: ok\n'
printf '  url: %s\n' "$url/"
printf '  auth: 401 without credentials, 200 with credentials\n'
printf '  mode: headful Wayland Chromium\n'
printf '  cdp: Hermes attach works; browser Origin is rejected\n'
printf '  proxy: configured\n'
printf '  Chromium egress: %s\n' "$browser_country"
printf '  hardening: desktop tools locked, sharing disabled\n'
printf '  profile: persistent mount ready\n'
