#!/bin/bash
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TASK_TEMP=$(mktemp -d /private/tmp/jewel-catalogue-tests.XXXXXX)
trap 'rm -rf "$TASK_TEMP"' EXIT
# Compile the production selection with the real Product model; SwiftUI is checked by xcodebuild.
python3 - "$TASK_ROOT" "$TASK_TEMP/Selection.swift" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
source = (root / 'JewelIndia/Sources/Features/Wholesaler/WholesalerCatalogueView.swift').read_text()
selection = source.split('struct CatalogueSelection {', 1)[1].split('\n}\n', 1)[0] + '\n}\n'
pathlib.Path(sys.argv[2]).write_text('struct CatalogueSelection {' + selection)
PY
xcrun swiftc -module-cache-path "$TASK_TEMP/ModuleCache" -parse-as-library \
    "$TASK_ROOT/JewelIndia/Sources/Core/Models.swift" \
    "$TASK_ROOT/JewelIndia/Sources/Core/Copy.swift" \
    "$TASK_ROOT/JewelIndia/Sources/Features/Wholesaler/WholesalerModels.swift" \
    "$TASK_TEMP/Selection.swift" "$TASK_ROOT/tests/catalogue-sharing/Tests.swift" \
    -o "$TASK_TEMP/tests"
"$TASK_TEMP/tests"
