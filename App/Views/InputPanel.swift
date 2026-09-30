import SwiftUI
import InstallmentKit

/// 入力エリア（仕様 5.1）。
struct InputPanel: View {
    @Environment(AppModel.self) var model

    var body: some View {
        @Bindable var model = model
        let theme = model.settings.theme

        VStack(alignment: .leading, spacing: 18) {
            Picker("計算モード", selection: $model.form.mode) {
                ForEach(LoanForm.Mode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)

            FieldRow(title: "支払総額（税込）", unit: "円") {
                AmountField(placeholder: "1,000,000", text: $model.form.principalText)
            }

            RateInput()

            if model.form.mode == .fromInstallments {
                FieldRow(title: "分割回数", unit: "回") {
                    AmountField(placeholder: "36", text: $model.form.installmentsText)
                }
            } else {
                FieldRow(title: model.form.bonusEnabled ? "月額（ボーナスを除く）" : "月額", unit: "円") {
                    AmountField(placeholder: "30,000", text: $model.form.monthlyPaymentText)
                }
            }

            BonusInput()

            FieldRow(title: "初回支払月", unit: nil) {
                MonthPicker(value: $model.form.firstPaymentMonth)
            }

            FieldRow(title: "患者名（任意・保存されません）", unit: "様") {
                TextField("山田 太郎", text: $model.form.patientName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }
        }
        .font(theme.body)
    }
}

/// 見出し + 入力欄 + 単位
struct FieldRow<Content: View>: View {
    @Environment(AppModel.self) var model
    let title: String
    let unit: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(model.settings.theme.label)
                .foregroundStyle(.secondary)
            HStack {
                content
                if let unit {
                    Text(unit).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 数値入力欄（全角数字・カンマも可）。
struct AmountField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .autocorrectionDisabled()
            #if os(iOS)
            .keyboardType(.decimalPad)
            .frame(minHeight: Theme.minimumTapHeight)
            #endif
    }
}

/// 年率の入力欄。既定値と違うときは色と注意書きで知らせる（仕様 7.2）。
struct RateInput: View {
    @Environment(AppModel.self) var model

    var body: some View {
        @Bindable var model = model
        let differs = model.rate.differsFromDefault
        let theme = model.settings.theme

        FieldRow(title: "年率", unit: "%") {
            AmountField(placeholder: "0", text: $model.rate.text)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(differs ? theme.accent : .clear, lineWidth: 2)
                )
        }

        HStack(spacing: 10) {
            if differs {
                Label("既定値（\(DisplayFormat.rate(model.rate.defaultRate))%）と異なります", systemImage: "exclamationmark.triangle.fill")
                    .font(theme.label)
                    .foregroundStyle(theme.accent)
                Spacer(minLength: 0)
                Button("既定に戻す") { model.rate.resetToDefault() }
                Button("この値を既定にする") { model.makeCurrentRateDefault() }
                    .disabled(model.rate.value == nil)
            } else {
                Label("既定の年率", systemImage: "checkmark.circle")
                    .font(theme.label)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// ボーナス払いの入力。
struct BonusInput: View {
    @Environment(AppModel.self) var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 10) {
            Toggle("ボーナス払い", isOn: $model.form.bonusEnabled)
                .toggleStyle(.switch)

            if model.form.bonusEnabled {
                FieldRow(title: "ボーナス月の加算額", unit: "円") {
                    AmountField(placeholder: "50,000", text: $model.form.bonusAmountText)
                }
                Text("ボーナス月")
                    .font(model.settings.theme.label)
                    .foregroundStyle(.secondary)
                MonthSelector(selection: $model.form.bonusMonths)
            }
        }
    }
}

/// 1〜12月から複数選択。
struct MonthSelector: View {
    @Environment(AppModel.self) var model
    @Binding var selection: Set<Int>

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(1...12, id: \.self) { month in
                let selected = selection.contains(month)
                Button {
                    if selected { selection.remove(month) } else { selection.insert(month) }
                } label: {
                    Text("\(month)月")
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(selected ? model.settings.theme.primary : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// 年・月の選択。
struct MonthPicker: View {
    @Binding var value: YearMonth

    private var years: [Int] {
        let current = YearMonth.nextMonth().year
        return Array(min(current - 1, value.year)...max(current + 5, value.year))
    }

    var body: some View {
        HStack {
            Picker("年", selection: Binding(get: { value.year }, set: { value = YearMonth(year: $0, month: value.month) })) {
                ForEach(years, id: \.self) { Text(verbatim: "\($0)年").tag($0) }
            }
            .labelsHidden()
            Picker("月", selection: Binding(get: { value.month }, set: { value = YearMonth(year: value.year, month: $0) })) {
                ForEach(1...12, id: \.self) { Text("\($0)月").tag($0) }
            }
            .labelsHidden()
            Spacer(minLength: 0)
        }
    }
}
