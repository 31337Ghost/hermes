# Headful Chromium browser

This optional module runs an isolated, persistent Chromium desktop through LinuxServer's browser-native Selkies interface. A person can complete logins or CAPTCHAs in the GUI, then Hermes continues in the same browser profile through the internal `cdp-proxy` service.

## Configure one deployment

Add these values to the deployment's ignored `.env` file:

```dotenv
COMPOSE_PROJECT_NAME=hermes-katya
BROWSER_USER=katya
BROWSER_PASSWORD=generate-a-long-random-password
BROWSER_PROXY_URL=http://proxy-host:8080
BROWSER_EXPECTED_COUNTRY=RU
BROWSER_HTTPS_PORT=13001
BROWSER_PROFILE_DIR=./browser-data/hermes-katya
BROWSER_PUID=501
BROWSER_PGID=20
TZ=Europe/Moscow
```

Use a unique `COMPOSE_PROJECT_NAME`, `BROWSER_USER`, `BROWSER_PASSWORD`, `BROWSER_HTTPS_PORT`, and `BROWSER_PROFILE_DIR` in every deployment. The browser overlay refuses to render unless the project name, GUI port, and profile path are all explicit; this prevents projects launched from the same checkout from sharing containers, ports, cookies, or authenticated sessions.

The browser overlay sets `BROWSER_CDP_URL=http://cdp-proxy:9223` on the Hermes `agent` service, so `make browser-up` recreates/starts the agent with the internal CDP endpoint automatically. No tracked deployment config or manual `data/config.yaml` edit is required.

Generate a password with:

```bash
openssl rand -base64 24 | tr -d '/+=' | cut -c1-24
```

## Operate

```bash
make browser-up
make browser-check
make browser-recreate-check  # force-recreates services and verifies profile persistence
make browser-status
make browser-logs
make browser-stop
```

Open `https://127.0.0.1:<BROWSER_HTTPS_PORT>/`. The interface uses a self-signed certificate, so the first visit shows a certificate warning.

`make browser-check` verifies HTTPS authentication, graphical non-headless Chromium, the fixed proxy flag, Chromium's country-level egress using an isolated CDP page, hardened desktop settings, persistent profile ownership, and a real CDP WebSocket command through `cdp-proxy`. It never prints the password, public IP, or CDP session URL.

`make browser-recreate-check` writes a temporary sentinel inside the Chromium profile, force-recreates `browser` and `cdp-proxy`, reruns the full check, verifies the sentinel, and removes it. Existing cookies and logins are not cleared.

## Isolation and security

- The GUI port binds to `127.0.0.1` by default. Do not change `BROWSER_BIND_HOST` to `0.0.0.0` for public exposure.
- Chromium's debugging port is exposed only to the Compose network. Hermes reaches it through `cdp-proxy:9223`; neither CDP port is published on the host.
- For remote access, keep the loopback bind and publish it through an authenticated private network such as Tailscale, or through an authenticated reverse proxy.
- The browser is not attached to the application default network. It uses a dedicated egress network plus an internal control network shared only with `cdp-proxy`. The proxy and Hermes agent share a separate `cdp-client` network; `dashboard` and `anytype` are on neither CDP network. Browser-origin requests to CDP are rejected with `403`.
- Chromium receives both `HTTP_PROXY`/`HTTPS_PROXY` and an explicit `--proxy-server` flag. QUIC and non-proxied WebRTC UDP are disabled.
- **Important:** this is browser-level proxy enforcement, not a container-wide fail-closed firewall. Non-browser software inside the container retains a direct egress route.
- The remote desktop is hardened for a non-administrator keyboard user: terminal launchers, passwordless `sudo`, helper-app spawning, the Selkies command channel, files/apps UI controls, and unauthenticated sharing links are disabled or hidden. The hidden files control is not claimed as a protocol-level file-transfer kill switch. Clipboard sync remains available for pasting credentials.
- The container is not privileged, uses `no-new-privileges`, and mounts only its own browser profile. Treat the authenticated user as trusted with that profile; this is not a hostile-user sandbox.
- Default limits are 2 CPUs, 2 GiB RAM, and 2 GiB shared-memory capacity. Override them with `BROWSER_CPUS`, `BROWSER_MEMORY_LIMIT`, and `BROWSER_SHM_SIZE`.
- The default `BROWSER_IMAGE` is pinned to the tested multi-architecture image digest. Change it deliberately when upgrading, then rerun `make browser-check`.

## Multiple agents from the same repository

Each agent must use its own clone or Compose project, `COMPOSE_PROJECT_NAME`, `.env`, browser port, password, and `browser-data` directory. For example:

- Katya: `COMPOSE_PROJECT_NAME=hermes-katya`, `BROWSER_HTTPS_PORT=13001`, `BROWSER_PROFILE_DIR=./browser-data/hermes-katya`
- Olga: `COMPOSE_PROJECT_NAME=hermes-olga`, `BROWSER_HTTPS_PORT=13002`, `BROWSER_PROFILE_DIR=./browser-data/hermes-olga`

Both can use the same proxy endpoint if desired, while cookies and authenticated sessions remain isolated.
