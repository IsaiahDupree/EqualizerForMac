"""Configuration flow for Sonance EQ."""

from __future__ import annotations

import hashlib
from typing import Any

import voluptuous as vol
from homeassistant import config_entries
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.selector import (
    NumberSelector,
    NumberSelectorConfig,
    NumberSelectorMode,
    SelectOptionDict,
    SelectSelector,
    SelectSelectorConfig,
    SelectSelectorMode,
    TextSelector,
    TextSelectorConfig,
    TextSelectorType,
)
from homeassistant.helpers.service_info.zeroconf import ZeroconfServiceInfo

from .client import (
    MusicAssistantApiError,
    MusicAssistantAuthError,
    MusicAssistantClient,
    MusicAssistantVersionError,
)
from .const import (
    BACKEND_HOME_ASSISTANT,
    BACKEND_MUSIC_ASSISTANT,
    BACKEND_POWERZONE,
    CONF_BACKEND,
    CONF_HOST,
    CONF_PORT,
    CONF_TOKEN,
    CONF_URL,
    DEFAULT_MUSIC_ASSISTANT_URL,
    DEFAULT_POWERZONE_PORT,
    DOMAIN,
)
from .powerzone import PowerZoneApiError, PowerZoneClient


class SonanceEqConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    """Set up routing, Music Assistant DSP, or direct PowerZone EQ."""

    VERSION = 1

    _discovered_powerzone: dict[str, Any] | None = None

    async def async_step_user(self, user_input: dict[str, Any] | None = None):
        """Choose an integration backend without making optional systems mandatory."""
        if user_input is not None:
            backend = user_input[CONF_BACKEND]
            if backend == BACKEND_HOME_ASSISTANT:
                await self.async_set_unique_id(BACKEND_HOME_ASSISTANT)
                self._abort_if_unique_id_configured()
                return self.async_create_entry(
                    title="Sonance EQ · Home Assistant",
                    data={CONF_BACKEND: BACKEND_HOME_ASSISTANT},
                )
            if backend == BACKEND_MUSIC_ASSISTANT:
                return await self.async_step_music_assistant()
            return await self.async_step_powerzone()

        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema(
                {
                    vol.Required(
                        CONF_BACKEND, default=BACKEND_HOME_ASSISTANT
                    ): SelectSelector(
                        SelectSelectorConfig(
                            options=[
                                SelectOptionDict(
                                    value=BACKEND_HOME_ASSISTANT,
                                    label="Home Assistant routing only",
                                ),
                                SelectOptionDict(
                                    value=BACKEND_MUSIC_ASSISTANT,
                                    label="Music Assistant DSP",
                                ),
                                SelectOptionDict(
                                    value=BACKEND_POWERZONE,
                                    label="Sonance PowerZone hardware",
                                ),
                            ],
                            mode=SelectSelectorMode.DROPDOWN,
                        )
                    )
                }
            ),
        )

    async def async_step_music_assistant(
        self, user_input: dict[str, Any] | None = None
    ):
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
                    data={
                        CONF_BACKEND: BACKEND_MUSIC_ASSISTANT,
                        CONF_URL: url,
                        CONF_TOKEN: user_input[CONF_TOKEN],
                    },
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
        return self.async_show_form(
            step_id="music_assistant", data_schema=schema, errors=errors
        )

    async def async_step_powerzone(self, user_input: dict[str, Any] | None = None):
        """Collect and validate one local Sonance PowerZone amplifier."""
        errors: dict[str, str] = {}
        if user_input is not None:
            host = user_input[CONF_HOST].strip().rstrip(".")
            port = int(user_input[CONF_PORT])
            client = PowerZoneClient(host, port)
            try:
                info = await client.validate_server()
            except PowerZoneApiError:
                errors["base"] = "cannot_connect_powerzone"
            else:
                await self.async_set_unique_id(f"powerzone-{info['serial']}")
                self._abort_if_unique_id_configured(
                    updates={CONF_HOST: host, CONF_PORT: port}
                )
                return self.async_create_entry(
                    title=f"Sonance PowerZone · {host}",
                    data={
                        CONF_BACKEND: BACKEND_POWERZONE,
                        CONF_HOST: host,
                        CONF_PORT: port,
                        "api_version": info["api_version"],
                        "serial": info["serial"],
                    },
                )

        schema = vol.Schema(
            {
                vol.Required(
                    CONF_HOST, default=(user_input or {}).get(CONF_HOST, "")
                ): TextSelector(TextSelectorConfig(type=TextSelectorType.TEXT)),
                vol.Required(
                    CONF_PORT,
                    default=(user_input or {}).get(CONF_PORT, DEFAULT_POWERZONE_PORT),
                ): NumberSelector(
                    NumberSelectorConfig(
                        min=1,
                        max=65535,
                        step=1,
                        mode=NumberSelectorMode.BOX,
                    )
                ),
            }
        )
        return self.async_show_form(
            step_id="powerzone", data_schema=schema, errors=errors
        )

    async def async_step_zeroconf(self, discovery_info: ZeroconfServiceInfo):
        """Discover a PowerZone amp through its official mDNS service."""
        host = discovery_info.host.rstrip(".")
        client = PowerZoneClient(host, DEFAULT_POWERZONE_PORT)
        try:
            info = await client.validate_server()
        except PowerZoneApiError:
            return self.async_abort(reason="cannot_connect_powerzone")

        await self.async_set_unique_id(f"powerzone-{info['serial']}")
        self._abort_if_unique_id_configured(
            updates={CONF_HOST: host, CONF_PORT: DEFAULT_POWERZONE_PORT},
            reload_on_update=True,
        )
        model = discovery_info.properties.get("model", "PowerZone")
        self._discovered_powerzone = {
            CONF_BACKEND: BACKEND_POWERZONE,
            CONF_HOST: host,
            CONF_PORT: DEFAULT_POWERZONE_PORT,
            "api_version": info["api_version"],
            "serial": info["serial"],
            "model": model,
        }
        self.context.update(
            {
                "title_placeholders": {"name": f"{model} · {host}"},
                "configuration_url": f"http://{host}",
            }
        )
        return await self.async_step_zeroconf_confirm()

    async def async_step_zeroconf_confirm(
        self, user_input: dict[str, Any] | None = None
    ):
        """Confirm a discovered local amplifier before enabling writes."""
        if self._discovered_powerzone is None:
            return self.async_abort(reason="cannot_connect_powerzone")
        if user_input is not None:
            return self.async_create_entry(
                title=(
                    "Sonance "
                    f"{self._discovered_powerzone['model']} · "
                    f"{self._discovered_powerzone[CONF_HOST]}"
                ),
                data={
                    key: value
                    for key, value in self._discovered_powerzone.items()
                    if key != "model"
                },
            )
        return self.async_show_form(
            step_id="zeroconf_confirm",
            description_placeholders={
                "name": str(self._discovered_powerzone["model"]),
                "host": str(self._discovered_powerzone[CONF_HOST]),
            },
        )
