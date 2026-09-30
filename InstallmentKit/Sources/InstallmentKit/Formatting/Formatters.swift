import Foundation

/// 表示用の書式。端末のロケールに左右されないよう、自前で整形する。
public enum DisplayFormat {
    /// 1234567 → "1,234,567"
    public static func yen(_ value: Int) -> String {
        let digits = String(value.magnitude)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return value < 0 ? "-" + out : out
    }

    /// Decimal(3) → "3", Decimal(string: "2.50") → "2.5"
    public static func rate(_ value: Decimal) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 4, .plain)
        return NSDecimalNumber(decimal: rounded).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }

    /// 2026年11月
    public static func month(_ value: YearMonth) -> String {
        "\(value.year)年\(value.month)月"
    }

    /// [12, 6] → "6月・12月"
    public static func months(_ values: Set<Int>) -> String {
        values.sorted().map { "\($0)月" }.joined(separator: "・")
    }

    /// 作成日 2026年9月30日
    public static func date(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)年\(c.month ?? 0)月\(c.day ?? 0)日"
    }
}
