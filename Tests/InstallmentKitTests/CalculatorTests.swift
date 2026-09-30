import XCTest
@testable import InstallmentKit

final class CalculatorTests: XCTestCase {
    let start = YearMonth(year: 2026, month: 10)

    private func input(_ principal: Int, rate: String, _ mode: CalculationMode, bonus: BonusPlan? = nil) -> LoanInput {
        LoanInput(principal: principal, annualRatePercent: Decimal(string: rate)!, mode: mode,
                  bonus: bonus, firstPaymentMonth: start)
    }

    /// 各行の整合性: 元本充当 = 支払額 − 利息、残高の推移、最終残高0、元本充当の合計 = 元本。
    private func assertConsistent(_ result: LoanResult, file: StaticString = #filePath, line: UInt = #line) {
        var balance = result.input.principal
        for row in result.schedule {
            XCTAssertEqual(row.principalPortion, row.payment - row.interest, file: file, line: line)
            balance -= row.principalPortion
            XCTAssertEqual(row.balance, balance, "row \(row.number)", file: file, line: line)
        }
        XCTAssertEqual(result.schedule.last?.balance, 0, file: file, line: line)
        XCTAssertEqual(result.schedule.reduce(0) { $0 + $1.principalPortion }, result.input.principal, file: file, line: line)
        XCTAssertEqual(result.totalInterest, result.schedule.reduce(0) { $0 + $1.interest }, file: file, line: line)
        XCTAssertEqual(result.schedule.map(\.number), Array(1...result.schedule.count), file: file, line: line)
    }

    // 年率あり・ボーナスなし・モード②
    // PMT(3%/12, 36, -1000000) = 29,081.2096… → 切り捨てで 29,081円。
    func testMode2WithInterestNoBonus() throws {
        let result = try Calculator.calculate(input(1_000_000, rate: "3", .fromInstallments(36)))
        XCTAssertEqual(result.monthlyPayment, 29_081)
        XCTAssertEqual(result.installments, 36)
        XCTAssertEqual(result.schedule.first?.interest, 2_500)  // 1,000,000 × 0.25%
        XCTAssertEqual(result.schedule.dropLast().map(\.payment), Array(repeating: 29_081, count: 35))
        // 利息を毎月切り捨てているため、最終回は月額より少し小さくなる（表計算で検算した値）。
        XCTAssertEqual(result.lastPayment, 29_069)
        XCTAssertEqual(result.totalPayment, 29_081 * 35 + 29_069)
        XCTAssertEqual(result.totalInterest, 46_904)
        XCTAssertEqual(result.schedule.last?.month, YearMonth(year: 2029, month: 9))
        assertConsistent(result)
    }

    // 年率あり・ボーナスなし・モード①: ②の月額を入れると36回に戻る
    func testMode1RoundTripsMode2() throws {
        let mode2 = try Calculator.calculate(input(1_000_000, rate: "3", .fromInstallments(36)))
        let mode1 = try Calculator.calculate(input(1_000_000, rate: "3", .fromMonthlyPayment(mode2.monthlyPayment)))
        XCTAssertEqual(mode1.installments, 36)
        XCTAssertEqual(mode1.schedule, mode2.schedule)
        assertConsistent(mode1)

        // 公式 n = −ln(1 − A·r/P) / ln(1 + r) では 36.00… になる（月額を円未満切り捨てした分だけ36を超える）。
        // この超過分は最終回に合算するため、回数は36回のまま。
        let n = Calculator.installmentsFormula(principal: 1_000_000, monthlyRate: 0.0025, payment: 29_081)!
        XCTAssertEqual(n, 36, accuracy: 0.001)
    }

    // 丸め方向・金利・回数を変えても、②の月額を①に入れると同じ回数に戻る
    func testRoundTripAcrossConditions() throws {
        for rate in ["0", "1.5", "3", "7.8", "15", "29.9"] {
            for n in [1, 2, 3, 12, 24, 36, 60, 84, 120] {
                for rounding in RoundingRule.allCases {
                    let options = CalculationOptions(rounding: rounding)
                    let m2 = try Calculator.calculate(input(987_654, rate: rate, .fromInstallments(n)), options: options)
                    let m1 = try Calculator.calculate(input(987_654, rate: rate, .fromMonthlyPayment(m2.monthlyPayment)), options: options)
                    XCTAssertEqual(m1.installments, n, "rate \(rate) n \(n) \(rounding)")
                    assertConsistent(m2)
                    assertConsistent(m1)
                }
            }
        }
    }

    // 年率0%: 月額 = 元本 ÷ 回数、利息0円
    func testZeroRate() throws {
        let result = try Calculator.calculate(input(1_000_000, rate: "0", .fromInstallments(36)))
        XCTAssertEqual(result.monthlyPayment, 27_777)  // 27,777.77… を切り捨て
        XCTAssertEqual(result.lastPayment, 1_000_000 - 27_777 * 35)
        XCTAssertEqual(result.totalInterest, 0)
        XCTAssertEqual(result.totalPayment, 1_000_000)
        XCTAssertTrue(result.schedule.allSatisfy { $0.interest == 0 })
        assertConsistent(result)

        let exact = try Calculator.calculate(input(360_000, rate: "0", .fromInstallments(12)))
        XCTAssertEqual(Set(exact.schedule.map(\.payment)), [30_000])

        // ①: 回数 = 元本 ÷ 月額 の切り上げ
        let mode1 = try Calculator.calculate(input(100_000, rate: "0", .fromMonthlyPayment(30_000)))
        XCTAssertEqual(mode1.installments, 4)
        XCTAssertEqual(mode1.lastPayment, 10_000)
    }

    func testRoundingRules() throws {
        let up = try Calculator.calculate(input(1_000_000, rate: "3", .fromInstallments(36)),
                                          options: .init(rounding: .up))
        XCTAssertEqual(up.monthlyPayment, 29_082)
        XCTAssertLessThan(up.lastPayment, 29_082 + 1)
        assertConsistent(up)

        let nearest = try Calculator.calculate(input(1_000_000, rate: "3", .fromInstallments(36)),
                                               options: .init(rounding: .nearest))
        XCTAssertEqual(nearest.monthlyPayment, 29_081)
        assertConsistent(nearest)
    }

    // 差額を初回で調整: 最終回が通常の月額とほぼ同じになり、初回で差を吸収する
    func testAdjustFirstPayment() throws {
        let result = try Calculator.calculate(input(1_000_000, rate: "0", .fromInstallments(36)),
                                              options: .init(adjustment: .first))
        XCTAssertEqual(result.monthlyPayment, 27_777)
        XCTAssertEqual(result.firstPayment, 1_000_000 - 27_777 * 35)
        XCTAssertEqual(result.schedule.dropFirst().map(\.payment), Array(repeating: 27_777, count: 35))
        assertConsistent(result)

        let withRate = try Calculator.calculate(input(1_000_000, rate: "3", .fromInstallments(36)),
                                                options: .init(adjustment: .first))
        XCTAssertEqual(withRate.installments, 36)
        XCTAssertLessThanOrEqual(abs(withRate.lastPayment - 29_081), 2)
        XCTAssertEqual(withRate.schedule.dropFirst().dropLast().map(\.payment), Array(repeating: 29_081, count: 34))
        assertConsistent(withRate)
    }

    // ボーナスあり（年2回、月を指定）: 最終回でちょうど残高0になる
    func testBonusMode2EndsAtZero() throws {
        let bonus = BonusPlan(amount: 50_000, months: [6, 12])
        let result = try Calculator.calculate(input(1_000_000, rate: "3", .fromInstallments(36), bonus: bonus))
        XCTAssertEqual(result.installments, 36)
        XCTAssertEqual(result.schedule.last?.balance, 0)
        // 36回（2026年10月〜2029年9月）に含まれるボーナス月は 6月×3回・12月×3回
        XCTAssertEqual(result.schedule.filter { $0.bonusAddition > 0 }.count, 6)
        XCTAssertEqual(result.totalBonus, 300_000)
        for row in result.schedule where [6, 12].contains(row.month.month) {
            XCTAssertEqual(row.bonusAddition, 50_000)
            XCTAssertEqual(row.payment, result.monthlyPayment + 50_000)
        }
        // ボーナスの分だけ月額は下がる
        XCTAssertLessThan(result.monthlyPayment, 29_081)
        // 最終回の調整額はごくわずか
        XCTAssertLessThanOrEqual(abs(result.lastPayment - result.monthlyPayment), 36)
        assertConsistent(result)

        // ①に月額を入れると同じ回数に戻る
        let mode1 = try Calculator.calculate(input(1_000_000, rate: "3", .fromMonthlyPayment(result.monthlyPayment), bonus: bonus))
        XCTAssertEqual(mode1.installments, 36)
        assertConsistent(mode1)
    }

    func testBonusMode1() throws {
        let bonus = BonusPlan(amount: 100_000, months: [7, 12])
        let result = try Calculator.calculate(input(800_000, rate: "5", .fromMonthlyPayment(10_000), bonus: bonus))
        let withoutBonus = try Calculator.calculate(input(800_000, rate: "5", .fromMonthlyPayment(10_000)))
        XCTAssertLessThan(result.installments, withoutBonus.installments)
        assertConsistent(result)
        assertConsistent(withoutBonus)
    }

    // 月額が利息を下回っても、ボーナスで元本が減るなら完済できる
    func testBonusCoversShortfall() throws {
        // 月利1%で利息は月1万円。月額5,000円だけでは減らないが、ボーナス年2回×10万円で減る。
        let bonus = BonusPlan(amount: 100_000, months: [6, 12])
        let result = try Calculator.calculate(input(1_000_000, rate: "12", .fromMonthlyPayment(5_000), bonus: bonus))
        assertConsistent(result)
    }

    // 完済不能な条件でエラーになる
    func testCannotRepay() {
        // 月利0.25%で初月の利息は2,500円。月額2,500円では元本が減らない。
        XCTAssertThrowsError(try Calculator.calculate(input(1_000_000, rate: "3", .fromMonthlyPayment(2_500)))) {
            XCTAssertEqual($0 as? CalculationError, .cannotRepay)
        }
        XCTAssertThrowsError(try Calculator.calculate(input(1_000_000, rate: "3", .fromMonthlyPayment(1_000)))) {
            XCTAssertEqual($0 as? CalculationError, .cannotRepay)
        }
        // ボーナスがあっても1年で元本が減らなければエラー
        let bonus = BonusPlan(amount: 1_000, months: [6])
        XCTAssertThrowsError(try Calculator.calculate(input(1_000_000, rate: "12", .fromMonthlyPayment(5_000), bonus: bonus))) {
            XCTAssertEqual($0 as? CalculationError, .cannotRepay)
        }
        // 元本は減るが上限回数を超える
        XCTAssertThrowsError(try Calculator.calculate(input(10_000_000, rate: "0", .fromMonthlyPayment(1_000)))) {
            XCTAssertEqual($0 as? CalculationError, .tooManyInstallments(limit: Calculator.maximumInstallments))
        }
    }

    func testValidation() {
        let cases: [(LoanInput, CalculationError)] = [
            (input(0, rate: "3", .fromInstallments(12)), .invalidPrincipal),
            (input(-1, rate: "3", .fromInstallments(12)), .invalidPrincipal),
            (input(100_000, rate: "-0.1", .fromInstallments(12)), .invalidRate),
            (input(100_000, rate: "30.01", .fromInstallments(12)), .invalidRate),
            (input(100_000, rate: "3", .fromInstallments(0)), .invalidInstallments),
            (input(100_000, rate: "3", .fromMonthlyPayment(0)), .invalidMonthlyPayment),
            (input(100_000, rate: "3", .fromInstallments(12), bonus: BonusPlan(amount: 1, months: [13])), .invalidBonusMonth),
            (input(100_000, rate: "3", .fromInstallments(12), bonus: BonusPlan(amount: 200_000, months: [6, 12])), .bonusTooLarge),
        ]
        for (value, expected) in cases {
            XCTAssertThrowsError(try Calculator.calculate(value)) { XCTAssertEqual($0 as? CalculationError, expected) }
        }
    }

    func testFormulas() {
        XCTAssertEqual(Calculator.monthlyPaymentFormula(principal: 1_000_000, monthlyRate: 0.0025, installments: 36),
                       29_081.2096, accuracy: 0.001)
        XCTAssertEqual(Calculator.monthlyPaymentFormula(principal: 1_200, monthlyRate: 0, installments: 12), 100)
        XCTAssertNil(Calculator.installmentsFormula(principal: 1_000_000, monthlyRate: 0.0025, payment: 2_500))
    }

    func testYearMonth() {
        XCTAssertEqual(YearMonth(year: 2026, month: 11).adding(months: 2), YearMonth(year: 2027, month: 1))
        XCTAssertEqual(YearMonth(year: 2026, month: 1).adding(months: 11), YearMonth(year: 2026, month: 12))
        XCTAssertEqual(YearMonth(year: 2026, month: 12).adding(months: 24), YearMonth(year: 2028, month: 12))
    }
}
