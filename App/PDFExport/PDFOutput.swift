import SwiftUI
import UniformTypeIdentifiers
import PDFKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 保存ダイアログ（fileExporter）に渡すPDF。保存先は出力時に利用者が選ぶ（仕様 9章）。
struct PDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// 設定のエクスポート用（JSON）。
struct SettingsFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// PDFの印刷（Mac: 印刷ダイアログ、iPad: AirPrint）。
@MainActor
enum PDFPrinter {
    static func print(_ data: Data, jobName: String) {
        #if os(macOS)
        guard let document = PDFDocument(data: data),
              let operation = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleNone, autoRotate: true)
        else { return }
        operation.jobTitle = jobName
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window = NSApp.keyWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
        #else
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true)
        #endif
    }
}

/// 共有シート用の一時ファイル。画面を閉じたら消す（患者名を含むため残さない）。
enum TemporaryPDF {
    static func write(_ data: Data, fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func removeAll() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }
}
