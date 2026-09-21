"""Real TCP integration tests for the Sonance PowerZone client."""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

COMPONENTS = Path(__file__).parents[1] / "custom_components"
sys.path.insert(0, str(COMPONENTS))

from sonance_eq.powerzone import (  # noqa: E402
    PowerZoneApiError,
    PowerZoneClient,
    PowerZoneNetworkError,
)


class PowerZoneTestService:
    """Actual line-based TCP server implementing the API contract under test."""

    def __init__(self, *, outputs: int = 4, eq_bands: int = 4) -> None:
        self.values: dict[str, str] = {
            "API_VERSION": '"1.5"',
            "SETUP.DEVICE.SERIAL": '"PZ-TEST-0001"',
            "OUT.COUNT": str(outputs),
            "OUT.EQ.COUNT": str(eq_bands),
        }
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
                if verb == "GET" and register in self.values:
                    writer.write(f"+{register} {self.values[register]}\n".encode())
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
            info = await client.validate_server()
            assert info == {
                "api_version": "1.5",
                "serial": "PZ-TEST-0001",
                "outputs": 4,
                "eq_bands": 4,
            }

            applied = await client.apply_preset(2, "Vocal")
            assert applied["bands"] == 4
            assert service.values["OUT-2.EQ.BYPASS"] == "0"
            assert service.values["OUT-2.EQ-1.TYPE"] == "PARAMETRIC"
            gains = [
                float(service.values[f"OUT-2.EQ-{band}.GAIN"]) for band in range(1, 5)
            ]
            assert max(gains) == 0

            flat = await client.apply_preset(2, "Flat")
            assert flat["bands"] == 0
            assert service.values["OUT-2.EQ.BYPASS"] == "1"

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
