import XCTest
@testable import InstallmentKit

final class SettingsTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallmentKitTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingFileGivesDefaults() {
        XCTAssertEqual(SettingsStore(directory: directory).load(), AppSettings())
    }

    // 年率の既定値が再起動後も保持され、「既定にする」を押したときだけ更新される
    func testDefaultRatePersistsAcrossLaunches() throws {
        // 1回目の起動: 既定値 3.0% を保存
        var store = SettingsStore(directory: directory)
        var settings = store.load()
        settings.defaultAnnualRatePercent = Decimal(string: "3.0")!
        try store.save(settings)

        // 2回目の起動: 既定値が入力欄に入る
        store = SettingsStore(directory: directory)
        var field = RateField(defaultRate: store.load().defaultAnnualRatePercent)
        XCTAssertEqual(field.text, "3")
        XCTAssertFalse(field.differsFromDefault)

        // 一時的に別の年率を入力しても、既定値は変わらない
        field.text = "4.5"
        XCTAssertTrue(field.differsFromDefault)
        store = SettingsStore(directory: directory)
        XCTAssertEqual(store.load().defaultAnnualRatePercent, Decimal(string: "3.0")!)
        XCTAssertEqual(RateField(defaultRate: store.load().defaultAnnualRatePercent).text, "3")

        // 「この値を既定にする」を押したときだけ更新される
        let newDefault = try XCTUnwrap(field.makeCurrentDefault())
        try store.saveDefaultAnnualRate(newDefault)
        XCTAssertFalse(field.differsFromDefault)

        // 3回目の起動
        store = SettingsStore(directory: directory)
        XCTAssertEqual(store.load().defaultAnnualRatePercent, Decimal(string: "4.5")!)
        XCTAssertEqual(RateField(defaultRate: store.load().defaultAnnualRatePercent).text, "4.5")
    }

    func testSavingDefaultRateKeepsOtherSettings() throws {
        let store = SettingsStore(directory: directory)
        var settings = AppSettings()
        settings.clinicName = "テスト歯科"
        try store.save(settings)
        try store.saveDefaultAnnualRate(7)
        XCTAssertEqual(store.load().clinicName, "テスト歯科")
        XCTAssertEqual(store.load().defaultAnnualRatePercent, 7)
    }

    func testRateFieldRejectsInvalidDefault() {
        var field = RateField(defaultRate: 3)
        field.text = "abc"
        XCTAssertTrue(field.differsFromDefault)
        XCTAssertNil(field.makeCurrentDefault())
        field.text = "99"
        XCTAssertNil(field.makeCurrentDefault())
        XCTAssertEqual(field.defaultRate, 3)
        field.resetToDefault()
        XCTAssertEqual(field.text, "3")
    }

    func testExportImport() throws {
        let store = SettingsStore(directory: directory)
        var settings = AppSettings()
        settings.clinicName = "さくら歯科"
        settings.logoImage = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        settings.themeColorHex = "#112233"
        settings.rounding = .nearest
        settings.adjustment = .first
        settings.defaultAnnualRatePercent = Decimal(string: "6.8")!
        settings.templateFileName = "simple.html"

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let exported = directory.appendingPathComponent("export.json")
        try store.export(settings, to: exported)

        // 別のMac（別の保存先）で取り込む
        let other = SettingsStore(directory: directory.appendingPathComponent("other"))
        XCTAssertEqual(try other.importSettings(from: exported), settings)
        XCTAssertEqual(other.load(), settings)
    }

    func testDecodingFillsMissingKeysWithDefaults() throws {
        let json = #"{"clinicName": "古い設定", "defaultAnnualRatePercent": 2.5}"#
        let settings = try SettingsStore.decode(Data(json.utf8))
        XCTAssertEqual(settings.clinicName, "古い設定")
        XCTAssertEqual(settings.defaultAnnualRatePercent, Decimal(string: "2.5")!)
        XCTAssertEqual(settings.note, AppSettings().note)
        XCTAssertEqual(settings.rounding, .down)
    }

    func testCorruptFileFallsBackToDefaults() throws {
        let store = SettingsStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.settingsURL)
        XCTAssertEqual(store.load(), AppSettings())
    }

    func testSettingsDoNotContainPatientFields() throws {
        let json = String(decoding: try SettingsStore.encode(AppSettings()), as: UTF8.self)
        for key in ["patient", "principal", "installments"] {
            XCTAssertFalse(json.contains(key), key)
        }
    }
}
