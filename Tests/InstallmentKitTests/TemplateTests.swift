import XCTest
@testable import InstallmentKit

final class TemplateTests: XCTestCase {
    let template = """
    <h1>{{clinic_name}}</h1><p>{{ patient_name }}様</p>
    <p data-show="interest">利息 {{total_interest}}円</p>
    <table>
    <!-- ROW_START -->
    <tr>
      <td>{{row.no}}</td>
      <td>{{row.month}}</td>
      <td>{{row.payment}}</td>
      <td data-show="interest">{{row.interest}}</td>
      <td>{{row.balance}}</td>
    </tr>
    <!-- ROW_END -->
    </table>
    <p>{{unknown}}</p>
    """

    func makeResult() throws -> LoanResult {
        try Calculator.calculate(LoanInput(principal: 120_000, annualRatePercent: 6, mode: .fromInstallments(3),
                                           firstPaymentMonth: YearMonth(year: 2026, month: 11)))
    }

    func testRowsAreRepeatedAndValuesEscaped() throws {
        let result = try makeResult()
        var settings = AppSettings()
        settings.clinicName = "A&B <歯科>"
        let context = TemplateContext(result: result, settings: settings, patientName: "山田 太郎", showInterest: true)
        let html = TemplateRenderer.render(template, context: context)

        XCTAssertTrue(html.contains("<h1>A&amp;B &lt;歯科&gt;</h1>"))
        XCTAssertTrue(html.contains("<p>山田 太郎様</p>"))
        XCTAssertEqual(html.components(separatedBy: "<tr>").count - 1, 3)
        XCTAssertTrue(html.contains("<td>2026年11月</td>"))
        XCTAssertTrue(html.contains("<td>2027年1月</td>"))
        XCTAssertTrue(html.contains(">600</td>"))  // 初回の利息 120,000 × 0.5%
        XCTAssertTrue(html.contains("利息 \(DisplayFormat.yen(result.totalInterest))円"))
        XCTAssertFalse(html.contains("ROW_START"))
        XCTAssertTrue(html.contains("{{unknown}}"))
    }

    func testInterestHidden() throws {
        let result = try makeResult()
        let context = TemplateContext(result: result, settings: AppSettings(), patientName: "", showInterest: false)
        let html = TemplateRenderer.render(template, context: context)

        XCTAssertFalse(html.contains("data-show=\"interest\""))
        XCTAssertFalse(html.contains("利息"))
        XCTAssertFalse(html.contains(">600<"))
        XCTAssertEqual(html.components(separatedBy: "<td>").count - 1, 3 * 4)
        XCTAssertEqual(context.values["total_interest"], "")
    }

    func testRemoveNestedElements() {
        let html = """
        <div>A<div data-show='interest'>B<div>C</div>D<br><img src="x"/></div>E</div>\
        <img data-show="interest" src="y">F<span data-show="interest"/>G
        """
        XCTAssertEqual(TemplateRenderer.removeElements(showing: "interest", in: html), "<div>AE</div>FG")
    }

    func testBonusSectionHiddenWithoutBonus() throws {
        let html = #"<tr data-show="bonus"><td>{{bonus_amount}}</td></tr>ok"#
        let noBonus = TemplateContext(result: try makeResult(), settings: AppSettings(), patientName: "", showInterest: false)
        XCTAssertEqual(TemplateRenderer.render(html, context: noBonus), "ok")

        let withBonus = try Calculator.calculate(LoanInput(
            principal: 500_000, annualRatePercent: 3, mode: .fromInstallments(12),
            bonus: BonusPlan(amount: 30_000, months: [12, 6]), firstPaymentMonth: YearMonth(year: 2026, month: 11)))
        let context = TemplateContext(result: withBonus, settings: AppSettings(), patientName: "", showInterest: false)
        XCTAssertEqual(TemplateRenderer.render(html, context: context), #"<tr data-show="bonus"><td>30,000</td></tr>ok"#)
        XCTAssertEqual(context.values["bonus_months"], "6月・12月")
    }

    func testDefaultTemplateRenders() throws {
        let template = TemplateLibrary.bundledDefaultTemplate
        XCTAssertTrue(template.contains(TemplateRenderer.rowStartMarker))
        let result = try makeResult()
        let shown = TemplateRenderer.render(template, context: TemplateContext(
            result: result, settings: AppSettings(), patientName: "山田", showInterest: true))
        let hidden = TemplateRenderer.render(template, context: TemplateContext(
            result: result, settings: AppSettings(), patientName: "山田", showInterest: false))

        XCTAssertFalse(shown.contains("{{"), "未置換のプレースホルダーが残っている")
        XCTAssertFalse(hidden.contains("{{"))
        XCTAssertTrue(shown.contains("うち利息"))
        XCTAssertFalse(hidden.contains("うち利息"))
        XCTAssertFalse(hidden.contains("data-show=\"interest\""))
        XCTAssertTrue(hidden.contains("山田 様"))
        XCTAssertFalse(hidden.contains("<img"))  // ロゴ未設定なら img を出さない
    }

    func testTemplateLibrary() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tpl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = TemplateLibrary(directory: dir)
        try library.prepare()
        XCTAssertEqual(library.availableTemplates(), ["default.html"])

        // 利用者が編集した既定テンプレートは上書きしない
        try "custom".write(to: dir.appendingPathComponent("default.html"), atomically: true, encoding: .utf8)
        try library.prepare()
        XCTAssertEqual(library.load(named: "default.html"), "custom")

        let source = FileManager.default.temporaryDirectory.appendingPathComponent("simple-\(UUID().uuidString).html")
        try "<p>x</p>".write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }
        let name = try library.importTemplate(from: source)
        XCTAssertEqual(library.availableTemplates().count, 2)
        XCTAssertEqual(library.load(named: name), "<p>x</p>")
        XCTAssertEqual(library.load(named: "missing.html"), TemplateLibrary.bundledDefaultTemplate)
    }

    func testLoanFormParsing() throws {
        var form = LoanForm()
        form.principalText = "１,０００,０００円"
        form.rateText = "３．０%"
        form.installmentsText = "36"
        form.firstPaymentMonth = YearMonth(year: 2026, month: 10)
        let input = try form.makeInput()
        XCTAssertEqual(input.principal, 1_000_000)
        XCTAssertEqual(input.annualRatePercent, 3)
        XCTAssertEqual(input.mode, .fromInstallments(36))
        XCTAssertNil(input.bonus)

        form.installmentsText = "3.5"
        XCTAssertThrowsError(try form.makeInput()) { XCTAssertEqual($0 as? CalculationError, .invalidInstallments) }
        form.installmentsText = "36"
        form.rateText = "abc"
        XCTAssertThrowsError(try form.makeInput()) { XCTAssertEqual($0 as? CalculationError, .invalidRate) }
        form.rateText = "3"
        form.bonusEnabled = true
        form.bonusAmountText = "50,000"
        XCTAssertEqual(try form.makeInput().bonus, BonusPlan(amount: 50_000, months: [6, 12]))

        form.mode = .fromMonthlyPayment
        XCTAssertFalse(form.isReadyToCalculate)
        form.monthlyPaymentText = "29081"
        XCTAssertEqual(try form.makeInput().mode, .fromMonthlyPayment(29_081))
    }

    func testDisplayFormat() {
        XCTAssertEqual(DisplayFormat.yen(0), "0")
        XCTAssertEqual(DisplayFormat.yen(999), "999")
        XCTAssertEqual(DisplayFormat.yen(1_000), "1,000")
        XCTAssertEqual(DisplayFormat.yen(1_234_567), "1,234,567")
        XCTAssertEqual(DisplayFormat.yen(-46_904), "-46,904")
        XCTAssertEqual(DisplayFormat.rate(Decimal(string: "2.50")!), "2.5")
        XCTAssertEqual(DisplayFormat.rate(15), "15")
    }
}
