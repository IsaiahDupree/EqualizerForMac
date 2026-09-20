"""Real HTTP integration tests for the Sonance Music Assistant client."""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path
from typing import Any

from aiohttp import ClientSession, web
from aiohttp.test_utils import TestServer

COMPONENTS = Path(__file__).parents[1] / "custom_components"
sys.path.insert(0, str(COMPONENTS))

from sonance_eq.client import (  # noqa: E402
    MusicAssistantAuthError,
    MusicAssistantClient,
    MusicAssistantVersionError,
)


class MusicAssistantTestService:
    """Small actual aiohttp service implementing the commands under test."""

    def __init__(self, version: str = "2.10.4") -> None:
        self.version = version
        self.presets: dict[str, dict[str, Any]] = {}
        self.applied: list[tuple[str, str]] = []
        self.requests: list[dict[str, Any]] = []

    async def api(self, request: web.Request) -> web.Response:
        if request.headers.get("Authorization") != "Bearer local-test-token":
            return web.Response(status=401, text="Authentication required")
        message = await request.json()
        self.requests.append(message)
        command = message["command"]
        args = message.get("args", {})

        if command == "info":
            return web.json_response(
                {"server_version": self.version, "schema_version": 33}
            )
        if command == "config/dsp_presets/get":
            return web.json_response(list(self.presets.values()))
        if command == "config/dsp_presets/save":
            preset = args["preset"]
            preset_id = preset.get("preset_id") or f"preset{len(self.presets) + 1}"
            saved = {**preset, "preset_id": preset_id}
            self.presets[preset_id] = saved
            return web.json_response(saved)
        if command == "config/players/dsp/apply_preset":
            self.applied.append((args["player_id"], args["preset_id"]))
            return web.json_response(
                {"enabled": True, "preset_id": args["preset_id"], "filters": []}
            )
        return web.Response(status=400, text="Unknown command")


async def _with_server(service: MusicAssistantTestService, scenario) -> None:
    app = web.Application()
    app.router.add_post("/api", service.api)
    server = TestServer(app)
    await server.start_server()
    try:
        async with ClientSession() as session:
            client = MusicAssistantClient(
                session,
                str(server.make_url("/")).rstrip("/"),
                "local-test-token",
            )
            await scenario(client)
    finally:
        await server.close()


def test_validate_sync_and_apply_over_real_http() -> None:
    async def run() -> None:
        service = MusicAssistantTestService()

        async def scenario(client: MusicAssistantClient) -> None:
            info = await client.validate_server()
            assert info["server_version"] == "2.10.4"
            synced = await client.sync_sonance_presets()
            assert "Flat" in synced
            assert "Bass Boost" in synced
            assert len(service.presets) == 9

            state = await client.apply_preset("living_room", "Vocal")
            assert state["preset_id"] == synced["Vocal"]
            assert service.applied == [("living_room", synced["Vocal"])]
            assert all(message.get("message_id") for message in service.requests)

        await _with_server(service, scenario)

    asyncio.run(run())


def test_sync_is_an_upsert_not_a_duplicate() -> None:
    async def run() -> None:
        service = MusicAssistantTestService()

        async def scenario(client: MusicAssistantClient) -> None:
            first = await client.sync_sonance_presets()
            second = await client.sync_sonance_presets()
            assert first == second
            assert len(service.presets) == 9

        await _with_server(service, scenario)

    asyncio.run(run())


def test_rejects_music_assistant_without_required_dsp_contract() -> None:
    async def run() -> None:
        service = MusicAssistantTestService(version="2.10.0")

        async def scenario(client: MusicAssistantClient) -> None:
            try:
                await client.validate_server()
            except MusicAssistantVersionError:
                return
            raise AssertionError(
                "Expected an unsupported Music Assistant version to be rejected"
            )

        await _with_server(service, scenario)

    asyncio.run(run())


def test_rejects_invalid_token() -> None:
    async def run() -> None:
        service = MusicAssistantTestService()
        app = web.Application()
        app.router.add_post("/api", service.api)
        server = TestServer(app)
        await server.start_server()
        try:
            async with ClientSession() as session:
                client = MusicAssistantClient(
                    session, str(server.make_url("/")).rstrip("/"), "wrong-token"
                )
                try:
                    await client.validate_server()
                except MusicAssistantAuthError:
                    return
                raise AssertionError("Expected invalid auth to fail")
        finally:
            await server.close()

    asyncio.run(run())
