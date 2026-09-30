import Foundation

/// templates フォルダ内のHTMLテンプレートの一覧・読み込み・取り込み。
public struct TemplateLibrary {
    public static let defaultTemplateFileName = "default.html"

    public let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// アプリに同梱の既定テンプレート。
    public static var bundledDefaultTemplate: String {
        guard let url = Bundle.module.url(forResource: "default", withExtension: "html"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "<html><body><p>テンプレートが見つかりません。</p></body></html>"
        }
        return text
    }

    /// フォルダが無ければ作り、既定テンプレートが無ければ置く（利用者が編集した内容は上書きしない）。
    public func prepare() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.defaultTemplateFileName)
        if !fileManager.fileExists(atPath: url.path) {
            try Self.bundledDefaultTemplate.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// 使用できるテンプレートのファイル名（.html / .htm）。
    public func availableTemplates() -> [String] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { ["html", "htm"].contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
    }

    /// テンプレートを読む。見つからなければ同梱の既定テンプレートを返す。
    public func load(named name: String) -> String {
        let url = directory.appendingPathComponent(name)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? Self.bundledDefaultTemplate
    }

    /// 外部のHTMLファイル（ファイルAppなど）を templates フォルダへコピーし、ファイル名を返す。
    @discardableResult
    public func importTemplate(from source: URL) throws -> String {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = source.lastPathComponent
        let destination = directory.appendingPathComponent(name)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        return name
    }
}
