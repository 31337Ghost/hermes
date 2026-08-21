#!/usr/bin/env python3
"""Verify Chromium CDP and country egress without touching user tabs."""

import asyncio
import json
import os
import time
import urllib.request

import websockets


CDP_VERSION_URL = "http://cdp-proxy:9223/json/version"
COUNTRY_URL = os.environ["COUNTRY_URL"]


async def main() -> None:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(CDP_VERSION_URL, timeout=5) as response:
        info = json.load(response)

    context_id = None
    target_id = None
    async with websockets.connect(info["webSocketDebuggerUrl"], open_timeout=5) as socket:
        next_id = 0

        async def command(method: str, params: dict | None = None, session_id: str | None = None) -> dict:
            nonlocal next_id
            next_id += 1
            command_id = next_id
            message: dict = {"id": command_id, "method": method}
            if params:
                message["params"] = params
            if session_id:
                message["sessionId"] = session_id
            await socket.send(json.dumps(message))

            while True:
                reply = json.loads(await asyncio.wait_for(socket.recv(), timeout=10))
                if reply.get("id") != command_id:
                    continue
                if "error" in reply:
                    raise RuntimeError(reply["error"])
                return reply.get("result", {})

        await command("Browser.getVersion")
        try:
            context = await command("Target.createBrowserContext")
            context_id = context["browserContextId"]
            target = await command(
                "Target.createTarget",
                {"url": "about:blank", "browserContextId": context_id, "background": True},
            )
            target_id = target["targetId"]
            attached = await command("Target.attachToTarget", {"targetId": target_id, "flatten": True})
            session_id = attached["sessionId"]
            await command("Page.enable", session_id=session_id)
            await command("Runtime.enable", session_id=session_id)
            await command("Page.navigate", {"url": COUNTRY_URL}, session_id=session_id)

            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                evaluated = await command(
                    "Runtime.evaluate",
                    {
                        "expression": "({ready: document.readyState, text: document.body ? document.body.innerText : ''})",
                        "returnByValue": True,
                    },
                    session_id=session_id,
                )
                value = evaluated.get("result", {}).get("value", {})
                text = str(value.get("text", "")).strip()
                if value.get("ready") == "complete" and text:
                    print(text)
                    return
                await asyncio.sleep(0.5)
            raise TimeoutError("country page did not finish loading")
        finally:
            if target_id:
                await command("Target.closeTarget", {"targetId": target_id})
            if context_id:
                await command("Target.disposeBrowserContext", {"browserContextId": context_id})


if __name__ == "__main__":
    asyncio.run(main())
