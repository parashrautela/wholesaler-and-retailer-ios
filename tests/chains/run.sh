#!/bin/bash
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TASK_TEMP=$(mktemp -d /private/tmp/jewel-chain-tests.XXXXXX)
trap 'rm -rf "$TASK_TEMP"' EXIT
python3 - "$TASK_ROOT" "$TASK_TEMP/Chains.swift" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'JewelIndia/Sources/Features/Wholesaler/Chamak/ChamakModels.swift').read_text()
Path(sys.argv[2]).write_text('import Foundation\n'+source[source.index('enum JewelleryTypeCanonical:'):]+'''
for alias in ["chain", "chains", "Neck Chain", " neck chains "] {
    precondition(JewelleryTypeCanonical.canonicalize(alias) == "chain")
}
precondition(JewelleryTypeCanonical.allCanonical.contains("chain"))
precondition(JewelleryTypeCanonical.displayLabel(for: "chain") == "Chains")
precondition(JewelleryTypeCanonical.canonicalize("gold") == nil)
precondition(JewelleryTypeCanonical.canonicalize("necklace") == "necklace")
print("PASS: chain aliases, picker label, and separation from material and necklace categories")
''')
PY
CLANG_MODULE_CACHE_PATH="$TASK_TEMP/cache" xcrun swiftc -module-cache-path "$TASK_TEMP/cache" "$TASK_TEMP/Chains.swift" -o "$TASK_TEMP/tests"
"$TASK_TEMP/tests"
