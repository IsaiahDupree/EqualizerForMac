"""Preset selectors for Sonance PowerZone amplifier outputs."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, ClassVar

from homeassistant.components.select import SelectEntity
from homeassistant.core import callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.device_registry import DeviceInfo

from .const import DOMAIN
from .powerzone import PowerZoneApiError, PowerZoneClient
from .presets import PRESET_NAMES

if TYPE_CHECKING:
    from homeassistant.config_entries import ConfigEntry
    from homeassistant.core import HomeAssistant
    from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

_LOGGER = logging.getLogger(__name__)


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddConfigEntryEntitiesCallback,
) -> None:
    """Create one bridge-friendly preset selector for each amplifier output."""
    del hass
    client = entry.runtime_data
    if not isinstance(client, PowerZoneClient):
        return

    info = client.device_info or await client.validate_server()
    try:
        output_names = await client.output_names()
    except PowerZoneApiError:
        output_names = {
            output_id: f"Output {output_id}"
            for output_id in range(1, info["outputs"] + 1)
        }
    async_add_entities(
        [
            PowerZonePresetSelect(client, output_id, output_names[output_id])
            for output_id in range(1, info["outputs"] + 1)
        ],
        update_before_add=True,
    )


class PowerZonePresetSelect(SelectEntity):
    """A standard Home Assistant select backed by physical output EQ."""

    _attr_has_entity_name = True
    _attr_icon = "mdi:tune-variant"
    _attr_options: ClassVar[list[str]] = list(PRESET_NAMES)
    _attr_should_poll = False

    def __init__(
        self, client: PowerZoneClient, output_id: int, output_name: str
    ) -> None:
        """Initialize a physical output preset selector."""
        info = client.device_info
        if info is None:
            raise RuntimeError("PowerZone must be validated before creating entities")
        self._client = client
        self._output_id = output_id
        self._attr_name = f"{output_name} EQ preset"
        self._attr_unique_id = f"{info['serial']}-output-{output_id}-eq-preset"
        configuration_host = f"[{client.host}]" if ":" in client.host else client.host
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, info["serial"])},
            manufacturer=info["manufacturer"],
            model=info["model"],
            model_id=info["hardware_id"] or None,
            name=f"{info['model']} · {info['serial']}",
            serial_number=info["serial"],
            sw_version=info["firmware"] or None,
            configuration_url=f"http://{configuration_host}",
        )

    async def async_added_to_hass(self) -> None:
        """Listen for presets applied through the integration service action."""
        await super().async_added_to_hass()
        self.async_on_remove(
            self._client.add_preset_listener(self._async_preset_applied)
        )

    @callback
    def _async_preset_applied(self, output_id: int, option: str) -> None:
        """Synchronize state when another Sonance control surface writes EQ."""
        if output_id != self._output_id:
            return
        self._attr_available = True
        self._attr_current_option = option
        self.async_write_ha_state()

    async def async_update(self) -> None:
        """Read the initial EQ state without continuously polling the amplifier."""
        try:
            self._attr_current_option = await self._client.read_preset(self._output_id)
        except PowerZoneApiError as error:
            self._attr_available = False
            _LOGGER.debug(
                "Could not read PowerZone output %s preset: %s",
                self._output_id,
                error,
            )
        else:
            self._attr_available = True

    async def async_select_option(self, option: str) -> None:
        """Program the selected Sonance curve into this physical output."""
        try:
            await self._client.apply_preset(self._output_id, option)
        except PowerZoneApiError as error:
            self._attr_available = False
            self.async_write_ha_state()
            raise HomeAssistantError(str(error)) from error
