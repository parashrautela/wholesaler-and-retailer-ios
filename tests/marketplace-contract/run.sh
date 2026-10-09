#!/bin/bash
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TASK_TEMP=$(mktemp -d /private/tmp/jewel-marketplace-tests.XXXXXX)
trap 'rm -rf "$TASK_TEMP"' EXIT
python3 - "$TASK_ROOT" "$TASK_TEMP/Contract.swift" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
models=(root/'JewelIndia/Sources/Features/Wholesaler/WholesalerModels.swift').read_text()
product=models[models.index('enum ImageSize:'):models.index('// MARK: - Orders')]
api=(root/'JewelIndia/Sources/Networking/JewelAPI.swift').read_text()
contract=api[api.index('    struct RetailerMarketplaceResponse:'):api.index('    struct SuccessResponse:')]
helpers='extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }; var nilIfEmpty: String? { isEmpty ? nil : self } }'
Path(sys.argv[2]).write_text('import Foundation\n'+helpers+'\n'+product+'\nenum JewelAPI {\n'+contract+'\n}\n')
PY
xcrun swiftc -parse-as-library "$TASK_TEMP/Contract.swift" "$TASK_ROOT/tests/marketplace-contract/Tests.swift" -o "$TASK_TEMP/tests"
"$TASK_TEMP/tests"
