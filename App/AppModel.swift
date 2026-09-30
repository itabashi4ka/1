import Foundation
import Observation
import InstallmentKit

/// 画面全体の状態。
/// 入力値（患者名・支払総額など）はメモリ上にだけ持ち、保存しない（仕様 9章）。
/// 保存するのは `settings`（設定ファイル）だけ。
@MainActor
@Observable
final class AppModel {
    let store: SettingsStore
    let templateLibrary: TemplateLibrary

    /// 設定。変更するとすぐ settings.json に保存する。
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            persistSettings()
            if settings.calculationOptions != oldValue.calculationOptions { recalculate() }
        }
    }

    /// 入力欄（年率以外）。
    var form: LoanForm {
        didSet { if form != oldValue { recalculate() } }
    }

    /// 年率の入力欄（既定値の保持つき）。
    var rate: RateField {
        didSet { if rate.text != oldValue.text { recalculate() } }
    }

    private(set) var result: LoanResult?
    private(set) var error: CalculationError?
    /// 利息総額を見せているか。起動時と、再計算で結果が変わったときは非表示に戻す。
    var interestRevealed = false
    private(set) var templates: [String] = []
    var lastErrorMessage: String?

    init(store: SettingsStore = SettingsStore(directory: SettingsStore.defaultDirectory())) {
        self.store = store
        self.templateLibrary = TemplateLibrary(directory: store.templatesDirectory)
        let settings = store.load()
        self.settings = settings
        self.rate = RateField(defaultRate: settings.defaultAnnualRatePercent)
        var form = LoanForm()
        form.bonusMonths = Set(settings.defaultBonusMonths)
        self.form = form
        try? templateLibrary.prepare()
        refreshTemplates()
    }

    // MARK: - 計算

    func recalculate() {
        let previous = (result, error)
        var form = self.form
        form.rateText = rate.text
        if !form.isReadyToCalculate {
            result = nil
            error = nil
        } else {
            do {
                result = try Calculator.calculate(try form.makeInput(), options: settings.calculationOptions)
                error = nil
            } catch let e as CalculationError {
                result = nil
                error = e
            } catch {
                result = nil
            }
        }
        // 入力を変えて結果が変わったら、利息は自動で非表示に戻す（仕様 5.3）。
        if previous.0 != result || previous.1 != error {
            interestRevealed = false
        }
    }

    /// 入力をすべて消す（次の患者へ）。年率は既定値に戻す。
    func clearInputs() {
        var fresh = LoanForm()
        fresh.mode = form.mode
        fresh.bonusMonths = Set(settings.defaultBonusMonths)
        form = fresh
        rate.resetToDefault()
        interestRevealed = false
    }

    // MARK: - 年率の既定値（仕様 7.2）

    /// 「この値を既定にする」
    func makeCurrentRateDefault() {
        guard let value = rate.makeCurrentDefault() else {
            lastErrorMessage = CalculationError.invalidRate.message
            return
        }
        settings.defaultAnnualRatePercent = value
    }

    /// 設定画面で既定の年率を直接変更したとき、入力欄の既定値表示も合わせる。
    func applyDefaultRateFromSettings() {
        let current = rate.text
        rate = RateField(defaultRate: settings.defaultAnnualRatePercent)
        rate.text = current
    }

    // MARK: - 設定

    private func persistSettings() {
        do {
            try store.save(settings)
        } catch {
            lastErrorMessage = "設定を保存できませんでした: \(error.localizedDescription)"
        }
    }

    func exportSettingsData() throws -> Data {
        try SettingsStore.encode(settings)
    }

    func importSettings(from url: URL) {
        do {
            let imported = try withSecurityScope(url) { try store.importSettings(from: $0) }
            settings = imported
            applyDefaultRateFromSettings()
            rate.resetToDefault()
        } catch {
            lastErrorMessage = "設定を読み込めませんでした: \(error.localizedDescription)"
        }
    }

    func resetSettings() {
        settings = AppSettings()
        applyDefaultRateFromSettings()
    }

    func setLogo(from url: URL) {
        do {
            settings.logoImage = try withSecurityScope(url) { try Data(contentsOf: $0) }
        } catch {
            lastErrorMessage = "画像を読み込めませんでした: \(error.localizedDescription)"
        }
    }

    // MARK: - テンプレート

    func refreshTemplates() {
        templates = templateLibrary.availableTemplates()
    }

    func importTemplate(from url: URL) {
        do {
            let name = try withSecurityScope(url) { try templateLibrary.importTemplate(from: $0) }
            refreshTemplates()
            settings.templateFileName = name
        } catch {
            lastErrorMessage = "テンプレートを読み込めませんでした: \(error.localizedDescription)"
        }
    }

    /// 支払い表のHTMLを作る。
    func renderPaymentTableHTML(templateName: String, showInterest: Bool) -> String? {
        guard let result else { return nil }
        let template = templateLibrary.load(named: templateName)
        let context = TemplateContext(result: result, settings: settings,
                                      patientName: form.patientName, showInterest: showInterest)
        return TemplateRenderer.render(template, context: context)
    }

    private func withSecurityScope<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }
}
