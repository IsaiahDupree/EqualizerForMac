"""Configuration flow for Sonance EQ."""

from __future__ import annotations

import hashlib
from typing import Any

import voluptuous as vol
from homeassistant import config_entries
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.selector import (
    TextSelector,
    TextSelectorConfig,
    TextSelectorType,
)

from .client import (
    MusicAssistantApiError,
    MusicAssistantAuthError,
    MusicAssistantClient,
    MusicAssistantVersionError,
)
from .const import CONF_TOKEN, CONF_URL, DEFAULT_MUSIC_ASSISTANT_URL, DOMAIN


class SonanceEqConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    """Set up Sonance EQ against a Music Assistant server."""

    VERSION = 1

    async def async_step_user(self, user_input: dict[str, Any] | None = None):
        """Collect and validate the local Music Assistant connection."""
        errors: dict[str, str] = {}
        if user_input is not None:
            url = user_input[CONF_URL].rstrip("/")
            client = MusicAssistantClient(
                async_get_clientsession(self.hass), url, user_input[CONF_TOKEN]
            )
            try:
                await client.validate_server()
            except MusicAssistantAuthError:
                errors["base"] = "invalid_auth"
            except MusicAssistantVersionError:
                errors["base"] = "unsupported_version"
            except MusicAssistantApiError:
                errors["base"] = "cannot_connect"
            else:
                server_id = hashlib.sha256(url.encode()).hexdigest()[:16]
                await self.async_set_unique_id(server_id)
                self._abort_if_unique_id_configured()
                return self.async_create_entry(
                    title=f"Sonance EQ · {url}",
                    data={CONF_URL: url, CONF_TOKEN: user_input[CONF_TOKEN]},
                )

        schema = vol.Schema(
            {
                vol.Required(
                    CONF_URL,
                    default=(user_input or {}).get(
                        CONF_URL, DEFAULT_MUSIC_ASSISTANT_URL
                    ),
                ): TextSelector(TextSelectorConfig(type=TextSelectorType.URL)),
                vol.Required(CONF_TOKEN): TextSelector(
                    TextSelectorConfig(type=TextSelectorType.PASSWORD)
                ),
            }
        )
        return self.async_show_form(step_id="user", data_schema=schema, errors=errors)
