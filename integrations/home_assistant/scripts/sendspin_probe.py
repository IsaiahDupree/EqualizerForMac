#!/usr/bin/env python3
"""Hardware acceptance probe for a private-LAN Sendspin player.

The default probe only connects, negotiates roles, and reads player state. The
two state-changing checks are opt-in, bounded, and restore the original state.
"""

from __future__ import annotations

import argparse
import asyncio
import ipaddress
import json
import socket
import sys
from typing import Any

DEPENDENCY_ERROR: ImportError | None = None

try:
    from aiosendspin.models import AudioCodec
    from aiosendspin.models.types import ConnectionReason
    from aiosendspin.noise import Identity
    from aiosendspin.noise.trust_store import InMemoryServerPairingStore
    from aiosendspin.server import SendspinServer
    from aiosendspin.server.audio import AudioFormat
except ImportError as error:  # pragma: no cover - exercised by the CLI environment
    DEPENDENCY_ERROR = error


DEFAULT_PORT = 8927
DEFAULT_PATH = "/sendspin"
SILENCE_SECONDS = 1
PCM_FORMAT_VALUES = {
    "sample_rate": 48_000,
    "bit_depth": 16,
    "channels": 2,
}


class SendspinProbeError(Exception):
    """The endpoint could not safely complete the requested acceptance test."""


def _is_private_address(address: str) -> bool:
    parsed = ipaddress.ip_address(address.split("%", 1)[0])
    return parsed.is_private or parsed.is_loopback or parsed.is_link_local


async def _resolve_private_endpoint(host: str, port: int) -> tuple[str, str]:
    """Resolve once and return a URL that cannot re-resolve to a public address."""
    if not 1 <= port <= 65_535:
        raise SendspinProbeError("Sendspin port must be between 1 and 65535")

    try:
        answers = await asyncio.get_running_loop().getaddrinfo(
            host,
            port,
            type=socket.SOCK_STREAM,
        )
    except OSError as error:
        raise SendspinProbeError(f"Cannot resolve Sendspin host {host}: {error}") from error

    addresses = list(dict.fromkeys(answer[4][0] for answer in answers))
    if not addresses:
        raise SendspinProbeError(f"Cannot resolve Sendspin host {host}")
    if any(not _is_private_address(address) for address in addresses):
        raise SendspinProbeError(
            "Sendspin hardware probes are restricted to private, loopback, or link-local addresses"
        )

    address = addresses[0]
    url_host = f"[{address}]" if ":" in address else address
    return address, f"ws://{url_host}:{port}{DEFAULT_PATH}"


async def _wait_for_volume(role: Any, expected: int, timeout: float) -> bool:
    deadline = asyncio.get_running_loop().time() + timeout
    while asyncio.get_running_loop().time() < deadline:
        if role.volume == expected:
            return True
        await asyncio.sleep(0.1)
    return role.volume == expected


def _device_report(client: Any, player_role: Any) -> dict[str, Any]:
    info = client.info
    device_info = info.device_info
    support = info.player_support
    formats = []
    commands = []
    if support is not None:
        commands = [command.value for command in support.supported_commands]
        formats = [
            {
                "codec": item.codec.value,
                "sample_rate": item.sample_rate,
                "bit_depth": item.bit_depth,
                "channels": item.channels,
            }
            for item in support.supported_formats
        ]

    return {
        "name": client.name,
        "device_info": {
            "manufacturer": getattr(device_info, "manufacturer", None),
            "product_name": getattr(device_info, "product_name", None),
            "software_version": getattr(device_info, "software_version", None),
        },
        "negotiated_roles": client.negotiated_role_ids,
        "active_roles": client.active_role_ids,
        "available": client.available,
        "player": {
            "volume": player_role.volume,
            "muted": player_role.muted,
            "static_delay_ms": player_role.static_delay_ms,
            "required_lead_time_ms": player_role.required_lead_time_ms,
            "min_buffer_ms": player_role.min_buffer_ms,
            "supported_commands": commands,
            "supported_formats": formats,
        },
        "transport_security": (
            "legacy_unencrypted"
            if client.connection_security is None
            else str(client.connection_security)
        ),
    }


async def probe(
    host: str,
    port: int,
    timeout: float,
    *,
    control_test: bool,
    silent_stream_test: bool,
) -> dict[str, Any]:
    """Inspect a Sendspin player and optionally run reversible hardware checks."""
    if DEPENDENCY_ERROR is not None:
        raise SendspinProbeError(
            "Missing probe dependencies; install requirements-sendspin-probe.txt in a virtualenv"
        ) from DEPENDENCY_ERROR

    address, url = await _resolve_private_endpoint(host, port)
    loop = asyncio.get_running_loop()
    server = SendspinServer(
        loop,
        Identity.generate(),
        "Sonance EQ hardware probe",
        pairing_store=InMemoryServerPairingStore(),
        allow_unencrypted=True,
        allow_noncompliant_clients=True,
    )
    group = None
    player_role = None
    original_volume = None
    tests: dict[str, Any] = {}
    connection_reason = (
        ConnectionReason.PLAYBACK
        if control_test or silent_stream_test
        else ConnectionReason.DISCOVERY
    )

    try:
        await asyncio.wait_for(
            server.connect_to_client_and_wait(url, connection_reason=connection_reason),
            timeout=timeout,
        )
        await asyncio.sleep(0.75)
        if not server.connected_clients:
            raise SendspinProbeError("Sendspin handshake completed without a connected client")

        client = server.connected_clients[0]
        player_role = client.role("player@v1")
        if player_role is None:
            raise SendspinProbeError("The endpoint did not negotiate the player@v1 role")
        original_volume = player_role.volume
        group = client.group

        if control_test:
            probe_volume = original_volume - 1 if original_volume > 0 else 1
            player_role.set_volume(probe_volume)
            changed = await _wait_for_volume(player_role, probe_volume, timeout)
            player_role.set_volume(original_volume)
            restored = await _wait_for_volume(player_role, original_volume, timeout)
            tests["volume_control"] = {
                "requested": probe_volume,
                "change_acknowledged": changed,
                "restored_to": original_volume,
                "restore_acknowledged": restored,
            }
            if not changed or not restored:
                raise SendspinProbeError(
                    "Volume control test did not acknowledge and restore state"
                )

        if silent_stream_test:
            pcm_format = AudioFormat(**PCM_FORMAT_VALUES)
            if not player_role.set_preferred_format(pcm_format, AudioCodec.PCM):
                raise SendspinProbeError("The endpoint rejected 48 kHz 16-bit stereo PCM")
            silence = bytes(
                PCM_FORMAT_VALUES["sample_rate"]
                * PCM_FORMAT_VALUES["channels"]
                * (PCM_FORMAT_VALUES["bit_depth"] // 8)
                * SILENCE_SECONDS
            )
            stream = group.start_stream()
            stream.prepare_audio(silence, pcm_format)
            play_start_us = await stream.commit_audio()
            await asyncio.sleep(0.25)
            started = player_role.stream_started and group.has_active_stream
            volume_unchanged = player_role.volume == original_volume
            await asyncio.sleep(1.75)
            stopped = await group.stop()
            await asyncio.sleep(0.25)
            ended = not player_role.stream_started and not group.has_active_stream
            tests["silent_pcm_stream"] = {
                "codec": "pcm",
                "format": PCM_FORMAT_VALUES,
                "duration_seconds": SILENCE_SECONDS,
                "bytes_sent": len(silence),
                "play_start_us": play_start_us,
                "started": started,
                "stopped": stopped and ended,
                "volume_unchanged": volume_unchanged,
            }
            if not started or not stopped or not ended or not volume_unchanged:
                raise SendspinProbeError(
                    "Silent PCM stream did not start, stop, and preserve volume"
                )

        return {
            "status": "compatible",
            "endpoint": {
                "host": host,
                "resolved_address": address,
                "port": port,
                "path": DEFAULT_PATH,
            },
            "device": _device_report(client, player_role),
            "tests": tests,
            "writes_performed": control_test or silent_stream_test,
            "persistent_state_restored": player_role.volume == original_volume,
        }
    finally:
        if player_role is not None and original_volume is not None:
            if player_role.volume != original_volume:
                player_role.set_volume(original_volume)
                await _wait_for_volume(player_role, original_volume, timeout)
        if group is not None and group.has_active_stream:
            await group.stop()
        server.disconnect_from_client(url)
        await asyncio.sleep(0.2)
        await server.close()


def parse_args() -> argparse.Namespace:
    """Parse the guarded hardware-probe command line."""
    parser = argparse.ArgumentParser(
        description=(
            "Inspect a private-LAN Sendspin player; state-changing checks are opt-in and restored"
        )
    )
    parser.add_argument("host", help="Private IP address or local hostname")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--timeout", type=float, default=8.0)
    parser.add_argument(
        "--control-test",
        action="store_true",
        help="Change volume by one point, verify the acknowledgement, and restore it",
    )
    parser.add_argument(
        "--silent-stream-test",
        action="store_true",
        help="Send one second of digital silence and verify start/stop state",
    )
    return parser.parse_args()


def main() -> int:
    """Run the physical Sendspin acceptance probe."""
    args = parse_args()
    try:
        report = asyncio.run(
            probe(
                args.host,
                args.port,
                args.timeout,
                control_test=args.control_test,
                silent_stream_test=args.silent_stream_test,
            )
        )
    except (OSError, TimeoutError, SendspinProbeError, ValueError) as error:
        detail = str(error) or type(error).__name__
        print(
            json.dumps(
                {
                    "status": "incompatible_or_unreachable",
                    "error": detail,
                    "state_changing_tests_requested": (
                        args.control_test or args.silent_stream_test
                    ),
                },
                indent=2,
                sort_keys=True,
            ),
            file=sys.stderr,
        )
        return 2
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
