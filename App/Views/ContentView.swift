import SwiftUI
import InstallmentKit

/// メイン画面。横幅が広いとき（Mac・iPad横向き）は入力と結果を左右に、狭いとき（iPad縦向きなど）は上下に並べる。
struct ContentView: View {
    @Environment(AppModel.self) var model
    @State private var showingExport = false
    @State private var showingSettings = false

    private let sideBySideWidth: CGFloat = 900

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if geometry.size.width >= sideBySideWidth {
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView { InputPanel().padding(20) }
                            .frame(width: min(420, geometry.size.width * 0.4))
                        Divider()
                        ScrollView { ResultPanel().padding(24) }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            InputPanel()
                            Divider()
                            ResultPanel()
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("分割払い計算")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .sheet(isPresented: $showingExport) {
                ExportView()
                    .environment(model)
            }
            #if os(iOS)
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完了") { showingSettings = false }
                            }
                        }
                }
                .environment(model)
            }
            #endif
            .alert("エラー", isPresented: errorAlertBinding) {
                Button("OK") { model.lastErrorMessage = nil }
            } message: {
                Text(model.lastErrorMessage ?? "")
            }
        }
        .font(model.settings.theme.body)
        .tint(model.settings.theme.primary)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.clearInputs()
            } label: {
                Label("入力をクリア", systemImage: "eraser")
            }
            .help("次の患者に備えて入力をすべて消します")

            Button {
                showingExport = true
            } label: {
                Label("支払い表を出力", systemImage: "doc.richtext")
            }
            .disabled(model.result == nil)

            #if os(macOS)
            SettingsLink {
                Label("設定", systemImage: "gearshape")
            }
            #else
            Button {
                showingSettings = true
            } label: {
                Label("設定", systemImage: "gearshape")
            }
            #endif
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { model.lastErrorMessage != nil },
                set: { if !$0 { model.lastErrorMessage = nil } })
    }
}
