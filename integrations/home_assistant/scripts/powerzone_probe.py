#!/usr/bin/env python3
"""Read-only acceptance probe for a physical Sonance PowerZone amplifier."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path
from typing import Any

COMPONENTS = Path(__file__).parents[1] / "custom_components"
sys.path.insert(0, str(COMPONENTS))

from sonance_eq.powerzone import PowerZoneApiError, PowerZoneClient


async def probe(host: str, port: int, timeout: float) -> dict[str, Any]:
    """Read identity, output names, and recognizable user-EQ presets."""
    client = PowerZoneClient(host, port, timeout_seconds=timeout)
    info = await client.validate_server()
    names = await client.output_names()
    outputs = []
    for output_id in range(1, info["outputs"] + 1):
        outputs.append(
            {
                "id": output_id,
                "name": names[output_id],
                "managed_preset": await client.read_preset(output_id),
            }
        )
    return {
        "status": "compatible",
        "endpoint": {"host": client.host, "port": client.port},
        "device": info,
        "outputs": outputs,
        "writes_performed": False,
    }


def parse_args() -> argparse.Namespace:
    """Parse a deliberately read-only command line."""
    parser = argparse.ArgumentParser(
        description=(
            "Verify a private-LAN Sonance PowerZone API without changing amplifier state"
        )
    )
    parser.add_argument("host", help="Private IP address or local hostname")
    parser.add_argument("--port", type=int, default=7621)
    parser.add_argument("--timeout", type=float, default=5.0)
    return parser.parse_args()


def main() -> int:
    """Run the physical-device acceptance probe."""
    args = parse_args()
    try:
        report = asyncio.run(probe(args.host, args.port, args.timeout))
    except (PowerZoneApiError, ValueError) as error:
        print(
            json.dumps(
                {
                    "status": "incompatible_or_unreachable",
                    "error": str(error),
                    "writes_performed": False,
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
