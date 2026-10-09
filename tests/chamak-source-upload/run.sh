#!/bin/bash
set -euo pipefail
TASK_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TASK_TEMP=$(mktemp -d /private/tmp/chamak-upload-test.XXXXXX)
trap 'rm -rf "$TASK_TEMP"' EXIT
python3 - "$TASK_ROOT" "$TASK_TEMP/Test.swift" <<'PY'
from pathlib import Path
import sys
source=(Path(sys.argv[1])/'JewelIndia/Sources/Networking/ChamakAPI.swift').read_text()
def method(start, end):
    a=source.index(start); return source[a:source.index(end,a)].rstrip()
check=method('    private static func requireLiveSession(', '\n    // MARK: - Products for Picker')
upload=method('    static func uploadSourceImage(', '\n    // MARK: - Stage 1: Create & Analyze')
Path(sys.argv[2]).write_text('''import Foundation
struct User { let id: UUID }
struct Session { let user: User }
struct Auth { var session: Session { get async throws { Session(user: User(id: SupabaseManager.owner)) } } }
struct Client { let auth = Auth() }
enum SupabaseManager { static let owner = UUID(); static let client = Client() }
enum ChamakMode { case fusion, setCreation }
enum WholesalerAPI {
    static var paths: [String] = []
    static var fail = false
    static func upload(bucket: String, path: String, data: Data, contentType: String, upsert: Bool = true) async throws -> String {
        precondition(bucket == "plant-images" && !upsert)
        paths.append(path)
        if fail { throw NSError(domain: "upload", code: 1, userInfo: [NSLocalizedDescriptionKey: "RLS denied"]) }
        return path
    }
}
enum ChamakAPI {
    struct ChamakError: LocalizedError { let message: String; var errorDescription: String? { message } }
'''+check+'\n'+upload+'''
}
@main struct Tests {
    static func main() async throws {
        let uid = SupabaseManager.owner
        let a = try await ChamakAPI.uploadSourceImage(wholesalerID: uid, imageData: Data(), slot: 1)
        let b = try await ChamakAPI.uploadSourceImage(wholesalerID: uid, imageData: Data(), slot: 1)
        precondition(a != b && a.hasPrefix("raw/\\(uid.uuidString.lowercased())/chamak_1_"))
        let c = try await ChamakAPI.uploadSourceImage(wholesalerID: uid, imageData: Data(), slot: 2, mode: .setCreation)
        precondition(c.contains("/setcreation_2_"))
        let count = WholesalerAPI.paths.count
        do {
            _ = try await ChamakAPI.uploadSourceImage(wholesalerID: UUID(), imageData: Data(), slot: 1)
            fatalError("Mismatched owner was accepted")
        } catch { precondition(WholesalerAPI.paths.count == count) }
        WholesalerAPI.fail = true
        do {
            _ = try await ChamakAPI.uploadSourceImage(wholesalerID: uid, imageData: Data(), slot: 2)
            fatalError("Upload failure was swallowed")
        } catch {
            precondition(error.localizedDescription.contains("source image 2") && error.localizedDescription.contains("RLS denied"))
        }
        print("PASS: unique insert-only uploads, owner session checks, set mode and contextual failures")
    }
}
''')
PY
CLANG_MODULE_CACHE_PATH="$TASK_TEMP/cache" xcrun swiftc -module-cache-path "$TASK_TEMP/cache" -parse-as-library "$TASK_TEMP/Test.swift" -o "$TASK_TEMP/tests"
"$TASK_TEMP/tests"
