#!/bin/bash
# Checkout-local AppFleet entry point. Default: read-only doctor.
# Tools/ship.sh status
# Tools/ship.sh ship                         # preview a source release
# Tools/ship.sh ship --yes                   # build -> upload -> VALID -> attach
# Tools/ship.sh upload --artifact /path/to/SonanceEQ.pkg --build-number 9
# Add --yes only when the previewed Apple writes are authorized.
# Listing/IAP/privacy/review operations remain separate; see docs/RELEASE.md.
set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$TOOLS_DIR/asc/pipeline.py" "$@"
