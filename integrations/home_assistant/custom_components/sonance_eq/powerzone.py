"""Local client for the official Sonance PowerZone Connect installer API."""

from __future__ import annotations

import asyncio
from collections.abc import Callable
from contextlib import suppress
import ipaddress
import socket
from typing import Any, Iterable

from .presets import PRESET_NAMES, powerzone_bands

MAX_COMMAND_BYTES = 8192
LOCAL_NETWORKS = (
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
    ipaddress.ip_network("fc00::/7"),
)


class PowerZoneApiError(Exception):
    """A PowerZone amplifier could not complete a local API request."""


class PowerZoneNetworkError(PowerZoneApiError):
    """The PowerZone target is not a safe local-network address."""


class PowerZoneClient:
    """Client for the line-based PowerZone API on TCP port 7621."""

    def __init__(
        self,
        host: str,
        port: int = 7621,
        *,
        timeout_seconds: float = 5.0,
    ) -> None:
        normalized_host = host.strip().rstrip(".")
        if normalized_host.startswith("[") and normalized_host.endswith("]"):
            normalized_host = normalized_host[1:-1]
        self.host = normalized_host
        self.port = int(port)
        self._timeout_seconds = timeout_seconds
        self._command_lock = asyncio.Lock()
        self.device_info: dict[str, Any] | None = None
        self._preset_listeners: set[Callable[[int, str], None]] = set()

    def add_preset_listener(
        self, listener: Callable[[int, str], None]
    ) -> Callable[[], None]:
        """Subscribe to presets applied through any Home Assistant surface."""
        self._preset_listeners.add(listener)

        def unsubscribe() -> None:
            self._preset_listeners.discard(listener)

        return unsubscribe

    def _notify_preset_applied(self, output_id: int, name: str) -> None:
        """Keep standard select entities synchronized with service actions."""
        for listener in tuple(self._preset_listeners):
            listener(output_id, name)

    async def _validated_local_addresses(
        self,
    ) -> list[tuple[int, int, int, tuple[Any, ...]]]:
        """Resolve once and return only socket addresses on an explicit local range."""
        if not self.host or any(char in self.host for char in "/@"):
            raise PowerZoneNetworkError("Enter a local hostname or IP address only")
        if not 1 <= self.port <= 65535:
            raise PowerZoneNetworkError("PowerZone port must be between 1 and 65535")

        try:
            addresses = await asyncio.get_running_loop().getaddrinfo(
                self.host,
                self.port,
                type=socket.SOCK_STREAM,
            )
        except OSError as error:
            raise PowerZoneNetworkError(
                f"Cannot resolve PowerZone host {self.host}: {error}"
            ) from error

        if not addresses:
            raise PowerZoneNetworkError(f"Cannot resolve PowerZone host {self.host}")
        validated: list[tuple[int, int, int, tuple[Any, ...]]] = []
        for family, socket_type, protocol, _, socket_address in addresses:
            ip = ipaddress.ip_address(socket_address[0].split("%", 1)[0])
            if not (
                ip.is_link_local
                or ip.is_loopback
                or any(ip in network for network in LOCAL_NETWORKS)
            ):
                raise PowerZoneNetworkError(
                    "PowerZone's control API is unauthenticated; use a private or "
                    "link-local address and never port-forward it"
                )
            validated.append((family, socket_type, protocol, socket_address))
        return validated

    @staticmethod
    def _validate_command(command: str) -> str:
        normalized = command.strip()
        if not normalized or "\n" in normalized or "\r" in normalized:
            raise PowerZoneApiError("PowerZone commands must be one non-empty line")
        if len(normalized.encode("utf-8")) > MAX_COMMAND_BYTES:
            raise PowerZoneApiError("PowerZone command exceeds the API size limit")
        return normalized

    @staticmethod
    def _decode_value(value: str) -> Any:
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] == '"':
            return value[1:-1]
        try:
            return int(value)
        except ValueError:
            try:
                return float(value)
            except ValueError:
                return value

    async def execute(self, commands: Iterable[str]) -> list[dict[str, Any]]:
        """Run commands on one real TCP session and return each command's values."""
        normalized = [self._validate_command(command) for command in commands]
        if not normalized:
            return []
        addresses = await self._validated_local_addresses()

        # Pin the connection to an address that was already validated. Resolving
        # the hostname again inside open_connection would permit a DNS-rebinding
        # race between validation and connection. The lock also prevents two HA
        # service calls from interleaving separate output-EQ transactions.
        async with self._command_lock:
            connection_error: Exception | None = None
            reader: asyncio.StreamReader | None = None
            writer: asyncio.StreamWriter | None = None
            for family, socket_type, protocol, socket_address in addresses:
                transport_socket = socket.socket(family, socket_type, protocol)
                transport_socket.setblocking(False)
                try:
                    await asyncio.wait_for(
                        asyncio.get_running_loop().sock_connect(
                            transport_socket, socket_address
                        ),
                        timeout=self._timeout_seconds,
                    )
                    reader, writer = await asyncio.open_connection(
                        sock=transport_socket
                    )
                    break
                except (OSError, asyncio.TimeoutError) as error:
                    connection_error = error
                    transport_socket.close()

            if reader is None or writer is None:
                raise PowerZoneApiError(
                    f"Cannot reach PowerZone at {self.host}:{self.port}: "
                    f"{connection_error or 'no local address'}"
                ) from connection_error

            responses: list[dict[str, Any]] = []
            try:
                for command in normalized:
                    writer.write(f"{command}\n".encode())
                    await asyncio.wait_for(
                        writer.drain(), timeout=self._timeout_seconds
                    )
                    values: dict[str, Any] = {}
                    while True:
                        raw = await asyncio.wait_for(
                            reader.readline(), timeout=self._timeout_seconds
                        )
                        if not raw:
                            raise PowerZoneApiError(
                                f"PowerZone closed the connection during {command}"
                            )
                        line = raw.decode("utf-8", errors="strict").rstrip("\r\n")
                        if line == f"*{command}":
                            responses.append(values)
                            break
                        if line.startswith("#"):
                            detail = line.partition("|")[2] or line[1:]
                            raise PowerZoneApiError(
                                f"PowerZone rejected {command}: {detail}"
                            )
                        if line.startswith("+"):
                            register, separator, value = line[1:].partition(" ")
                            if separator:
                                values[register] = self._decode_value(value)
            except (OSError, UnicodeError, asyncio.TimeoutError) as error:
                raise PowerZoneApiError(
                    f"PowerZone communication failed at {self.host}:{self.port}: "
                    f"{error}"
                ) from error
            finally:
                writer.close()
                with suppress(OSError):
                    await writer.wait_closed()
            return responses

    async def command(self, command: str) -> dict[str, Any]:
        """Run one command."""
        return (await self.execute([command]))[0]

    async def validate_server(self) -> dict[str, Any]:
        """Verify that the target exposes the required output-EQ API contract."""
        api, device, outputs, eq_bands = await self.execute(
            [
                "GET API_VERSION",
                "GET SYSTEM.DEVICE.*",
                "GET OUT.COUNT",
                "GET OUT.EQ.COUNT",
            ]
        )
        try:
            info = {
                "api_version": str(api["API_VERSION"]),
                "serial": str(device["SYSTEM.DEVICE.SERIAL"]),
                "outputs": int(outputs["OUT.COUNT"]),
                "eq_bands": int(eq_bands["OUT.EQ.COUNT"]),
                "manufacturer": str(device.get("SYSTEM.DEVICE.VENDOR_NAME", "Sonance")),
                "model": str(device.get("SYSTEM.DEVICE.MODEL_NAME", "PowerZone")),
                "firmware": str(device.get("SYSTEM.DEVICE.FIRMWARE", "")),
                "hardware_id": str(device.get("SYSTEM.DEVICE.HWID", "")),
            }
        except (KeyError, TypeError, ValueError) as error:
            raise PowerZoneApiError(
                "The device did not return the required PowerZone EQ registers"
            ) from error
        if not info["serial"]:
            raise PowerZoneApiError("The PowerZone device returned no serial number")
        if info["outputs"] < 1 or info["eq_bands"] < 1:
            raise PowerZoneApiError("The PowerZone device exposes no usable output EQ")
        self.device_info = info
        return info

    async def read_preset(self, output_id: int) -> str | None:
        """Identify the Sonance preset currently programmed on one output.

        Return ``None`` when the user EQ does not match a managed preset. This
        makes external installer changes visible as an unknown select state
        instead of mislabeling them as one of our curves.
        """
        info = self.device_info or await self.validate_server()
        output_id = int(output_id)
        if not 1 <= output_id <= info["outputs"]:
            raise PowerZoneApiError(
                f"Output {output_id} is outside this amplifier's 1-{info['outputs']} range"
            )

        root = f"OUT-{output_id}.EQ"
        commands = [f"GET {root}.BYPASS"]
        for band_id in range(1, info["eq_bands"] + 1):
            prefix = f"{root}-{band_id}"
            commands.extend(
                (
                    f"GET {prefix}.TYPE",
                    f"GET {prefix}.FREQ",
                    f"GET {prefix}.Q",
                    f"GET {prefix}.GAIN",
                    f"GET {prefix}.BYPASS",
                )
            )
        responses = await self.execute(commands)
        values = {
            register: value
            for response in responses
            for register, value in response.items()
        }
        if self._as_bool(values.get(f"{root}.BYPASS")):
            return "Flat"

        for name in PRESET_NAMES:
            if name == "Flat":
                continue
            expected = powerzone_bands(name, info["eq_bands"])
            if self._matches_bands(root, expected, info["eq_bands"], values):
                return name
        return None

    @staticmethod
    def _as_bool(value: Any) -> bool:
        """Interpret the API's integer and textual boolean encodings."""
        if isinstance(value, str):
            return value.strip().lower() in {"1", "true", "on", "yes"}
        return bool(value)

    @classmethod
    def _matches_bands(
        cls,
        root: str,
        expected: list[dict[str, float | str]],
        band_count: int,
        values: dict[str, Any],
    ) -> bool:
        """Compare an amplifier snapshot with one managed curve."""
        for band_id in range(1, band_count + 1):
            prefix = f"{root}-{band_id}"
            if band_id > len(expected):
                if not cls._as_bool(values.get(f"{prefix}.BYPASS")):
                    return False
                continue

            band = expected[band_id - 1]
            if cls._as_bool(values.get(f"{prefix}.BYPASS")):
                return False
            if values.get(f"{prefix}.TYPE") != band["type"]:
                return False
            try:
                if (
                    abs(float(values[f"{prefix}.FREQ"]) - float(band["frequency"]))
                    > 0.1
                ):
                    return False
                if abs(float(values[f"{prefix}.Q"]) - float(band["q"])) > 0.01:
                    return False
                if abs(float(values[f"{prefix}.GAIN"]) - float(band["gain"])) > 0.05:
                    return False
            except (KeyError, TypeError, ValueError):
                return False
        return True

    async def output_names(self) -> dict[int, str]:
        """Return the installer-defined name for each physical output."""
        info = self.device_info or await self.validate_server()
        response = await self.command("GET OUT-*.NAME")
        names: dict[int, str] = {}
        for output_id in range(1, info["outputs"] + 1):
            names[output_id] = str(
                response.get(f"OUT-{output_id}.NAME", f"Output {output_id}")
            )
        return names

    async def apply_preset(self, output_id: int, name: str) -> dict[str, Any]:
        """Apply a headroom-safe Sonance curve to one user output-EQ stage."""
        info = self.device_info or await self.validate_server()
        output_id = int(output_id)
        if not 1 <= output_id <= info["outputs"]:
            raise PowerZoneApiError(
                f"Output {output_id} is outside this amplifier's 1-{info['outputs']} range"
            )

        root = f"OUT-{output_id}.EQ"
        bands = powerzone_bands(name, info["eq_bands"])
        if not bands:
            await self.command(f"SET {root}.BYPASS 1")
            self._notify_preset_applied(output_id, name)
            return {**info, "output_id": output_id, "preset": name, "bands": 0}

        # Keep the user EQ bypassed while individual registers are changing. If
        # the transaction fails, the amp remains safely bypassed, never half-EQ'd.
        commands = [f"SET {root}.BYPASS 1"]
        for band_id, band in enumerate(bands, start=1):
            prefix = f"{root}-{band_id}"
            commands.extend(
                (
                    f"SET {prefix}.TYPE {band['type']}",
                    f"SET {prefix}.FREQ {band['frequency']:.2f}",
                    f"SET {prefix}.Q {band['q']:.3f}",
                    f"SET {prefix}.GAIN {band['gain']:.2f}",
                    f"SET {prefix}.BYPASS 0",
                )
            )
        for band_id in range(len(bands) + 1, info["eq_bands"] + 1):
            commands.append(f"SET {root}-{band_id}.BYPASS 1")
        commands.append(f"SET {root}.BYPASS 0")
        await self.execute(commands)
        self._notify_preset_applied(output_id, name)
        return {
            **info,
            "output_id": output_id,
            "preset": name,
            "bands": len(bands),
        }
