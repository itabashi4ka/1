import SwiftUI
import UniformTypeIdentifiers
import InstallmentKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 設定画面（仕様 7章）。変更はすぐ settings.json に保存される。
struct SettingsView: View {
    @Environment(AppModel.self) var model

    private enum ImportKind {
        case logo, template, settings

        var contentTypes: [UTType] {
            switch self {
            case .logo: return [.png, .jpeg]
            case .template: return [.html]
            case .settings: return [.json]
            }
        }
    }

    @State private var importKind: ImportKind = .logo
    @State private var showingImporter = false
    @State private var exportingSettings = false
    @State private var confirmingReset = false
    @State private var defaultRateText = ""

    var body: some View {
        @Bindable var model = model

        Form {
            Section("院の情報") {
                TextField("院名", text: $model.settings.clinicName)
                HStack {
                    Text("ロゴ画像")
                    Spacer()
                    if let data = model.settings.logoImage, let image = logoImage(from: data) {
                        image.resizable().scaledToFit().frame(height: 40)
                        Button("削除", role: .destructive) { model.settings.logoImage = nil }
                    }
                    Button("画像を選ぶ…") { startImport(.logo) }
                }
            }

            Section("見た目") {
                ColorPicker("テーマカラー", selection: colorBinding(\.themeColorHex), supportsOpacity: false)
                ColorPicker("強調色（既定値と異なる年率の表示など）", selection: colorBinding(\.accentColorHex), supportsOpacity: false)
                TextField("フォント名（空欄でシステムフォント）", text: $model.settings.fontName)
                    .autocorrectionDisabled()
                HStack {
                    Text("文字サイズ")
                    Slider(value: $model.settings.baseFontSize, in: 12...28, step: 1)
                    Text(verbatim: "\(Int(model.settings.baseFontSize))pt").monospacedDigit()
                }
                HStack {
                    Text("結果の文字サイズ")
                    Slider(value: $model.settings.resultFontSize, in: 32...120, step: 2)
                    Text(verbatim: "\(Int(model.settings.resultFontSize))pt").monospacedDigit()
                }
            }

            Section("文言") {
                TextField("注記文", text: $model.settings.note, axis: .vertical)
                    .lineLimit(2...5)
                TextField("利息を伏せるときの表示", text: $model.settings.interestMaskText)
            }

            Section {
                Picker("端数処理", selection: $model.settings.rounding) {
                    ForEach(RoundingRule.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("差額の調整（回数から求めるとき）", selection: $model.settings.adjustment) {
                    ForEach(AdjustmentPlacement.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                HStack {
                    Text("既定の年率")
                    Spacer()
                    TextField("0", text: $defaultRateText)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                        .onSubmit(applyDefaultRate)
                    Text("%")
                    Button("保存", action: applyDefaultRate)
                        .disabled(NumberParser.decimal(defaultRateText) == model.settings.defaultAnnualRatePercent)
                }
                HStack {
                    Text("ボーナス月の初期値")
                    Spacer()
                }
                MonthSelector(selection: Binding(
                    get: { Set(model.settings.defaultBonusMonths) },
                    set: { model.settings.defaultBonusMonths = $0.sorted() }))
            } header: {
                Text("計算")
            } footer: {
                Text("返済方式は元利均等。月利は年率 ÷ 12 で、日割りはしません。")
            }

            Section {
                Picker("使用するテンプレート", selection: $model.settings.templateFileName) {
                    ForEach(model.templates, id: \.self) { Text($0).tag($0) }
                }
                Button("テンプレートを読み込む…") { startImport(.template) }
                #if os(macOS)
                Button("テンプレートフォルダを開く") {
                    NSWorkspace.shared.open(model.templateLibrary.directory)
                }
                #endif
            } header: {
                Text("支払い表テンプレート")
            } footer: {
                Text("HTMLファイルを templates フォルダに置くと選べるようになります。")
            }

            Section {
                Button("設定を書き出す…") { exportingSettings = true }
                Button("設定を読み込む…") { startImport(.settings) }
                Button("設定を初期状態に戻す", role: .destructive) { confirmingReset = true }
            } header: {
                Text("設定の移行")
            } footer: {
                Text("書き出したファイルを別のMacやiPadで読み込むと、同じ設定（ロゴ・既定の年率を含む）になります。テンプレートは別途コピーしてください。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("設定")
        .onAppear {
            model.refreshTemplates()
            defaultRateText = DisplayFormat.rate(model.settings.defaultAnnualRatePercent)
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: importKind.contentTypes) { result in
            guard case .success(let url) = result else { return }
            switch importKind {
            case .logo: model.setLogo(from: url)
            case .template: model.importTemplate(from: url)
            case .settings:
                model.importSettings(from: url)
                defaultRateText = DisplayFormat.rate(model.settings.defaultAnnualRatePercent)
            }
        }
        .fileExporter(isPresented: $exportingSettings,
                      document: try? SettingsFile(data: model.exportSettingsData()),
                      contentType: .json,
                      defaultFilename: "InstallmentCalculator-settings.json") { result in
            if case .failure(let error) = result {
                model.lastErrorMessage = "書き出せませんでした: \(error.localizedDescription)"
            }
        }
        .confirmationDialog("設定を初期状態に戻しますか？", isPresented: $confirmingReset) {
            Button("初期状態に戻す", role: .destructive) {
                model.resetSettings()
                defaultRateText = DisplayFormat.rate(model.settings.defaultAnnualRatePercent)
            }
        }
    }

    private func startImport(_ kind: ImportKind) {
        importKind = kind
        showingImporter = true
    }

    private func applyDefaultRate() {
        guard let value = NumberParser.decimal(defaultRateText), value >= 0,
              value <= Calculator.maximumAnnualRatePercent else {
            model.lastErrorMessage = CalculationError.invalidRate.message
            return
        }
        model.settings.defaultAnnualRatePercent = value
        model.applyDefaultRateFromSettings()
    }

    private func colorBinding(_ keyPath: WritableKeyPath<AppSettings, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: model.settings[keyPath: keyPath]) ?? .accentColor },
            set: { if let hex = $0.hexString { model.settings[keyPath: keyPath] = hex } })
    }
}

/// 設定に埋め込んだロゴ画像の表示。
private func logoImage(from data: Data) -> Image? {
    #if os(macOS)
    NSImage(data: data).map(Image.init(nsImage:))
    #else
    UIImage(data: data).map(Image.init(uiImage:))
    #endif
}
