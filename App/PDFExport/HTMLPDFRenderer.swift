import Foundation
import WebKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// HTMLをA4のPDFに変換する（macOS・iPadOS共通の入口）。
/// WebKitで描画し、各OSの印刷機構でページ分割する。
@MainActor
final class HTMLPDFRenderer: NSObject, WKNavigationDelegate {
    /// A4（ポイント）
    static let paperSize = CGSize(width: 595.2, height: 841.8)
    /// 余白（ポイント、約10mm）
    static let margin: CGFloat = 28

    enum RenderError: LocalizedError {
        case loadFailed(Error)
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case .loadFailed(let error): return "支払い表を描画できませんでした: \(error.localizedDescription)"
            case .emptyOutput: return "PDFを作成できませんでした。"
            }
        }
    }

    private var loadContinuation: CheckedContinuation<Void, Error>?
    #if os(macOS)
    private var printContinuation: CheckedContinuation<Bool, Never>?
    #endif

    /// - Parameter baseURL: テンプレート内の相対パス（画像など）の基準。templates フォルダを渡す。
    static func makePDF(html: String, baseURL: URL?) async throws -> Data {
        try await HTMLPDFRenderer().render(html: html, baseURL: baseURL)
    }

    private func render(html: String, baseURL: URL?) async throws -> Data {
        let webView = WKWebView(frame: CGRect(origin: .zero, size: Self.paperSize))
        webView.navigationDelegate = self

        #if os(macOS)
        // 印刷処理にはウインドウが必要なので、画面外に見えないウインドウを用意する。
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: Self.paperSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        defer { window.close() }
        #endif

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }

        #if os(macOS)
        let data = try await makePDFOnMac(webView: webView, window: window)
        #else
        let data = makePDFOnIOS(webView: webView)
        #endif
        guard !data.isEmpty else { throw RenderError.emptyOutput }
        return data
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: RenderError.loadFailed(error))
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: RenderError.loadFailed(error))
        loadContinuation = nil
    }

    // MARK: - macOS

    #if os(macOS)
    private func makePDFOnMac(webView: WKWebView, window: NSWindow) async throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        let info = NSPrintInfo()
        info.paperSize = Self.paperSize
        info.topMargin = Self.margin
        info.bottomMargin = Self.margin
        info.leftMargin = Self.margin
        info.rightMargin = Self.margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // WKWebView の印刷ビューに大きさを与えないと白紙になることがある。
        operation.view?.frame = CGRect(origin: .zero, size: Self.paperSize)

        _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            printContinuation = continuation
            operation.runModal(for: window, delegate: self,
                               didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
        return (try? Data(contentsOf: url)) ?? Data()
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool,
                                            contextInfo: UnsafeMutableRawPointer?) {
        printContinuation?.resume(returning: success)
        printContinuation = nil
    }
    #endif

    // MARK: - iPadOS

    #if os(iOS)
    private func makePDFOnIOS(webView: WKWebView) -> Data {
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        let paper = CGRect(origin: .zero, size: Self.paperSize)
        let printable = paper.insetBy(dx: Self.margin, dy: Self.margin)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printable), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }
    #endif
}
