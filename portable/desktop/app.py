#!/usr/bin/env python3
from pathlib import Path
import sys

# Share the shipping preset contract in source runs and frozen builds.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sonance_ui.main import main

if __name__ == "__main__":
    raise SystemExit(main())
