# Headful Chromium browser

This optional module runs a persistent Chromium desktop through LinuxServer's browser-native Selkies interface. A person can complete logins or CAPTCHAs in the GUI, then Hermes continues in the same browser profile through an Nginx sidecar that exposes Chromium's loopback-only CDP inside the shared Compose network.

## Configure one deployment

Add these values to the deployment's ignored `.env` file:

```dotenv
COMPOSE_PROJECT_NAME=hermes-katya
BROWSER_USER=katya
BROWSER_PASSWORD=generate-a-long-random-password
BROWSER_PROXY_URL=http://proxy-host:8080
BROWSER_HTTPS_PORT=13001
BROWSER_PROFILE_DIR=./browser-data/hermes-katya
BROWSER_PUID=501
BROWSER_PGID=20
TZ=Europe/Moscow
```

Use a unique `COMPOSE_PROJECT_NAME`, `BROWSER_USER`, `BROWSER_PASSWORD`, `BROWSER_HTTPS_PORT`, and `BROWSER_PROFILE_DIR` in every deployment. The browser overlay refuses to render unless the project name, GUI port, and profile path are all explicit; this prevents projects launched from the same checkout from sharing containers, ports, cookies, or authenticated sessions.

The browser overlay sets `BROWSER_CDP_URL=http://browser:9223` on the Hermes `agent` service. `browser-cdp-proxy` shares the browser's network namespace, reaches Chromium on its loopback-only port, and rewrites CDP discovery URLs for the Compose service name. No tracked deployment config or manual `data/config.yaml` edit is required.

Generate a password with:

```bash
openssl rand -base64 24 | tr -d '/+=' | cut -c1-24
```

## Operate

```bash
make browser-up
make browser-status
make browser-logs
make browser-stop
```

Open `https://127.0.0.1:<BROWSER_HTTPS_PORT>/`. The interface uses a self-signed certificate, so the first visit shows a certificate warning.

`browser-cdp-proxy` has a Compose healthcheck against Chromium's CDP discovery endpoint. The `agent` starts only after that healthcheck passes; `make browser-status` shows the resulting health state. The browser profile lives entirely under `BROWSER_PROFILE_DIR`, so cookies and logins survive container recreation through the bind mount without initialization or persistence-test scripts.

## Isolation and security

- The GUI port binds to `127.0.0.1` by default. Do not change `BROWSER_BIND_HOST` to `0.0.0.0` for public exposure.
- Chromium keeps CDP on `127.0.0.1:9222` inside the browser network namespace. The `browser-cdp-proxy` sidecar shares that namespace, publishes only port `9223` to the Compose network, rewrites discovery WebSocket URLs, and rejects browser-origin requests with `403`. Neither CDP port is published on the host.
- The browser and Hermes agent intentionally share the default Compose network. This keeps the connection config-only and avoids a custom TCP relay, but it is not a hostile-browser network sandbox: the browser container can address other services on that network.
- For remote access, keep the loopback GUI bind and publish it through an authenticated private network such as Tailscale, or through an authenticated reverse proxy.
- Chromium receives both `HTTP_PROXY`/`HTTPS_PROXY` and an explicit `--proxy-server` flag. QUIC and non-proxied WebRTC UDP are disabled.
- **Important:** this is browser-level proxy enforcement, not a container-wide fail-closed firewall. Non-browser software inside the container retains a direct egress route.
- The remote desktop is hardened for a non-administrator keyboard user: terminal launchers, passwordless `sudo`, helper-app spawning, the Selkies command channel, files/apps UI controls, and unauthenticated sharing links are disabled or hidden. The hidden files control is not claimed as a protocol-level file-transfer kill switch. Clipboard sync remains available for pasting credentials.
- The container is not privileged, uses `no-new-privileges`, and mounts only its own browser profile. Treat the authenticated user as trusted with that profile.
- Default limits are 2 CPUs, 2 GiB RAM, and 2 GiB shared-memory capacity. Override them with `BROWSER_CPUS`, `BROWSER_MEMORY_LIMIT`, and `BROWSER_SHM_SIZE`.
- The default `BROWSER_IMAGE` is pinned to the tested multi-architecture image digest. Change it deliberately when upgrading, then verify the GUI and `browser-cdp-proxy` health state.

## Multiple agents from the same repository

Each agent must use its own clone or Compose project, `COMPOSE_PROJECT_NAME`, `.env`, browser port, password, and `browser-data` directory. For example:

- Katya: `COMPOSE_PROJECT_NAME=hermes-katya`, `BROWSER_HTTPS_PORT=13001`, `BROWSER_PROFILE_DIR=./browser-data/hermes-katya`
- Olga: `COMPOSE_PROJECT_NAME=hermes-olga`, `BROWSER_HTTPS_PORT=13002`, `BROWSER_PROFILE_DIR=./browser-data/hermes-olga`

Both can use the same proxy endpoint if desired, while cookies and authenticated sessions remain isolated.
