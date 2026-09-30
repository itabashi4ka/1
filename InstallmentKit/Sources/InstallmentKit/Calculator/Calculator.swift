import Foundation

/// 分割払い（元利均等）の計算。UIには依存しない。
///
/// 毎月の処理（ボーナスの有無にかかわらず共通）:
/// 1. 利息 = 残高 × 月利（端数処理ルールで円に丸める）
/// 2. 支払額 = 月額（ボーナス月は月額 + ボーナス加算額）
/// 3. 元本充当 = 支払額 − 利息
/// 4. 残高 = 残高 − 元本充当
/// 最終回は、残高と利息をちょうど払い切る額に調整する（残高は必ず0で終わる）。
public enum Calculator {
    /// これを超える年率は入力ミスとみなしてエラーにする。
    public static let maximumAnnualRatePercent: Decimal = 30
    /// 分割回数の上限（50年）。
    public static let maximumInstallments = 600

    public static func calculate(_ input: LoanInput, options: CalculationOptions = .init()) throws -> LoanResult {
        try validate(input)
        let sim = Simulator(input: input, rounding: options.rounding)

        switch input.mode {
        case .fromInstallments(let n):
            let payment = try solveMonthlyPayment(input, installments: n, rounding: options.rounding)
            var schedule = sim.run(regularPayment: payment, installments: n)
            if options.adjustment == .first, n > 1 {
                schedule = adjustFirstPayment(sim: sim, regularPayment: payment, installments: n, fallback: schedule)
            }
            return LoanResult(input: input, monthlyPayment: payment, schedule: schedule)

        case .fromMonthlyPayment(let payment):
            let schedule = try sim.runUntilRepaid(regularPayment: payment, limit: maximumInstallments)
            return LoanResult(input: input, monthlyPayment: payment, schedule: schedule)
        }
    }

    // MARK: - 入力チェック

    public static func validate(_ input: LoanInput) throws {
        guard input.principal > 0 else { throw CalculationError.invalidPrincipal }
        guard input.annualRatePercent >= 0, input.annualRatePercent <= maximumAnnualRatePercent else {
            throw CalculationError.invalidRate
        }
        switch input.mode {
        case .fromInstallments(let n):
            guard n >= 1 else { throw CalculationError.invalidInstallments }
            guard n <= maximumInstallments else { throw CalculationError.tooManyInstallments(limit: maximumInstallments) }
        case .fromMonthlyPayment(let p):
            guard p >= 1 else { throw CalculationError.invalidMonthlyPayment }
        }
        if let bonus = input.bonus {
            guard bonus.amount >= 0 else { throw CalculationError.invalidBonusAmount }
            guard bonus.months.allSatisfy({ (1...12).contains($0) }) else { throw CalculationError.invalidBonusMonth }
        }
    }

    // MARK: - 公式（ボーナスなし）

    /// ボーナスなしの月額: r > 0 なら A × r ÷ (1 − (1 + r)^−n)、r = 0 なら A ÷ n（丸める前の値）。
    public static func monthlyPaymentFormula(principal: Double, monthlyRate r: Double, installments n: Int) -> Double {
        if r == 0 { return principal / Double(n) }
        return principal * r / (1 - pow(1 + r, -Double(n)))
    }

    /// ボーナスなしの回数: r > 0 なら −ln(1 − A × r ÷ P) ÷ ln(1 + r)、r = 0 なら A ÷ P（切り上げ前の値）。
    /// 月額が利息以下なら nil（完済不能）。
    public static func installmentsFormula(principal: Double, monthlyRate r: Double, payment: Double) -> Double? {
        if r == 0 { return principal / payment }
        let x = 1 - principal * r / payment
        guard x > 0 else { return nil }
        return -log(x) / log(1 + r)
    }

    // MARK: - モード②: 月額を求める

    /// n回ちょうどで残高が0になる月額（ボーナスを除く）を求め、端数処理ルールで円に丸める。
    ///
    /// 各回の支払いを現在価値に割り引いた合計が元本と等しくなる条件
    ///   A = Σ (P + B_k) / (1 + r)^k
    /// は P について1次式なので直接解ける（ボーナスなしのときは公式と一致する）。
    static func solveMonthlyPayment(_ input: LoanInput, installments n: Int, rounding: RoundingRule) throws -> Int {
        let r = NSDecimalNumber(decimal: input.monthlyRate).doubleValue
        let bonus = input.bonus ?? BonusPlan(amount: 0, months: [])
        var annuity = 0.0        // Σ 1 / (1 + r)^k
        var bonusValue = 0.0     // Σ B_k / (1 + r)^k
        var discount = 1.0
        for k in 1...n {
            discount /= (1 + r)
            annuity += discount
            bonusValue += Double(bonus.addition(for: input.firstPaymentMonth.adding(months: k - 1))) * discount
        }
        let exact = (Double(input.principal) - bonusValue) / annuity
        let payment = rounding.apply(exact)
        guard payment >= 1 else {
            throw bonus.isActive ? CalculationError.bonusTooLarge : CalculationError.invalidPrincipal
        }
        return payment
    }

    /// 差額を初回で調整する: 最終回がなるべく通常の支払額と同じになるように初回の額を決める。
    static func adjustFirstPayment(sim: Simulator, regularPayment: Int, installments n: Int,
                                   fallback: [ScheduleRow]) -> [ScheduleRow] {
        guard let last = fallback.last, fallback.count == n else { return fallback }
        let expectedLast = regularPayment + last.bonusAddition
        // 最終回の差額を初回時点の価値に割り戻した額が、初回の調整額の目安。
        let growth = pow(1 + NSDecimalNumber(decimal: sim.rate).doubleValue, Double(n - 1))
        let estimate = regularPayment + Int((Double(last.payment - expectedLast) / growth).rounded())

        var best = fallback
        var bestGap = abs(last.payment - expectedLast)
        for first in (estimate - 3)...(estimate + 3) where first >= 1 {
            let candidate = sim.run(regularPayment: regularPayment, installments: n, firstPayment: first)
            guard candidate.count == n, let candidateLast = candidate.last else { continue }
            let gap = abs(candidateLast.payment - expectedLast)
            // 同じ差なら、最終回が通常額以下になるほう（初回に寄せる）を選ぶ。
            if gap < bestGap || (gap == bestGap && candidateLast.payment <= expectedLast && best.last!.payment > expectedLast) {
                best = candidate
                bestGap = gap
            }
        }
        return best
    }
}

/// 月ごとの残高シミュレーション。
struct Simulator {
    let principal: Int
    let rate: Decimal
    let rounding: RoundingRule
    let bonus: BonusPlan
    let firstMonth: YearMonth

    init(input: LoanInput, rounding: RoundingRule) {
        principal = input.principal
        rate = input.monthlyRate
        self.rounding = rounding
        bonus = input.bonus ?? BonusPlan(amount: 0, months: [])
        firstMonth = input.firstPaymentMonth
    }

    func interest(on balance: Int) -> Int {
        balance <= 0 ? 0 : rounding.apply(Decimal(balance) * rate)
    }

    /// 回数を決めて支払う（モード②）。最終回は残高に合わせて調整する。
    /// 途中で完済できた場合はその回で終わる。
    func run(regularPayment: Int, installments n: Int, firstPayment: Int? = nil) -> [ScheduleRow] {
        var rows: [ScheduleRow] = []
        var balance = principal
        for k in 1...n {
            let month = firstMonth.adding(months: k - 1)
            let interest = interest(on: balance)
            let bonusAddition = bonus.addition(for: month)
            let base = (k == 1 ? firstPayment : nil) ?? regularPayment
            let due = balance + interest
            if k == n || base + bonusAddition >= due {
                rows.append(finalRow(k, month, due: due, interest: interest, bonusAddition: bonusAddition))
                break
            }
            let payment = base + bonusAddition
            balance -= payment - interest
            rows.append(ScheduleRow(number: k, month: month, payment: payment, bonusAddition: bonusAddition,
                                    principalPortion: payment - interest, interest: interest, balance: balance))
        }
        return rows
    }

    /// 月額を決めて完済まで支払う（モード①）。
    ///
    /// 月額を円に丸めたことによる残り（1回あたり1円未満の積み重ね）だけが残った場合は、
    /// 新しい回を作らずその回に合算する。これにより、モード②で求めた月額をモード①に
    /// 入れると同じ回数に戻る。
    func runUntilRepaid(regularPayment: Int, limit: Int) throws -> [ScheduleRow] {
        var rows: [ScheduleRow] = []
        var balance = principal
        var checkpoint = principal
        let growth = 1 + NSDecimalNumber(decimal: rate).doubleValue
        var roundingSlack = 0.0  // 丸めで生じうる残りの上限: Σ (1 + r)^j

        if !bonus.isActive, regularPayment <= interest(on: principal) {
            throw CalculationError.cannotRepay
        }

        var k = 0
        while true {
            k += 1
            guard k <= limit else { throw CalculationError.tooManyInstallments(limit: limit) }
            let month = firstMonth.adding(months: k - 1)
            let interest = interest(on: balance)
            let bonusAddition = bonus.addition(for: month)
            let due = balance + interest
            var payment = regularPayment + bonusAddition
            if payment >= due {
                rows.append(finalRow(k, month, due: due, interest: interest, bonusAddition: bonusAddition))
                return rows
            }
            balance -= payment - interest
            roundingSlack = roundingSlack * growth + 1
            let tolerance = min(Int(roundingSlack), regularPayment / 2)
            if balance <= tolerance {
                payment += balance
                balance = 0
            }
            rows.append(ScheduleRow(number: k, month: month, payment: payment, bonusAddition: bonusAddition,
                                    principalPortion: payment - interest, interest: interest, balance: balance))
            if balance == 0 { return rows }

            // 1年ごとに残高が減っているか確認する（ボーナス月の支払いも含めて判定）。
            if k % 12 == 0 {
                if balance >= checkpoint { throw CalculationError.cannotRepay }
                checkpoint = balance
            }
        }
    }

    private func finalRow(_ k: Int, _ month: YearMonth, due: Int, interest: Int, bonusAddition: Int) -> ScheduleRow {
        ScheduleRow(number: k, month: month, payment: due, bonusAddition: min(bonusAddition, due),
                    principalPortion: due - interest, interest: interest, balance: 0)
    }
}
