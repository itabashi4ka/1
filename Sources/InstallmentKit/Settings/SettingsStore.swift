import Foundation

/// 設定ファイル（settings.json）とテンプレートフォルダの読み書き。
///
/// 保存先の例: ~/Library/Application Support/InstallmentCalculator/
///   ├─ settings.json
///   └─ templates/
public final class SettingsStore {
    public static let appFolderName = "InstallmentCalculator"
    public static let settingsFileName = "settings.json"

    public let directory: URL
    public var settingsURL: URL { directory.appendingPathComponent(Self.settingsFileName) }
    public var templatesDirectory: URL { directory.appendingPathComponent("templates", isDirectory: true) }

    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// Application Support 配下の既定の保存先。
    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent(appFolderName, isDirectory: true)
    }

    /// 設定を読み込む。ファイルが無い、または壊れている場合は既定値を返す。
    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? Self.decode(data) else {
            return AppSettings()
        }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encode(settings).write(to: settingsURL, options: .atomic)
    }

    /// 既定の年率だけを更新して保存する（「この値を既定にする」ボタン）。
    @discardableResult
    public func saveDefaultAnnualRate(_ rate: Decimal) throws -> AppSettings {
        var settings = load()
        settings.defaultAnnualRatePercent = rate
        try save(settings)
        return settings
    }

    // MARK: - エクスポート／インポート

    public func export(_ settings: AppSettings, to url: URL) throws {
        try Self.encode(settings).write(to: url, options: .atomic)
    }

    /// 取り込んだ設定を保存して返す。
    public func importSettings(from url: URL) throws -> AppSettings {
        let settings = try Self.decode(Data(contentsOf: url))
        try save(settings)
        return settings
    }

    public static func encode(_ settings: AppSettings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    public static func decode(_ data: Data) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: data)
    }
}
