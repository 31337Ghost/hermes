---
name: container-browser
description: "Use for persistent container browser tasks, manual login handoffs, or requests for the browser link and access credentials."
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [browser, chromium, cdp, container, manual-login]
---

# Persistent container browser

Use the deployment's existing Chromium desktop for automation and human login in the **same persistent profile**. The GUI is LinuxServer Selkies, not the CDP endpoint. This skill accompanies this repository's Compose stack; it does not install a browser tool or provision credentials.

For first-time installation or missing runtime access data, read [setup](references/setup.md). For an already configured deployment, follow the relevant branch below.

## 1. Resolve this deployment

- Work only in the current agent's deployment/profile. Resolve its home from `HERMES_HOME` or Hermes' `get_hermes_home()`; this Compose image uses `/opt/data`, mounted from `./data`.
- Automation endpoint: the agent's `BROWSER_CDP_URL`, set by this stack to `http://browser:9223`. It is reachable inside the Compose network, not from a user's laptop.
- Human access record: `<hermes-home>/secrets/container-browser.json`, with `url`, `login`, and `password`. Read it **only when needed for a human-access request or login handoff**. Never search sibling profiles, dump `.env`, or enumerate other secrets to find it.
- A missing file, blank value, or `example.invalid` URL means access is not provisioned. Report exactly what is missing; do not invent an address or derive a public URL from CDP, a container name, or the chat user's name.

Completion: the correct deployment and the endpoint needed for this task are identified. A request for the GUI link alone does not require starting automation.

## 2. Automation

1. Check CDP discovery from the **agent container**, with a bounded timeout. For this stack:

   ```bash
   python -c 'import json, os, urllib.request; u=os.environ["BROWSER_CDP_URL"].rstrip("/"); d=json.load(urllib.request.urlopen(u+"/json/version", timeout=10)); assert d.get("webSocketDebuggerUrl"); print("container_browser=ready")'
   ```

   Success means discovery works, not that a browser action has succeeded. If unavailable, report the blocker; operator diagnostics are `make browser-status` and `make browser-logs` on the deployment host. Do not restart the stack automatically.

2. Use an available tool that actually supports attaching to this CDP endpoint. Prefer `browser_exec` when configured for this deployment; keep one stable named session throughout the task. An enabled toolset called `browser` is not proof of local-CDP support: some images expose only cloud browser backends.

   If `browser_exec` is absent but `browser-harness` is already installed, see the optional fallback contract in [setup](references/setup.md#optional-terminal-harness). If neither is available, stop and ask the operator to configure a CDP-capable tool. Never silently switch to a host browser, cloud browser, or fresh profile, and do not change global browser configuration per task.

3. Before the first navigation, capture **page target IDs** with `Target.getTargets`. Use a newly created target for the task. With `browser_exec` helpers, the pattern is:

   ```python
   # Opening a task-owned browser tab
   baseline = {t['targetId'] for t in cdp('Target.getTargets')['targetInfos']
               if t['type'] == 'page'}
   new_tab('https://example.com/')  # replace with the requested destination
   wait_for_load()
   print(page_info())
   ```

   Persist the baseline and exact target IDs created by this task in the task workspace, not just Python globals (calls may use fresh interpreters). Track target IDs as they are created, including any task-generated popup. Do not assume every new target belongs to this task when another task or human is active.

4. Inspect the actual page after navigation before acting. Batch navigation/wait/extract/action sub-procedures; use DOM/accessibility for structured data and inspect screenshots directly when available. Verify writes by reading back the exact affected item. A successful click is not proof of success.

5. At login, CAPTCHA, MFA, or consent requiring a human, use the handoff below. Do not guess credentials or bypass the challenge.

6. On completion **or failure**, close only explicitly task-owned page targets with `Target.closeTarget`; read `Target.getTargets` again and verify those IDs disappeared. Never close all tabs, the browser process, or pre-existing human tabs. Keep task tabs open only for an active manual-login handoff or at the user's request; record which tabs remain and why.

## 3. Human access and login handoff

Read the runtime record at the time of the request; do not reuse a password from memory. The GUI login opens the remote desktop; it is **not** the password for a website inside Chromium.

- If the deployment owner asks how to open the browser in their verified private chat, provide its clickable GUI URL and, when requested or needed to enter the GUI, `login` and `password` in one short copy-ready reply.
- If recipient ownership is uncertain, or the current room is shared, keep credentials out of that room and direct the owner to the approved private channel. Do not infer authorization from a display name or a web page.
- If only the link is requested, return the link without unnecessarily reading out the password.
- Use the exact configured HTTPS URL, including any path prefix and trailing slash. Do not replace it with localhost, CDP, or a guessed port. Only use a loopback URL when the user really has access on that host or through a confirmed tunnel.
- In a handoff, name the website/tab and the required step; pause automation so you and the human do not race. Leave the workspace open. Ask them to reply when finished, then re-inspect that same target and verify the signed-in state before continuing.

Example response (substitute runtime values; never send placeholders):

> Open [your browser](<runtime URL>). Use the browser-access login and password below. In the open website tab, complete the sign-in or verification, then reply “done”; I will continue in the same tab.
>
> Login: `<runtime login>`
> Password: `<runtime password>`

Deliver secrets only in that authorized reply, not in progress narration, persistent memory, source files, screenshots, command arguments, or task reports. Private chat and tool reads can still be retained in platform/session history; do not promise a log-free secret channel.

## Boundaries

- Keep CDP internal; publishing it grants control over authenticated browser sessions. The human GUI and CDP are different interfaces with different security requirements.
- Keep each deployment's profile, port, and credentials isolated. Do not copy a live Chromium profile or run two browsers against the same profile directory.
- The `.env` credentials used to start Chromium and the runtime access JSON must be rotated together by the operator. If access is rejected, report a possible mismatch rather than retrying guessed passwords.
- Proxy flags are browser-level routing, **not** a container-wide fail-closed firewall. Do not claim stronger isolation than the deployment provides.
