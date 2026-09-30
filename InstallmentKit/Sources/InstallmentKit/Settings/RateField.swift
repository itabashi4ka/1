import Foundation

/// 年率入力欄の状態（仕様 7.2）。
/// - 起動時は設定の既定値を入れる
/// - 一時的に別の値を入力しても既定値は変わらない
/// - 「この値を既定にする」を押したときだけ既定値を更新する
/// - 既定値と異なるときは画面で分かるようにする（`differsFromDefault`）
public struct RateField: Equatable, Sendable {
    public var text: String
    public private(set) var defaultRate: Decimal

    public init(defaultRate: Decimal) {
        self.defaultRate = defaultRate
        self.text = DisplayFormat.rate(defaultRate)
    }

    public var value: Decimal? { NumberParser.decimal(text) }

    public var differsFromDefault: Bool {
        // 空欄や数値でない入力も「既定値と違う」扱いにして気づけるようにする。
        guard let value else { return true }
        return value != defaultRate
    }

    /// 入力中の値を既定値にする。保存は呼び出し側（`SettingsStore.saveDefaultAnnualRate`）で行う。
    public mutating func makeCurrentDefault() -> Decimal? {
        guard let value, value >= 0, value <= Calculator.maximumAnnualRatePercent else { return nil }
        defaultRate = value
        return value
    }

    /// 入力欄を既定値に戻す。
    public mutating func resetToDefault() {
        text = DisplayFormat.rate(defaultRate)
    }
}
