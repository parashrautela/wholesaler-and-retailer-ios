#!/bin/bash
# Checks AddProductForm's required-field rules and ChamakAPI.isDeviceUpload,
# compiled straight from the app sources.
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TASK_TEMP=$(mktemp -d /private/tmp/add-product-rules.XXXXXX)
trap 'rm -rf "$TASK_TEMP"' EXIT
python3 - "$TASK_ROOT" "$TASK_TEMP/Test.swift" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]) / 'JewelIndia/Sources'
form = (root / 'Features/Wholesaler/AddProductForm.swift').read_text()
api = (root / 'Networking/ChamakAPI.swift').read_text()
a = form.index('    /// Accepts "12,5"'); b = form.index('    /// An optional text field')
number = form[a:b]
a = form.index('    func validate(requiresImage: Bool)'); b = form.index('    // MARK: - Submit')
validate = form[a:b]
a = api.index('    static func isDeviceUpload'); b = api.index('    // MARK: - Stage 1: Create & Analyze')
device = api[a:b]
Path(sys.argv[2]).write_text('import Foundation\n' + '''
extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
struct PickedFile {}
enum ChamakAPI {
''' + device + '''
}
final class Form {
    var image: PickedFile? = PickedFile()
    var title = "", jewelleryType = "necklace", category = "", style = "", size = "", metalPurity = ""
    var grossWeight = "", stoneWeight = "", netWeight = "12.5", makeToOrderDays = ""
    var stockAvailable = true
    var errors: [String: String] = [:]
    var bannerError: String?
''' + number + validate + '''
}
func check(_ name: String, valid: Bool, errorKeys: Set<String> = [], requiresImage: Bool = true, _ edit: (Form) -> Void = { _ in }) {
    let f = Form(); edit(f)
    let ok = f.validate(requiresImage: requiresImage)
    guard ok == valid, Set(f.errors.keys) == errorKeys else {
        print("FAIL: \\(name): valid=\\(ok) errors=\\(f.errors.keys.sorted())"); exit(1)
    }
    print("ok   \\(name)")
}
check("only type + net weight is enough", valid: true)
check("everything filled in", valid: true) { $0.title = "Haar"; $0.category = "gold"; $0.style = "bridal"; $0.size = "m"; $0.metalPurity = "22k"; $0.grossWeight = "14"; $0.stoneWeight = "1.5" }
check("missing type", valid: false, errorKeys: ["jewellery_type"]) { $0.jewelleryType = "" }
check("missing net weight", valid: false, errorKeys: ["netWeight"]) { $0.netWeight = "" }
check("spaces as net weight", valid: false, errorKeys: ["netWeight"]) { $0.netWeight = "   " }
check("zero net weight", valid: false, errorKeys: ["netWeight"]) { $0.netWeight = "0" }
check("negative net weight", valid: false, errorKeys: ["netWeight"]) { $0.netWeight = "-3" }
check("text as net weight", valid: false, errorKeys: ["netWeight"]) { $0.netWeight = "abc" }
check("comma decimal net weight", valid: true) { $0.netWeight = "12,5" }
check("missing type and weight", valid: false, errorKeys: ["jewellery_type", "netWeight"]) { $0.jewelleryType = ""; $0.netWeight = "" }
check("no photo when submitting", valid: false, errorKeys: ["image"]) { $0.image = nil }
check("no photo is fine for save later", valid: true, requiresImage: false) { $0.image = nil }
check("gross weight blank is fine", valid: true) { $0.grossWeight = "  " }
check("gross weight wrong", valid: false, errorKeys: ["grossWeight"]) { $0.grossWeight = "abc" }
check("gross weight zero", valid: false, errorKeys: ["grossWeight"]) { $0.grossWeight = "0" }
check("stone weight zero is fine", valid: true) { $0.stoneWeight = "0" }
check("stone weight negative", valid: false, errorKeys: ["stoneWeight"]) { $0.stoneWeight = "-1" }
check("stone weight wrong", valid: false, errorKeys: ["stoneWeight"]) { $0.stoneWeight = "x" }
check("out of stock, no days is fine", valid: true) { $0.stockAvailable = false }
check("out of stock, days given", valid: true) { $0.stockAvailable = false; $0.makeToOrderDays = "14" }
check("out of stock, zero days", valid: false, errorKeys: ["makeToOrderDays"]) { $0.stockAvailable = false; $0.makeToOrderDays = "0" }
check("in stock ignores bad days", valid: true) { $0.makeToOrderDays = "abc" }

func device(_ url: String, _ expected: Bool) {
    guard ChamakAPI.isDeviceUpload(url) == expected else { print("FAIL: isDeviceUpload \\(url)"); exit(1) }
    print("ok   \\(expected ? "device" : "catalogue"): \\(url.suffix(44))")
}
let base = "https://x.supabase.co/storage/v1/object/public/plant-images/"
device(base + "raw/abc/chamak_1_1234.jpg", true)
device(base + "raw/abc/setcreation_3_1234.jpg", true)
device(base + "raw/abc/product-draft_1234.jpg", false)
device(base + "products/processed/abc_v1.png", false)
device(base + "raw/abc/my_chamak_photo.jpg", false)
device("", false)
print("ALL PASSED")
''')
PY
xcrun swiftc -o "$TASK_TEMP/test" "$TASK_TEMP/Test.swift"
"$TASK_TEMP/test"
