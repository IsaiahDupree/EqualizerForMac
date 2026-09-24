"""Real TCP integration tests for the Sonance PowerZone client."""

from __future__ import annotations

import asyncio
import sys
from fnmatch import fnmatchcase
from pathlib import Path

COMPONENTS = Path(__file__).parents[1] / "custom_components"
SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(COMPONENTS))
sys.path.insert(0, str(SCRIPTS))

from powerzone_probe import probe
from sonance_eq.powerzone import (
    PowerZoneApiError,
    PowerZoneClient,
    PowerZoneNetworkError,
)


class PowerZoneTestService:
    """Actual line-based TCP server implementing the API contract under test."""

    def __init__(self, *, outputs: int = 4, eq_bands: int = 4) -> None:
        self.values: dict[str, str] = {
            "API_VERSION": '"1.5"',
            "SYSTEM.DEVICE.SERIAL": '"PZ-TEST-0001"',
            "SYSTEM.DEVICE.VENDOR_NAME": '"Sonance"',
            "SYSTEM.DEVICE.MODEL_NAME": '"PowerZone Connect 254"',
            "SYSTEM.DEVICE.FIRMWARE": '"1.8.4"',
            "SYSTEM.DEVICE.HWID": "254",
            "OUT.COUNT": str(outputs),
            "OUT.EQ.COUNT": str(eq_bands),
        }
        self.values.update(
            {
                f"OUT-{output_id}.NAME": f'"Zone {output_id}"'
                for output_id in range(1, outputs + 1)
            }
        )
        for output_id in range(1, outputs + 1):
            self.values[f"OUT-{output_id}.EQ.BYPASS"] = "1"
            for band_id in range(1, eq_bands + 1):
                prefix = f"OUT-{output_id}.EQ-{band_id}"
                self.values.update(
                    {
                        f"{prefix}.TYPE": "PARAMETRIC",
                        f"{prefix}.FREQ": "1000.00",
                        f"{prefix}.Q": "1.000",
                        f"{prefix}.GAIN": "0.00",
                        f"{prefix}.BYPASS": "0",
                    }
                )
        self.commands: list[str] = []

    async def handle(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        try:
            while raw := await reader.readline():
                command = raw.decode().strip()
                self.commands.append(command)
                verb, _, remainder = command.partition(" ")
                register, _, value = remainder.partition(" ")
                if verb == "GET" and (register in self.values or "*" in register):
                    for matched_register, matched_value in self.values.items():
                        if fnmatchcase(matched_register, register):
                            writer.write(
                                f"+{matched_register} {matched_value}\n".encode()
                            )
                    writer.write(f"*{command}\n".encode())
                elif verb == "SET" and register:
                    self.values[register] = value
                    writer.write(f"*{command}\n".encode())
                else:
                    writer.write(f"#{command}|E107: Unknown Parameter\n".encode())
                await writer.drain()
        finally:
            writer.close()
            await writer.wait_closed()


async def _with_server(service: PowerZoneTestService, scenario) -> None:
    server = await asyncio.start_server(service.handle, "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    try:
        client = PowerZoneClient("127.0.0.1", port)
        await scenario(client)
    finally:
        server.close()
        await server.wait_closed()


def test_validate_and_apply_preset_over_real_tcp() -> None:
    async def run() -> None:
        service = PowerZoneTestService()

        async def scenario(client: PowerZoneClient) -> None:
            preset_events: list[tuple[int, str]] = []
            unsubscribe = client.add_preset_listener(
                lambda output_id, preset: preset_events.append((output_id, preset))
            )
            info = await client.validate_server()
            assert info == {
                "api_version": "1.5",
                "serial": "PZ-TEST-0001",
                "outputs": 4,
                "eq_bands": 4,
                "manufacturer": "Sonance",
                "model": "PowerZone Connect 254",
                "firmware": "1.8.4",
                "hardware_id": "254",
            }
            assert await client.output_names() == {
                1: "Zone 1",
                2: "Zone 2",
                3: "Zone 3",
                4: "Zone 4",
            }

            applied = await client.apply_preset(2, "Vocal")
            assert applied["bands"] == 4
            assert preset_events == [(2, "Vocal")]
            assert service.values["OUT-2.EQ.BYPASS"] == "0"
            assert service.values["OUT-2.EQ-1.TYPE"] == "PARAMETRIC"
            gains = [
                float(service.values[f"OUT-2.EQ-{band}.GAIN"]) for band in range(1, 5)
            ]
            assert max(gains) == 0
            assert await client.read_preset(2) == "Vocal"
            service.values["OUT-2.EQ-1.GAIN"] = "-14.99"
            assert await client.read_preset(2) is None

            flat = await client.apply_preset(2, "Flat")
            assert flat["bands"] == 0
            assert service.values["OUT-2.EQ.BYPASS"] == "1"
            assert await client.read_preset(2) == "Flat"
            assert preset_events == [(2, "Vocal"), (2, "Flat")]
            unsubscribe()

            report = await probe(client.host, client.port, 1.0)
            assert report["status"] == "compatible"
            assert report["writes_performed"] is False
            assert report["outputs"][1] == {
                "id": 2,
                "name": "Zone 2",
                "managed_preset": "Flat",
            }

        await _with_server(service, scenario)

    asyncio.run(run())


def test_rejects_invalid_output_without_writing_eq() -> None:
    async def run() -> None:
        service = PowerZoneTestService(outputs=2)

        async def scenario(client: PowerZoneClient) -> None:
            try:
                await client.apply_preset(3, "Vocal")
            except PowerZoneApiError as error:
                assert "1-2 range" in str(error)
            else:
                raise AssertionError("Expected invalid output to fail")
            assert not any(command.startswith("SET") for command in service.commands)

        await _with_server(service, scenario)

    asyncio.run(run())


def test_rejects_public_powerzone_target_before_connecting() -> None:
    async def run() -> None:
        client = PowerZoneClient("1.1.1.1")
        try:
            await client.validate_server()
        except PowerZoneNetworkError as error:
            assert "unauthenticated" in str(error)
            return
        raise AssertionError("Expected a public target to be rejected")

    asyncio.run(run())
