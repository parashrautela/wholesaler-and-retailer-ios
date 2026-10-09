import Foundation

// Run from the iOS repository:
// swiftc JewelIndia/Sources/Features/Wholesaler/TreasureChest/TreasureChestModels.swift tests/daily-credit-schedule/main.swift -o /tmp/daily-credit-schedule-tests
// /tmp/daily-credit-schedule-tests

func wallet(_ overrides: [String: Any] = [:]) throws -> CreditWallet {
    var json: [String: Any] = [
        "ok": true, "mode": "daily", "daily_allowance": 2000,
        "server_now": "2026-10-06T18:00:00+00:00",
        "resets_at": "2026-10-07T00:00:00+05:30"
    ]
    json.merge(overrides) { _, replacement in replacement }
    return try JSONDecoder().decode(CreditWallet.self, from: JSONSerialization.data(withJSONObject: json))
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let receipt = ContinuousClock.now
let schedule = DailyCreditSchedule(wallet: try wallet(), receivedAt: receipt)!
check(schedule.allowance == 2000, "Use the server allowance")
check(schedule.countdown(at: receipt) == "00:30:00", "UTC and IST represent the same reset")
check(schedule.countdown(at: receipt.advanced(by: .seconds(1))) == "00:29:59", "Countdown advances without a new server request")
check(schedule.countdown(at: receipt.advanced(by: .seconds(1800))) == "00:00:00", "Midnight is the refresh boundary")
check(schedule.remainingSeconds(at: receipt.advanced(by: .seconds(2000))) == 0, "Expired countdown must not become negative")
check(schedule.countdown(at: receipt.advanced(by: .seconds(-10))) == "00:30:00", "An earlier clock sample must not increase the countdown")
check(schedule.resetDescription.contains("7 Oct") && schedule.resetDescription.contains("12:00") && schedule.resetDescription.hasSuffix("IST"), "Render the deadline explicitly in India time")

let fractional = DailyCreditSchedule(wallet: try wallet([
    "server_now": "2026-10-06T18:29:58.750000+00:00",
    "resets_at": "2026-10-06T18:30:00.000000+00:00"
]), receivedAt: receipt)!
check(fractional.remainingSeconds(at: receipt) == 2, "Parse Supabase fractional-second timestamps and round up")
check(fractional.remainingSeconds(at: receipt.advanced(by: .milliseconds(1250))) == 0, "Fractional deadlines expire at their actual boundary")

let fullDay = DailyCreditSchedule(wallet: try wallet([
    "server_now": "2026-10-06T18:30:00Z", "resets_at": "2026-10-07T18:30:00Z"
]), receivedAt: receipt)!
check(fullDay.countdown(at: receipt) == "24:00:00", "Full next India calendar day is supported")

for overrides: [String: Any] in [
    ["ok": false, "error": "NOT_VERIFIED"],
    ["mode": "legacy"], ["daily_allowance": 0],
    ["server_now": NSNull()], ["resets_at": NSNull()],
    ["resets_at": "invalid"],
    ["resets_at": "2026-10-05T18:30:00Z"],
    ["resets_at": "2026-10-09T18:30:00Z"]
] {
    let candidate = DailyCreditSchedule(wallet: try wallet(overrides))
    check(candidate == nil, "Do not invent a countdown for errors, inactive wallets or invalid data")
}
let rejectedWallet = try wallet(["ok": false, "error": "NOT_VERIFIED"])
check(rejectedWallet.errorCode == "NOT_VERIFIED", "Preserve the server reason for the approval message")
let changedAllowance = DailyCreditSchedule(wallet: try wallet(["daily_allowance": 3000]))!
check(changedAllowance.allowance == 3000, "Do not hard-code the allowance")
print("Passed daily credit schedule checks: IST reset, monotonic countdown, midnight, fractional timestamps, eligibility and invalid data.")
