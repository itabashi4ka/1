import Foundation

/// 円未満の端数処理。
public enum RoundingRule: String, Codable, CaseIterable, Sendable {
    case down      // 切り捨て（既定）
    case up        // 切り上げ
    case nearest   // 四捨五入

    public var label: String {
        switch self {
        case .down: return "切り捨て"
        case .up: return "切り上げ"
        case .nearest: return "四捨五入"
        }
    }

    /// 0以上の金額を円単位に丸める。
    public func apply(_ value: Decimal) -> Int {
        var input = value
        var output = Decimal()
        let mode: NSDecimalNumber.RoundingMode
        switch self {
        case .down: mode = .down
        case .up: mode = .up
        case .nearest: mode = .plain
        }
        NSDecimalRound(&output, &input, 0, mode)
        return NSDecimalNumber(decimal: output).intValue
    }

    public func apply(_ value: Double) -> Int {
        switch self {
        case .down: return Int(value.rounded(.down))
        case .up: return Int(value.rounded(.up))
        case .nearest: return Int(value.rounded(.toNearestOrAwayFromZero))
        }
    }
}

/// 月額を円に丸めたときの差額を、どの回で調整するか（モード②で使用）。
public enum AdjustmentPlacement: String, Codable, CaseIterable, Sendable {
    case last   // 最終回で調整（既定）
    case first  // 初回で調整

    public var label: String {
        switch self {
        case .last: return "最終回で調整"
        case .first: return "初回で調整"
        }
    }
}

/// 年と月。支払月の表示に使う。
public struct YearMonth: Hashable, Codable, Comparable, Sendable {
    public var year: Int
    public var month: Int  // 1...12

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month), "month must be 1...12")
        self.year = year
        self.month = month
    }

    public func adding(months: Int) -> YearMonth {
        let index = year * 12 + (month - 1) + months
        return YearMonth(year: index / 12, month: index % 12 + 1)
    }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// 与えた日付の翌月（初回支払月の既定値）。
    public static func nextMonth(after date: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> YearMonth {
        let c = calendar.dateComponents([.year, .month], from: date)
        return YearMonth(year: c.year ?? 2000, month: c.month ?? 1).adding(months: 1)
    }
}

/// ボーナス払いの条件。加算額が0、または月が空なら無効として扱う。
public struct BonusPlan: Equatable, Sendable {
    public var amount: Int
    public var months: Set<Int>

    public init(amount: Int, months: Set<Int>) {
        self.amount = amount
        self.months = months
    }

    public var isActive: Bool { amount > 0 && !months.isEmpty }

    public func addition(for month: YearMonth) -> Int {
        isActive && months.contains(month.month) ? amount : 0
    }
}

/// 計算モード。
public enum CalculationMode: Equatable, Sendable {
    /// ① 月額（ボーナスを除く）から分割回数を求める
    case fromMonthlyPayment(Int)
    /// ② 分割回数から月額を求める
    case fromInstallments(Int)
}

/// 計算の入力。
public struct LoanInput: Equatable, Sendable {
    /// 支払総額（元本、税込、円）
    public var principal: Int
    /// 年率（%）
    public var annualRatePercent: Decimal
    public var mode: CalculationMode
    public var bonus: BonusPlan?
    public var firstPaymentMonth: YearMonth

    public init(principal: Int, annualRatePercent: Decimal, mode: CalculationMode,
                bonus: BonusPlan? = nil, firstPaymentMonth: YearMonth) {
        self.principal = principal
        self.annualRatePercent = annualRatePercent
        self.mode = mode
        self.bonus = bonus
        self.firstPaymentMonth = firstPaymentMonth
    }

    /// 月利 r = 年率 ÷ 100 ÷ 12
    public var monthlyRate: Decimal { annualRatePercent / 1200 }
}

/// 計算オプション（設定から渡す）。
public struct CalculationOptions: Equatable, Sendable {
    public var rounding: RoundingRule
    public var adjustment: AdjustmentPlacement

    public init(rounding: RoundingRule = .down, adjustment: AdjustmentPlacement = .last) {
        self.rounding = rounding
        self.adjustment = adjustment
    }
}

/// スケジュール表の1行。
public struct ScheduleRow: Equatable, Sendable {
    public var number: Int
    public var month: YearMonth
    /// その回の支払額（ボーナス加算を含む）
    public var payment: Int
    /// うちボーナス加算額
    public var bonusAddition: Int
    /// 元本充当
    public var principalPortion: Int
    /// 利息
    public var interest: Int
    /// 支払後の残高
    public var balance: Int
}

/// 計算結果。
public struct LoanResult: Equatable, Sendable {
    public var input: LoanInput
    /// 分割回数
    public var installments: Int { schedule.count }
    /// 月額（ボーナスを除く、通常回の額）
    public var monthlyPayment: Int
    public var schedule: [ScheduleRow]

    /// 総支払額 = 各回の支払額の合計
    public var totalPayment: Int { schedule.reduce(0) { $0 + $1.payment } }
    /// 利息総額 = 総支払額 − 支払総額（元本）
    public var totalInterest: Int { totalPayment - input.principal }
    public var totalBonus: Int { schedule.reduce(0) { $0 + $1.bonusAddition } }
    public var firstPayment: Int { schedule.first?.payment ?? 0 }
    public var lastPayment: Int { schedule.last?.payment ?? 0 }
}

/// 計算・入力のエラー。
public enum CalculationError: Error, Equatable, Sendable {
    case invalidPrincipal
    case invalidRate
    case invalidInstallments
    case invalidMonthlyPayment
    case invalidBonusAmount
    case invalidBonusMonth
    /// 月額（およびボーナス）が利息以下で元本が減らない
    case cannotRepay
    /// 返済に上限回数を超える回数がかかる
    case tooManyInstallments(limit: Int)
    /// ボーナス加算だけで完済でき、月額が0以下になる
    case bonusTooLarge
}

extension CalculationError: LocalizedError {
    public var errorDescription: String? { message }

    public var message: String {
        switch self {
        case .invalidPrincipal: return "支払総額は1円以上の整数で入力してください。"
        case .invalidRate: return "年率は0〜\(Calculator.maximumAnnualRatePercent)%の範囲で入力してください。"
        case .invalidInstallments: return "分割回数は1以上の整数で入力してください。"
        case .invalidMonthlyPayment: return "月額は1円以上の整数で入力してください。"
        case .invalidBonusAmount: return "ボーナス加算額は0円以上の整数で入力してください。"
        case .invalidBonusMonth: return "ボーナス月は1〜12月から選んでください。"
        case .cannotRepay: return "月額（およびボーナス）が毎月の利息以下のため、完済できません。"
        case .tooManyInstallments(let limit): return "分割回数が上限（\(limit)回）を超えます。月額を増やしてください。"
        case .bonusTooLarge: return "ボーナス加算額が大きすぎるため、月額を求められません。"
        }
    }
}
