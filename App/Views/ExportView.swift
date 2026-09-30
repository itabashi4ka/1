import SwiftUI
import PDFKit
import InstallmentKit

/// 支払い表の出力（仕様 6章）。テンプレートと利息の表示を選び、プレビューを見てから保存・印刷・共有する。
struct ExportView: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) private var dismiss

    @State private var templateName = ""
    /// 利息は既定で出力しない。
    @State private var showInterest = false
    @State private var pdfData: Data?
    @State private var shareURL: URL?
    @State private var isRendering = false
    @State private var errorMessage: String?
    @State private var showingSaveDialog = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Picker("テンプレート", selection: $templateName) {
                        ForEach(model.templates, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("利息を表示する", isOn: $showInterest)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                .formStyle(.grouped)
                .frame(maxHeight: 200)

                ZStack {
                    if let pdfData {
                        PDFPreview(data: pdfData)
                    } else {
                        Color.secondary.opacity(0.08)
                    }
                    if isRendering { ProgressView() }
                }
            }
            .navigationTitle("支払い表を出力")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        if let pdfData { PDFPrinter.print(pdfData, jobName: fileName) }
                    } label: {
                        Label("印刷", systemImage: "printer")
                    }
                    .disabled(pdfData == nil)

                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Label("共有", systemImage: "square.and.arrow.up")
                        }
                    }

                    Button {
                        showingSaveDialog = true
                    } label: {
                        Label("PDFを保存", systemImage: "arrow.down.doc")
                    }
                    .disabled(pdfData == nil)
                }
            }
            .fileExporter(isPresented: $showingSaveDialog,
                          document: pdfData.map(PDFFile.init(data:)),
                          contentType: .pdf,
                          defaultFilename: fileName) { result in
                if case .failure(let error) = result {
                    errorMessage = "保存できませんでした: \(error.localizedDescription)"
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 760)
        #endif
        .onAppear {
            model.refreshTemplates()
            templateName = model.templates.contains(model.settings.templateFileName)
                ? model.settings.templateFileName
                : (model.templates.first ?? TemplateLibrary.defaultTemplateFileName)
        }
        .task(id: RenderKey(templateName: templateName, showInterest: showInterest)) {
            await render()
        }
        .onDisappear {
            TemporaryPDF.removeAll()
        }
    }

    private struct RenderKey: Equatable {
        var templateName: String
        var showInterest: Bool
    }

    private var fileName: String {
        let name = model.form.patientName.trimmingCharacters(in: .whitespaces)
        let date = DisplayFormat.date(Date())
        let base = name.isEmpty ? "お支払い予定表_\(date)" : "お支払い予定表_\(name)様_\(date)"
        return base.replacingOccurrences(of: "/", with: "／").replacingOccurrences(of: ":", with: "：") + ".pdf"
    }

    private func render() async {
        guard !templateName.isEmpty,
              let html = model.renderPaymentTableHTML(templateName: templateName, showInterest: showInterest) else {
            return
        }
        isRendering = true
        defer { isRendering = false }
        do {
            let data = try await HTMLPDFRenderer.makePDF(html: html, baseURL: model.templateLibrary.directory)
            pdfData = data
            shareURL = try? TemporaryPDF.write(data, fileName: fileName)
            errorMessage = nil
        } catch {
            pdfData = nil
            shareURL = nil
            errorMessage = error.localizedDescription
        }
    }
}

/// PDFのプレビュー。
struct PDFPreview {
    let data: Data

    private func makePDFView() -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        return view
    }

    private func update(_ view: PDFView) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}

#if os(macOS)
extension PDFPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView { makePDFView() }
    func updateNSView(_ view: PDFView, context: Context) { update(view) }
}
#else
extension PDFPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView { makePDFView() }
    func updateUIView(_ view: PDFView, context: Context) { update(view) }
}
#endif
