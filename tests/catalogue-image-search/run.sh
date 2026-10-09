#!/bin/bash
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TASK_TEMP=$(mktemp -d /private/tmp/jewel-vision-tests.XXXXXX)
trap 'rm -rf "$TASK_TEMP"' EXIT
# Compile the production native transport and image validation on macOS.
# SwiftUI/PhotosUI are verified by the app build; matching runs in the backend.
python3 - "$TASK_ROOT" "$TASK_TEMP/Engine.swift" <<'PY'
import pathlib,sys
s=(pathlib.Path(sys.argv[1])/'JewelIndia/Sources/Features/Retailer/CatalogueImageSearch.swift').read_text()
s=s.split('@MainActor @Observable')[0]
s=s.replace('import UIKit\n','').replace('import PhotosUI\n','').replace('import SwiftUI\n','')
pathlib.Path(sys.argv[2]).write_text(s)
PY
xcrun swiftc -parse-as-library "$TASK_TEMP/Engine.swift" "$TASK_ROOT/tests/catalogue-image-search/Tests.swift" -o "$TASK_TEMP/tests"
"$TASK_TEMP/tests" "$@"
