#!/usr/bin/env bash
set -euo pipefail

if docker compose version >/dev/null 2>&1; then
  compose=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  compose=(docker-compose)
else
  echo "browser-recreate-check: Docker Compose is unavailable" >&2
  exit 1
fi

compose+=( -f docker-compose.yml -f docker-compose.browser.yml )
container_id="$("${compose[@]}" ps -q browser)"
if [[ -z "$container_id" ]] || [[ "$(docker inspect -f '{{.State.Running}}' "$container_id")" != "true" ]]; then
  echo "browser-recreate-check: browser container is not running" >&2
  exit 1
fi

token="$(openssl rand -hex 16)"
sentinel=/config/chromium-profile/.hermes-persistence-check
cleanup() {
  local current_id
  current_id="$("${compose[@]}" ps -q browser 2>/dev/null || true)"
  if [[ -n "$current_id" ]]; then
    docker exec -u abc "$current_id" rm -f "$sentinel" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

docker exec -u abc "$container_id" sh -c 'umask 077; printf "%s\n" "$1" > "$2"' sh "$token" "$sentinel"
"${compose[@]}" up -d --force-recreate browser cdp-proxy
./scripts/browser-check.sh

container_id="$("${compose[@]}" ps -q browser)"
actual="$(docker exec -u abc "$container_id" sh -c 'read -r value < "$1"; printf "%s" "$value"' sh "$sentinel")"
[[ "$actual" == "$token" ]] || {
  echo "browser-recreate-check: profile sentinel did not survive recreation" >&2
  exit 1
}

printf 'browser-recreate-check: ok (profile survived container recreation)\n'
