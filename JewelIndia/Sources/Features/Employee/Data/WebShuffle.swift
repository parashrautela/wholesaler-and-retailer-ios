import Foundation

/// The web home's "deterministic shuffle" (`app/dashboard/employee/page.jsx`),
/// reproduced bit for bit so an employee sees the same six designs, in the
/// same order, on the phone as in the browser.
///
/// The obvious Swift port — wrapping `Int32` arithmetic — gets a different
/// answer for almost every id. JavaScript evaluates
/// `1103515245 * seedVal` as a Double, which passes 2^53 whenever the seed
/// is above ~8 million, so its low bits are rounded away *before*
/// `& 0x7fffffff` converts back to an integer. This does the same.
enum WebShuffle {
    /// ECMA-262 ToInt32 applied to a Double.
    static func jsToInt32(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        var wrapped = value.rounded(.towardZero).truncatingRemainder(dividingBy: 4_294_967_296)
        if wrapped < 0 { wrapped += 4_294_967_296 }
        return Int32(bitPattern: UInt32(wrapped))
    }

    /// `seedID` must be the id exactly as the database returns it — a
    /// lowercase `employees.id`. `UUID.uuidString` is uppercase and gives a
    /// different order.
    static func shuffled<T>(_ items: [T], seedID: String, keep: Int = 6) -> [T] {
        var seed: Int32 = 0
        for unit in seedID.utf16 {
            let folded = Double(seed) * 31
            seed = jsToInt32(folded + Double(unit))
        }

        var result = items
        var i = result.count - 1
        while i > 0 {
            // Two statements on purpose: a fused multiply-add would not
            // round the way JavaScript does.
            let product = 1_103_515_245 * Double(seed)
            let sum = product + 12_345
            seed = jsToInt32(sum) & 0x7FFF_FFFF
            let j = Int(seed) % (i + 1)
            result.swapAt(i, j)
            i -= 1
        }
        return Array(result.prefix(keep))
    }

    /// Which of the four tall collection images this person gets: the last
    /// hex digit of their id, mod 4 (`parseInt(lastChar, 16) || 0`).
    static func imageIndex(for seedID: String, count: Int = 4) -> Int {
        guard let last = seedID.last, let digit = Int(String(last), radix: 16) else { return 0 }
        return digit % count
    }
}
