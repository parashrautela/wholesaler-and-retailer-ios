#!/bin/bash
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TASK_TEMP=$(mktemp -d /private/tmp/chamak-message-test.XXXXXX)
trap 'rm -rf "$TASK_TEMP"' EXIT
python3 - "$TASK_ROOT" "$TASK_TEMP/Test.swift" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'JewelIndia/Sources/Features/Wholesaler/Chamak/ChamakModels.swift').read_text()
flag=source[source.index('enum ContentFlag:'):source.index('// MARK: - Stage 1 Vision Analysis')]
a=source.index('    var failureUserMessage: String');b=source.index('\n    enum CodingKeys:',a)
prop=source[a:b]
Path(sys.argv[2]).write_text('import Foundation\n'+flag+'''
struct Analysis { let contentFlag: ContentFlag }
struct Generation {
    let contentFlagHit: ContentFlag?
    let stage1AnalysisJSON: Analysis?
'''+prop+'''
}
let rejected = Generation(contentFlagHit: .notJewelry, stage1AnalysisJSON: nil)
precondition(rejected.failureUserMessage == "Jewellery was not detected in one or both selected images. Please select two clear jewellery photos to continue.")
let blurry = Generation(contentFlagHit: nil, stage1AnalysisJSON: Analysis(contentFlag: .tooUnclearToAssess))
precondition(blurry.failureUserMessage.contains("blurry"))
let unknown = Generation(contentFlagHit: nil, stage1AnalysisJSON: nil)
precondition(unknown.failureUserMessage.contains("try again"))
let ok = Generation(contentFlagHit: .ok, stage1AnalysisJSON: nil)
precondition(ok.failureUserMessage == unknown.failureUserMessage)
print("PASS: saved rejection, legacy analysis and unclassified failures use appropriate messages")
''')
PY
CLANG_MODULE_CACHE_PATH="$TASK_TEMP/cache" xcrun swiftc -module-cache-path "$TASK_TEMP/cache" "$TASK_TEMP/Test.swift" -o "$TASK_TEMP/tests"
"$TASK_TEMP/tests"
