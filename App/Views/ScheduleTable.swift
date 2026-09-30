import SwiftUI
import InstallmentKit

/// 支払いスケジュール表（仕様 5.4）。利息列は利息総額と同じく伏せる。
struct ScheduleTable: View {
    @Environment(AppModel.self) var model
    let result: LoanResult

    private var showsBonus: Bool { result.totalBonus > 0 }

    var body: some View {
        let theme = model.settings.theme
        let revealed = model.interestRevealed
        let mask = model.settings.interestMaskText

        Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("回")
                Text("支払月")
                Text("支払額")
                if showsBonus { Text("うちボーナス") }
                Text("元本充当")
                Text("利息")
                Text("残高")
            }
            .font(theme.label.weight(.semibold))
            .foregroundStyle(.secondary)

            Divider().gridCellUnsizedAxes(.horizontal)

            ForEach(result.schedule, id: \.number) { row in
                GridRow {
                    Text(verbatim: "\(row.number)")
                    Text(DisplayFormat.month(row.month))
                    Text(DisplayFormat.yen(row.payment))
                    if showsBonus { Text(row.bonusAddition > 0 ? DisplayFormat.yen(row.bonusAddition) : "") }
                    Text(DisplayFormat.yen(row.principalPortion))
                    Text(revealed ? DisplayFormat.yen(row.interest) : mask).foregroundStyle(.secondary)
                    Text(DisplayFormat.yen(row.balance))
                }
                .monospacedDigit()
            }
        }
        .font(theme.label)
        .textSelection(.enabled)
    }
}
