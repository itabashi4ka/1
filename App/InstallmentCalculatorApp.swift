import SwiftUI

@main
struct InstallmentCalculatorApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 820)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 600, height: 700)
        }
        #endif
    }
}
