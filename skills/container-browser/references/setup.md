# Install and provision the container-browser skill

## Install in one deployment

Run on the deployment host, from this repository's root. Review an existing installation before overwriting it; persona-specific browser skills may already be installed and should be reconciled deliberately rather than left with competing instructions.

```bash
mkdir -p ./data/skills
cp -R ./skills/container-browser ./data/skills/
```

The Compose mount `./data:/opt/data` makes this skill available at `/opt/data/skills/container-browser/SKILL.md`. Nothing is installed automatically by `git pull`; copy the skill again deliberately when updating it. No gateway restart or browser recreation is required just to copy the skill. Start a fresh chat if the running session's skill catalog does not show it.

For other layouts, install into the current profile's `<hermes-home>/skills/`, not another user's home. The authoritative [Hermes skills documentation](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills/) describes discovery and external directories.

## Provision private human-access data

Use the existing ignored `data/` mount, separate from this tracked skill:

```bash
umask 077
install -d -m 700 ./data/secrets
```

Keep this restrictive umask in the shell used to create the file so it is private from creation, not only after the later `chmod`.

Create `./data/secrets/container-browser.json` with an editor or a secret manager, using this schema (these are non-working placeholders):

```json
{
  "url": "https://browser.example.invalid/person/",
  "login": "",
  "password": ""
}
```

Set `url` to the **actual user-reachable GUI URL**, with the reverse-proxy subpath if configured. Match `login` to the deployment's `.env` `BROWSER_USER` and `password` to `BROWSER_PASSWORD`. Then restrict the file:

```bash
chmod 600 ./data/secrets/container-browser.json
```

Ensure the directory and file are owned by/readable to the agent's container UID; `700`/`600` alone will not fix an ownership mismatch. Do not make them world-readable to solve access errors.

Two private stores intentionally exist: `.env` configures Chromium, while this JSON lets Hermes answer an authorized user's access request without reading the whole deployment environment. Rotate both together, apply the container credential change through the operator's normal deployment procedure, and verify the new GUI login. Do not commit either store or copy real credentials into examples, skills, memory, or validation output. This repository ignores `.env`, `data/`, and `browser-data/`; never force-add them.

The repository does not provision a public domain or path router. Its default GUI URL, `https://127.0.0.1:<BROWSER_HTTPS_PORT>/`, works only on the Docker host (or via an appropriate tunnel), and uses a self-signed certificate. For remote users, configure an authenticated private route or HTTPS reverse proxy and record that real URL. Never tell a remote user to open their own localhost. See the repository's `README.browser.md` for deployment security details.

## Optional terminal harness

The Compose image and this skill do **not** guarantee `browser_exec` or `browser-harness` is installed. Prefer the configured native CDP-capable tool. Use this fallback only after checking that `browser-harness` is already available and that it supports the helpers/variables below; otherwise report the missing prerequisite rather than downloading an unreviewed package.

A previously provisioned harness may be under `/opt/data/home/.local/bin`, which a raw `docker exec` shell does not necessarily include in `PATH`. Use one stable deployment-local session name, an agent-writable runtime directory, and the connection variables in **every same-shell invocation**. An ensure/check subprocess cannot export its environment back into its parent shell.

For a harness provisioned with its home at `/opt/data/home`, the invocation is:

```bash
export HOME=/opt/data/home
export PATH="$HOME/.local/bin:$PATH"
export BH_RUNTIME_DIR=/tmp/hermes-browser-harness-runtime
export BH_RUNTIME_DIR_SHARED=1
export BU_NAME=container-browser
export BU_CDP_URL="${BROWSER_CDP_URL:?BROWSER_CDP_URL must be configured}"
unset BU_CDP_WS
command -v browser-harness
browser-harness <<'PY'
# Checking the configured container browser
print(cdp('Browser.getVersion'))
PY
```

This is a connectivity probe, not a navigation test. A Linux Chromium user-agent alone does not prove tenant identity: verify the session is explicitly attached to the configured endpoint. Preserve task target IDs across calls as described in `SKILL.md`. Do not launch/reload a shared daemon merely because an unrelated probe failed; if an existing session is bound to another endpoint, stop and resolve the conflict with the operator.

## Acceptance checks

1. The installed skill is discoverable in the target profile's fresh session. Ask “How do I open my browser?”; it should read this deployment's runtime record, give the actual GUI link, and never invent an address.
2. Check the runtime JSON parses and required values are populated **without printing the password**. Check `git check-ignore .env data/secrets/container-browser.json browser-data/` confirms private paths are ignored.
3. Run the CDP probe from `SKILL.md` inside the agent container; expect `container_browser=ready`.
4. Through the available browser tool, record baseline targets, create one task tab, navigate to a harmless page, inspect the actual page, close that target, and verify baseline tabs remain. HTTP discovery alone is not this test.
5. With the owner present, hand off an actual login tab through the configured GUI URL, pause, resume after their confirmation, and verify signed-in state in the same profile. Do not perform a login or credential rotation just to install this documentation.

Report checks not exercised as unverified. Installation does not itself prove GUI reachability, authentication, or browser-tool availability.
