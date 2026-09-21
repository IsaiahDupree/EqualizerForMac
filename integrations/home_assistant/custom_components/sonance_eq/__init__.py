"""Sonance EQ integration for Home Assistant and Music Assistant."""

from __future__ import annotations

from typing import TYPE_CHECKING

from .client import (
    MusicAssistantApiError,
    MusicAssistantAuthError,
    MusicAssistantClient,
    MusicAssistantVersionError,
)
from .const import (
    ATTR_OUTPUT_ID,
    ATTR_ENTITY_ID,
    ATTR_MEDIA_ID,
    ATTR_MEDIA_TYPE,
    ATTR_PRESET,
    BACKEND_HOME_ASSISTANT,
    BACKEND_MUSIC_ASSISTANT,
    BACKEND_POWERZONE,
    CONF_BACKEND,
    CONF_ENTRY_ID,
    CONF_HOST,
    CONF_PORT,
    CONF_TOKEN,
    CONF_URL,
    DOMAIN,
    MASS_DOMAIN,
    MASS_UNIQUE_ID_PREFIX,
    SERVICE_APPLY_PRESET,
    SERVICE_APPLY_POWERZONE_PRESET,
    SERVICE_SEND_TO_DEVICE,
    SERVICE_SYNC_PRESETS,
)
from .powerzone import PowerZoneApiError, PowerZoneClient
from .presets import PRESET_NAMES

if TYPE_CHECKING:
    from homeassistant.config_entries import ConfigEntry
    from homeassistant.core import HomeAssistant, ServiceCall


def _configured_music_client(
    hass: HomeAssistant, entry_id: str | None
) -> MusicAssistantClient:
    """Resolve one loaded client, requiring a choice only when ambiguous."""
    entries = [
        entry
        for entry in hass.config_entries.async_entries(DOMAIN)
        if isinstance(entry.runtime_data, MusicAssistantClient)
    ]
    if entry_id:
        entries = [entry for entry in entries if entry.entry_id == entry_id]
    if len(entries) != 1:
        from homeassistant.exceptions import ServiceValidationError

        raise ServiceValidationError(
            "Choose config_entry_id" if entries else "No loaded Sonance EQ integration"
        )
    client = entries[0].runtime_data
    if not isinstance(client, MusicAssistantClient):
        from homeassistant.exceptions import ServiceValidationError

        raise ServiceValidationError("Sonance EQ is not connected")
    return client


def _configured_powerzone_client(
    hass: HomeAssistant, entry_id: str | None
) -> PowerZoneClient:
    """Resolve one loaded PowerZone client, requiring a choice when ambiguous."""
    entries = [
        entry
        for entry in hass.config_entries.async_entries(DOMAIN)
        if isinstance(entry.runtime_data, PowerZoneClient)
    ]
    if entry_id:
        entries = [entry for entry in entries if entry.entry_id == entry_id]
    if len(entries) != 1:
        from homeassistant.exceptions import ServiceValidationError

        raise ServiceValidationError(
            "Choose config_entry_id"
            if entries
            else "No loaded Sonance PowerZone connection"
        )
    client = entries[0].runtime_data
    if not isinstance(client, PowerZoneClient):
        from homeassistant.exceptions import ServiceValidationError

        raise ServiceValidationError("Sonance PowerZone is not connected")
    return client


def _mass_player_id(hass: HomeAssistant, entity_id: str) -> str:
    """Translate a Music Assistant media_player entity into its player ID."""
    from homeassistant.exceptions import ServiceValidationError
    from homeassistant.helpers import entity_registry as er

    entity = er.async_get(hass).async_get(entity_id)
    if entity is None or entity.platform != MASS_DOMAIN:
        raise ServiceValidationError(
            "EQ presets require a Music Assistant media player. "
            "A plain Cast entity can still play media, but direct Cast bypasses DSP."
        )
    if not entity.unique_id.startswith(MASS_UNIQUE_ID_PREFIX):
        raise ServiceValidationError(
            "The selected Music Assistant player has no usable player ID"
        )
    return entity.unique_id.removeprefix(MASS_UNIQUE_ID_PREFIX)


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Connect Sonance EQ and register its Home Assistant actions."""
    import voluptuous as vol
    from homeassistant.helpers import config_validation as cv
    from homeassistant.helpers.aiohttp_client import async_get_clientsession

    # Entries created by 0.1 did not store a backend and were all Music Assistant.
    backend = entry.data.get(CONF_BACKEND, BACKEND_MUSIC_ASSISTANT)
    if backend == BACKEND_MUSIC_ASSISTANT:
        entry.runtime_data = MusicAssistantClient(
            async_get_clientsession(hass), entry.data[CONF_URL], entry.data[CONF_TOKEN]
        )
        try:
            await entry.runtime_data.validate_server()
        except MusicAssistantAuthError as error:
            from homeassistant.exceptions import ConfigEntryAuthFailed

            raise ConfigEntryAuthFailed(str(error)) from error
        except MusicAssistantVersionError as error:
            from homeassistant.exceptions import ConfigEntryError

            raise ConfigEntryError(str(error)) from error
        except MusicAssistantApiError as error:
            from homeassistant.exceptions import ConfigEntryNotReady

            raise ConfigEntryNotReady(str(error)) from error
    elif backend == BACKEND_POWERZONE:
        entry.runtime_data = PowerZoneClient(
            entry.data[CONF_HOST], entry.data.get(CONF_PORT, 7621)
        )
        try:
            await entry.runtime_data.validate_server()
        except PowerZoneApiError as error:
            from homeassistant.exceptions import ConfigEntryNotReady

            raise ConfigEntryNotReady(str(error)) from error
    elif backend == BACKEND_HOME_ASSISTANT:
        entry.runtime_data = BACKEND_HOME_ASSISTANT
    else:
        from homeassistant.exceptions import ConfigEntryError

        raise ConfigEntryError(f"Unsupported Sonance EQ backend: {backend}")

    if hass.services.has_service(DOMAIN, SERVICE_SYNC_PRESETS):
        return True

    base_schema = {vol.Optional(CONF_ENTRY_ID): cv.string}

    async def handle_sync(call: ServiceCall) -> None:
        client = _configured_music_client(hass, call.data.get(CONF_ENTRY_ID))
        try:
            await client.sync_sonance_presets()
        except MusicAssistantApiError as error:
            from homeassistant.exceptions import HomeAssistantError

            raise HomeAssistantError(str(error)) from error

    async def handle_apply(call: ServiceCall) -> None:
        client = _configured_music_client(hass, call.data.get(CONF_ENTRY_ID))
        player_id = _mass_player_id(hass, call.data[ATTR_ENTITY_ID])
        try:
            await client.apply_preset(player_id, call.data[ATTR_PRESET])
        except MusicAssistantApiError as error:
            from homeassistant.exceptions import HomeAssistantError

            raise HomeAssistantError(str(error)) from error

    async def handle_apply_powerzone(call: ServiceCall) -> None:
        client = _configured_powerzone_client(hass, call.data.get(CONF_ENTRY_ID))
        try:
            await client.apply_preset(call.data[ATTR_OUTPUT_ID], call.data[ATTR_PRESET])
        except PowerZoneApiError as error:
            from homeassistant.exceptions import HomeAssistantError

            raise HomeAssistantError(str(error)) from error

    async def handle_send(call: ServiceCall) -> None:
        entity_id = call.data[ATTR_ENTITY_ID]
        preset = call.data.get(ATTR_PRESET)
        if preset:
            client = _configured_music_client(hass, call.data.get(CONF_ENTRY_ID))
            player_id = _mass_player_id(hass, entity_id)
            try:
                await client.apply_preset(player_id, preset)
            except MusicAssistantApiError as error:
                from homeassistant.exceptions import HomeAssistantError

                raise HomeAssistantError(str(error)) from error

        await hass.services.async_call(
            "media_player",
            "play_media",
            {
                "entity_id": entity_id,
                "media_content_id": call.data[ATTR_MEDIA_ID],
                "media_content_type": call.data.get(ATTR_MEDIA_TYPE, "music"),
            },
            blocking=True,
            context=call.context,
        )

    hass.services.async_register(
        DOMAIN,
        SERVICE_SYNC_PRESETS,
        handle_sync,
        schema=vol.Schema(base_schema),
    )
    hass.services.async_register(
        DOMAIN,
        SERVICE_APPLY_PRESET,
        handle_apply,
        schema=vol.Schema(
            {
                **base_schema,
                vol.Required(ATTR_ENTITY_ID): cv.entity_id,
                vol.Required(ATTR_PRESET): vol.In(PRESET_NAMES),
            }
        ),
    )
    hass.services.async_register(
        DOMAIN,
        SERVICE_APPLY_POWERZONE_PRESET,
        handle_apply_powerzone,
        schema=vol.Schema(
            {
                **base_schema,
                vol.Required(ATTR_OUTPUT_ID): vol.All(
                    vol.Coerce(int), vol.Range(min=1)
                ),
                vol.Required(ATTR_PRESET): vol.In(PRESET_NAMES),
            }
        ),
    )
    hass.services.async_register(
        DOMAIN,
        SERVICE_SEND_TO_DEVICE,
        handle_send,
        schema=vol.Schema(
            {
                **base_schema,
                vol.Required(ATTR_ENTITY_ID): cv.entity_id,
                vol.Required(ATTR_MEDIA_ID): cv.string,
                vol.Optional(ATTR_MEDIA_TYPE, default="music"): cv.string,
                vol.Optional(ATTR_PRESET): vol.In(PRESET_NAMES),
            }
        ),
    )
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Unload one Sonance EQ connection."""
    entry.runtime_data = None
    if len(hass.config_entries.async_entries(DOMAIN)) <= 1:
        for service in (
            SERVICE_SYNC_PRESETS,
            SERVICE_APPLY_PRESET,
            SERVICE_APPLY_POWERZONE_PRESET,
            SERVICE_SEND_TO_DEVICE,
        ):
            hass.services.async_remove(DOMAIN, service)
    return True
