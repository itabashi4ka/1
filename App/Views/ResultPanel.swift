import SwiftUI
import InstallmentKit

/// 結果エリア（患者に見せる部分、仕様 5.2〜5.4）。
struct ResultPanel: View {
    @Environment(AppModel.self) var model
    @State private var showingSchedule = true

    var body: some View {
        let theme = model.settings.theme

        VStack(alignment: .leading, spacing: 24) {
            if let error = model.error {
                Label(error.message, systemImage: "exclamationmark.octagon.fill")
                    .font(theme.headline)
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            if let result = model.result {
                MainFigure(result: result, mode: model.form.mode)
                SummaryGrid(result: result)
                InterestRow(result: result)

                DisclosureGroup(isExpanded: $showingSchedule) {
                    ScheduleTable(result: result)
                        .padding(.top, 8)
                } label: {
                    Text("お支払いスケジュール").font(theme.headline)
                }
            } else if model.error == nil {
                Text("支払総額・年率・\(model.form.mode == .fromInstallments ? "分割回数" : "月額")を入力してください。")
                    .font(theme.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }

            Text(model.settings.note)
                .font(theme.label)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }
}

/// 大きく見せる数字（モード②なら月額、モード①なら回数）。
private struct MainFigure: View {
    @Environment(AppModel.self) var model
    let result: LoanResult
    let mode: LoanForm.Mode

    var body: some View {
        let theme = model.settings.theme

        VStack(alignment: .leading, spacing: 8) {
            Text(mode == .fromInstallments ? "月々のお支払い" : "お支払い回数")
                .font(theme.headline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if mode == .fromInstallments {
                    Text(DisplayFormat.yen(result.monthlyPayment)).font(theme.result)
                    Text("円").font(theme.resultUnit)
                    Text("× \(result.installments)回").font(theme.resultUnit).foregroundStyle(.secondary)
                } else {
                    Text(verbatim: "\(result.installments)").font(theme.result)
                    Text("回").font(theme.resultUnit)
                    Text("（月々 \(DisplayFormat.yen(result.monthlyPayment))円）")
                        .font(theme.resultUnit).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(theme.primary)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// 総支払額など。
private struct SummaryGrid: View {
    @Environment(AppModel.self) var model
    let result: LoanResult

    var body: some View {
        let theme = model.settings.theme
        let first = result.schedule.first
        let last = result.schedule.last
        let regular = result.monthlyPayment

        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
            GridRow {
                Text("お支払い合計額").foregroundStyle(.secondary)
                Text("\(DisplayFormat.yen(result.totalPayment))円").font(theme.secondaryResult)
            }
            if let bonus = model.result?.input.bonus, bonus.isActive, result.totalBonus > 0 {
                GridRow {
                    Text("ボーナス月（\(DisplayFormat.months(bonus.months))）").foregroundStyle(.secondary)
                    Text("月額 + \(DisplayFormat.yen(bonus.amount))円").font(theme.headline)
                }
            }
            if let first, first.payment - first.bonusAddition != regular, result.installments > 1 {
                GridRow {
                    Text("初回").foregroundStyle(.secondary)
                    Text("\(DisplayFormat.yen(first.payment))円").font(theme.headline)
                }
            }
            if let last, last.payment - last.bonusAddition != regular, result.installments > 1 {
                GridRow {
                    Text("最終回").foregroundStyle(.secondary)
                    Text("\(DisplayFormat.yen(last.payment))円").font(theme.headline)
                }
            }
            if let first, let last {
                GridRow {
                    Text("お支払い期間").foregroundStyle(.secondary)
                    Text("\(DisplayFormat.month(first.month)) 〜 \(DisplayFormat.month(last.month))").font(theme.headline)
                }
            }
        }
    }
}

/// 利息総額（通常は伏せる。仕様 5.3）。
private struct InterestRow: View {
    @Environment(AppModel.self) var model
    let result: LoanResult

    var body: some View {
        @Bindable var model = model
        let theme = model.settings.theme

        HStack(spacing: 16) {
            Text("利息総額").foregroundStyle(.secondary)
            Text(model.interestRevealed
                 ? "\(DisplayFormat.yen(result.totalInterest))円"
                 : "\(model.settings.interestMaskText)円")
                .font(theme.headline)
                .monospacedDigit()
            Spacer(minLength: 0)
            Button {
                model.interestRevealed.toggle()
            } label: {
                Label(model.interestRevealed ? "利息総額を隠す" : "利息総額を表示",
                      systemImage: model.interestRevealed ? "eye.slash" : "eye")
                    .frame(minHeight: 28)
            }
            .buttonStyle(.bordered)
        }
    }
}
