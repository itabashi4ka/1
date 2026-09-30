import Foundation

/// テンプレートに差し込む値。金額はカンマ区切りの数字のみ（「円」はテンプレート側で書く）。
public struct TemplateContext: Equatable, Sendable {
    public var values: [String: String]
    public var rows: [[String: String]]
    /// 非表示にするセクション（`data-show` の値）
    public var hiddenSections: Set<String>

    public init(values: [String: String], rows: [[String: String]], hiddenSections: Set<String>) {
        self.values = values
        self.rows = rows
        self.hiddenSections = hiddenSections
    }

    public init(result: LoanResult, settings: AppSettings, patientName: String,
                showInterest: Bool, issueDate: Date = Date()) {
        let input = result.input
        let bonus = input.bonus.flatMap { $0.isActive && result.totalBonus > 0 ? $0 : nil }

        var values: [String: String] = [
            "clinic_name": settings.clinicName,
            "patient_name": patientName,
            "issue_date": DisplayFormat.date(issueDate),
            "principal": DisplayFormat.yen(input.principal),
            "annual_rate": DisplayFormat.rate(input.annualRatePercent),
            "installments": String(result.installments),
            "monthly_payment": DisplayFormat.yen(result.monthlyPayment),
            "first_payment": DisplayFormat.yen(result.firstPayment),
            "last_payment": DisplayFormat.yen(result.lastPayment),
            "bonus_amount": bonus.map { DisplayFormat.yen($0.amount) } ?? "",
            "bonus_months": bonus.map { DisplayFormat.months($0.months) } ?? "",
            "total_bonus": DisplayFormat.yen(result.totalBonus),
            "total_payment": DisplayFormat.yen(result.totalPayment),
            "total_interest": showInterest ? DisplayFormat.yen(result.totalInterest) : "",
            "first_month": result.schedule.first.map { DisplayFormat.month($0.month) } ?? "",
            "last_month": result.schedule.last.map { DisplayFormat.month($0.month) } ?? "",
            "note": settings.note,
            "theme_color": settings.themeColorHex,
            "accent_color": settings.accentColorHex,
            "font_family": settings.fontName,
            "logo": "",
        ]
        if let logo = settings.logoImage {
            values["logo"] = "data:\(Self.imageMIMEType(logo));base64,\(logo.base64EncodedString())"
        }

        let rows = result.schedule.map { row -> [String: String] in
            [
                "row.no": String(row.number),
                "row.month": DisplayFormat.month(row.month),
                "row.payment": DisplayFormat.yen(row.payment),
                "row.bonus": row.bonusAddition > 0 ? DisplayFormat.yen(row.bonusAddition) : "",
                "row.principal": DisplayFormat.yen(row.principalPortion),
                "row.interest": showInterest ? DisplayFormat.yen(row.interest) : "",
                "row.balance": DisplayFormat.yen(row.balance),
            ]
        }

        var hidden: Set<String> = []
        if !showInterest { hidden.insert("interest") }
        if bonus == nil { hidden.insert("bonus") }
        if settings.logoImage == nil { hidden.insert("logo") }
        if patientName.trimmingCharacters(in: .whitespaces).isEmpty { hidden.insert("patient") }

        self.init(values: values, rows: rows, hiddenSections: hidden)
    }

    static func imageMIMEType(_ data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8]) { return "image/jpeg" }
        if data.starts(with: Array("GIF8".utf8)) { return "image/gif" }
        return "image/png"
    }
}
