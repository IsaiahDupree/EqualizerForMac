"""Authenticated client for Music Assistant's local JSON API."""

from __future__ import annotations

import asyncio
from copy import deepcopy
import re
from typing import Any
from uuid import uuid4

from aiohttp import ClientError, ClientSession, ClientTimeout

from .presets import SONANCE_PRESETS, preset_payload

MINIMUM_MUSIC_ASSISTANT_VERSION = (2, 10, 1)


class MusicAssistantApiError(Exception):
    """Music Assistant could not complete an API request."""


class MusicAssistantAuthError(MusicAssistantApiError):
    """Music Assistant rejected the configured token."""


class MusicAssistantVersionError(MusicAssistantApiError):
    """Music Assistant is too old for the safe Sonance integration path."""


class MusicAssistantClient:
    """Small, typed-enough client for the Music Assistant commands Sonance needs."""

    def __init__(
        self,
        session: ClientSession,
        base_url: str,
        token: str,
        *,
        timeout_seconds: float = 10.0,
    ) -> None:
        self._session = session
        self.base_url = base_url.rstrip("/")
        self._token = token.strip()
        self._timeout = ClientTimeout(total=timeout_seconds)

    async def call(self, command: str, args: dict[str, Any] | None = None) -> Any:
        """Execute one authenticated Music Assistant JSON API command."""
        payload: dict[str, Any] = {
            "command": command,
            "message_id": str(uuid4()),
        }
        if args is not None:
            payload["args"] = args

        try:
            async with self._session.post(
                f"{self.base_url}/api",
                json=payload,
                headers={"Authorization": f"Bearer {self._token}"},
                timeout=self._timeout,
            ) as response:
                body = await response.text()
                if response.status in (401, 403):
                    raise MusicAssistantAuthError(
                        "Music Assistant rejected the token or its DSP permissions"
                    )
                if response.status >= 400:
                    detail = body.strip() or response.reason
                    raise MusicAssistantApiError(
                        f"Music Assistant {command} failed ({response.status}): {detail}"
                    )
                try:
                    return await response.json()
                except (ValueError, TypeError) as error:
                    raise MusicAssistantApiError(
                        f"Music Assistant {command} returned invalid JSON"
                    ) from error
        except asyncio.TimeoutError as error:
            raise MusicAssistantApiError("Music Assistant timed out") from error
        except ClientError as error:
            raise MusicAssistantApiError(
                f"Cannot reach Music Assistant: {error}"
            ) from error

    async def get_presets(self) -> list[dict[str, Any]]:
        """Return the persisted Music Assistant DSP presets."""
        result = await self.call("config/dsp_presets/get")
        if not isinstance(result, list):
            raise MusicAssistantApiError(
                "Music Assistant returned an invalid preset list"
            )
        return result

    async def validate_server(self) -> dict[str, Any]:
        """Verify API access and require the patched Music Assistant release."""
        info = await self.call("info")
        if not isinstance(info, dict):
            raise MusicAssistantApiError(
                "Music Assistant returned invalid server information"
            )
        version_text = str(info.get("server_version", ""))
        version = tuple(int(part) for part in re.findall(r"\d+", version_text)[:3])
        if len(version) < 3 or version < MINIMUM_MUSIC_ASSISTANT_VERSION:
            raise MusicAssistantVersionError(
                "Music Assistant 2.10.1 or newer is required; update the server before connecting"
            )
        await self.get_presets()
        return info

    async def save_preset(self, preset: dict[str, Any]) -> dict[str, Any]:
        """Create or update one Music Assistant DSP preset."""
        result = await self.call("config/dsp_presets/save", {"preset": preset})
        if not isinstance(result, dict) or not result.get("preset_id"):
            raise MusicAssistantApiError(
                "Music Assistant did not return a saved preset ID"
            )
        return result

    async def sync_sonance_presets(self) -> dict[str, str]:
        """Upsert the complete Sonance preset library and return short name to ID."""
        existing = {item.get("name"): item for item in await self.get_presets()}
        synced: dict[str, str] = {}
        for source in SONANCE_PRESETS:
            payload = deepcopy(source)
            if current := existing.get(source["name"]):
                payload["preset_id"] = current.get("preset_id")
            saved = await self.save_preset(payload)
            short_name = source["name"].removeprefix("Sonance · ")
            synced[short_name] = saved["preset_id"]
        return synced

    async def ensure_preset(self, name: str) -> str:
        """Ensure one Sonance preset exists and return its Music Assistant ID."""
        desired = preset_payload(name)
        for current in await self.get_presets():
            if current.get("name") != desired["name"]:
                continue
            desired["preset_id"] = current.get("preset_id")
            if current.get("config") == desired["config"] and current.get("preset_id"):
                return current["preset_id"]
            return (await self.save_preset(desired))["preset_id"]
        return (await self.save_preset(desired))["preset_id"]

    async def apply_preset(self, player_id: str, name: str) -> dict[str, Any]:
        """Apply a Sonance curve to one Music Assistant player."""
        preset_id = await self.ensure_preset(name)
        result = await self.call(
            "config/players/dsp/apply_preset",
            {"player_id": player_id, "preset_id": preset_id},
        )
        if not isinstance(result, dict):
            raise MusicAssistantApiError(
                "Music Assistant returned an invalid DSP state"
            )
        return result
