import Foundation

/// アプリの設定。1つのJSONファイルに保存し、エクスポート／インポートで別の端末へ移せる。
/// 見た目（院名・ロゴ・色・フォント・文言）はここから読み込み、コードにベタ書きしない。
/// 患者に関する入力（患者名・支払総額など）は含めないこと。
public struct AppSettings: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version = AppSettings.currentVersion

    // 院の情報
    public var clinicName = "〇〇歯科クリニック"
    /// ロゴ画像（PNG/JPEG）。設定ファイルに埋め込み、エクスポートで一緒に移せるようにする。
    public var logoImage: Data?

    // 見た目
    public var themeColorHex = "#2F6F8F"
    public var accentColorHex = "#E07A2E"
    /// 空ならシステムフォント
    public var fontName = ""
    public var baseFontSize: Double = 17
    public var resultFontSize: Double = 56

    // 文言
    public var note = "概算です。実際の条件は契約内容によります。"
    public var interestMaskText = "●●●"

    // 計算
    public var rounding: RoundingRule = .down
    public var adjustment: AdjustmentPlacement = .last
    /// 既定の年率（%）。起動時に入力欄へ入れる。
    public var defaultAnnualRatePercent: Decimal = 0
    public var defaultBonusMonths: [Int] = [6, 12]

    // 出力
    /// templates フォルダ内のファイル名
    public var templateFileName = TemplateLibrary.defaultTemplateFileName

    public init() {}

    public var calculationOptions: CalculationOptions {
        CalculationOptions(rounding: rounding, adjustment: adjustment)
    }

    // 古い設定ファイルや手で編集したファイルに項目が欠けていても読めるよう、欠けた項目は既定値にする。
    enum CodingKeys: String, CodingKey {
        case version, clinicName, logoImage, themeColorHex, accentColorHex, fontName, baseFontSize,
             resultFontSize, note, interestMaskText, rounding, adjustment, defaultAnnualRatePercent,
             defaultBonusMonths, templateFileName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        let d = AppSettings()
        version = try value(.version, d.version)
        clinicName = try value(.clinicName, d.clinicName)
        logoImage = try c.decodeIfPresent(Data.self, forKey: .logoImage)
        themeColorHex = try value(.themeColorHex, d.themeColorHex)
        accentColorHex = try value(.accentColorHex, d.accentColorHex)
        fontName = try value(.fontName, d.fontName)
        baseFontSize = try value(.baseFontSize, d.baseFontSize)
        resultFontSize = try value(.resultFontSize, d.resultFontSize)
        note = try value(.note, d.note)
        interestMaskText = try value(.interestMaskText, d.interestMaskText)
        rounding = try value(.rounding, d.rounding)
        adjustment = try value(.adjustment, d.adjustment)
        defaultAnnualRatePercent = try value(.defaultAnnualRatePercent, d.defaultAnnualRatePercent)
        defaultBonusMonths = try value(.defaultBonusMonths, d.defaultBonusMonths)
        templateFileName = try value(.templateFileName, d.templateFileName)
    }
}
