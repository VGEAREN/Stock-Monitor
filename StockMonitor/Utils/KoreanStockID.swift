import Foundation

/// Helpers for converting between Stockbar's internal Korean stock ID
/// (`kr_<6digit>.ks` for KOSPI, `kr_<6digit>.kq` for KOSDAQ) and Yahoo
/// Finance symbol (`005930.KS`, `293490.KQ`).
enum KoreanStockID {

    /// Stockbar-internal ID prefix for Korean stocks.
    static let prefix = "kr_"

    /// Returns true if `id` looks like a Korean stock ID. Case-insensitive on the prefix.
    static func isKorean(_ id: String) -> Bool {
        let lower = id.lowercased()
        guard lower.hasPrefix(prefix) else { return false }
        return lower.count > prefix.count
    }

    /// Convert internal ID → Yahoo symbol. Returns nil for non-Korean IDs.
    /// e.g. `kr_005930.ks` → `005930.KS`
    static func toYahooSymbol(_ id: String) -> String? {
        guard isKorean(id) else { return nil }
        let lower = id.lowercased()
        let suffix = String(lower.dropFirst(prefix.count))
        return suffix.uppercased()
    }

    /// Convert Yahoo symbol → internal ID. Always succeeds.
    /// e.g. `005930.KS` → `kr_005930.ks`
    static func fromYahooSymbol(_ symbol: String) -> String {
        return prefix + symbol.lowercased()
    }
}
