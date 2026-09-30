import Foundation

/// 入力画面の値（文字列のまま）。検証して `LoanInput` に変換する。
/// 患者に関する入力を含むため、保存しないこと（仕様 9章）。
public struct LoanForm: Equatable, Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        case fromMonthlyPayment  // ① 月額から求める
        case fromInstallments    // ② 回数から求める

        public var label: String {
            switch self {
            case .fromMonthlyPayment: return "① 月額から"
            case .fromInstallments: return "② 回数から"
            }
        }
    }

    public var mode: Mode = .fromInstallments
    public var principalText = ""
    public var rateText = ""
    public var installmentsText = ""
    public var monthlyPaymentText = ""
    public var bonusEnabled = false
    public var bonusAmountText = ""
    public var bonusMonths: Set<Int> = [6, 12]
    public var firstPaymentMonth: YearMonth = .nextMonth()
    public var patientName = ""

    public init() {}

    /// 計算に必要な値がそろっているか（未入力の間はエラーを出さないために使う）。
    public var isReadyToCalculate: Bool {
        let main = mode == .fromInstallments ? installmentsText : monthlyPaymentText
        return ![principalText, rateText, main].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public func makeInput() throws -> LoanInput {
        guard let principal = NumberParser.integer(principalText), principal > 0 else {
            throw CalculationError.invalidPrincipal
        }
        guard let rate = NumberParser.decimal(rateText) else { throw CalculationError.invalidRate }

        let calcMode: CalculationMode
        switch mode {
        case .fromInstallments:
            guard let n = NumberParser.integer(installmentsText), n >= 1 else {
                throw CalculationError.invalidInstallments
            }
            calcMode = .fromInstallments(n)
        case .fromMonthlyPayment:
            guard let p = NumberParser.integer(monthlyPaymentText), p >= 1 else {
                throw CalculationError.invalidMonthlyPayment
            }
            calcMode = .fromMonthlyPayment(p)
        }

        var bonus: BonusPlan?
        if bonusEnabled {
            let text = bonusAmountText.trimmingCharacters(in: .whitespaces)
            let amount: Int
            if text.isEmpty {
                amount = 0
            } else {
                guard let value = NumberParser.integer(text), value >= 0 else {
                    throw CalculationError.invalidBonusAmount
                }
                amount = value
            }
            guard bonusMonths.allSatisfy({ (1...12).contains($0) }) else { throw CalculationError.invalidBonusMonth }
            bonus = BonusPlan(amount: amount, months: bonusMonths)
        }

        let input = LoanInput(principal: principal, annualRatePercent: rate, mode: calcMode,
                              bonus: bonus, firstPaymentMonth: firstPaymentMonth)
        try Calculator.validate(input)
        return input
    }
}

/// 数値入力の解釈。全角数字・カンマ・「円」「%」・前後の空白を許す。
public enum NumberParser {
    public static func normalize(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19:  // 全角数字
                result.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!)
            case 0xFF0E: result.append(".")       // ．
            case 0xFF0D, 0x2212: result.append("-")  // －, −
            case 0x2C, 0xFF0C, 0x3001, 0x20, 0x3000: continue  // カンマ・読点・空白
            default:
                if "円%％".unicodeScalars.contains(scalar) { continue }
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// 整数（小数点を含むものは不可）。
    public static func integer(_ text: String) -> Int? {
        let s = normalize(text)
        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-") }) else { return nil }
        return Int(s)
    }

    /// 小数（年率など）。
    public static func decimal(_ text: String) -> Decimal? {
        let s = normalize(text)
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard !s.isEmpty, parts.count <= 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && ($0.isNumber || $0 == "-") } }),
              !parts[0].isEmpty || parts.count == 2 else { return nil }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }
}
