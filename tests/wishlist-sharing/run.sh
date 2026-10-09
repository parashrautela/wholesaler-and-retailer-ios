#!/bin/bash
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TASK_TEMP=$(mktemp -d /private/tmp/jewel-wishlist-native.XXXXXX)
trap 'rm -rf "$TASK_TEMP"' EXIT
python3 - "$TASK_ROOT" "$TASK_TEMP/Model.swift" <<'INNER'
from pathlib import Path
import sys
s=(Path(sys.argv[1])/'JewelIndia/Sources/Networking/WishlistAPI.swift').read_text().split('struct WishlistShare:')[1]
Path(sys.argv[2]).write_text('import Foundation\nenum AppConfig { static let siteURL = URL(string: "https://jewel-india-frontend-yws1.vercel.app")! }\nstruct WishlistShare:'+s)
INNER
xcrun swiftc "$TASK_TEMP/Model.swift" "$TASK_ROOT/tests/wishlist-sharing/main.swift" -o "$TASK_TEMP/tests"
"$TASK_TEMP/tests"
