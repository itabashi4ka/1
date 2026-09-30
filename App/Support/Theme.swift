import SwiftUI
import InstallmentKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 設定から作る見た目。色・フォント・文字サイズはここを通して使い、Viewにベタ書きしない。
struct Theme {
    var primary: Color
    var accent: Color
    var fontName: String
    var baseSize: CGFloat
    var resultSize: CGFloat

    init(settings: AppSettings) {
        primary = Color(hex: settings.themeColorHex) ?? .accentColor
        accent = Color(hex: settings.accentColorHex) ?? .orange
        fontName = settings.fontName.trimmingCharacters(in: .whitespaces)
        baseSize = CGFloat(settings.baseFontSize)
        resultSize = CGFloat(settings.resultFontSize)
    }

    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if fontName.isEmpty {
            return .system(size: size, weight: weight)
        }
        return .custom(fontName, size: size).weight(weight)
    }

    var body: Font { font(baseSize) }
    var label: Font { font(baseSize * 0.85) }
    var headline: Font { font(baseSize * 1.1, weight: .semibold) }
    var result: Font { font(resultSize, weight: .bold).monospacedDigit() }
    var resultUnit: Font { font(resultSize * 0.4, weight: .semibold) }
    var secondaryResult: Font { font(resultSize * 0.45, weight: .semibold).monospacedDigit() }

    /// タッチ操作しやすい最小の高さ（iPad）
    static let minimumTapHeight: CGFloat = 44
}

extension AppSettings {
    var theme: Theme { Theme(settings: self) }
}

extension Color {
    /// "#RRGGBB" / "RRGGBB"
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String? {
        #if os(macOS)
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let (r, g, b) = (c.redComponent, c.greenComponent, c.blueComponent)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #endif
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
