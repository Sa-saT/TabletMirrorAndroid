import XCTest
@testable import TabletMirror

/// ADBManager のユニットテスト。
///
/// # 実行方法
/// Xcode で Test ターゲットを追加してから実行する:
///   File → New → Target → macOS → Unit Testing Bundle
///   ターゲット名: TabletMirrorTests
///   「TabletMirrorTests」フォルダをターゲットに追加する
final class ADBManagerTests: XCTestCase {

    // MARK: - adb パス解決

    /// このMacに adb がインストールされているか確認する。
    /// brew install android-platform-tools 済みであれば必ず通る。
    func testADBIsInstalled() {
        XCTAssertTrue(ADBManager.isInstalled, "adb が見つかりません。brew install android-platform-tools を実行してください。")
    }

    /// Apple Silicon Mac では /opt/homebrew/bin/adb が返るはず。
    func testADBPathIsHomebrew() {
        guard let path = ADBManager.adbPath else {
            XCTFail("adbPath が nil")
            return
        }
        XCTAssertTrue(
            path.contains("/homebrew/") || path.contains("/local/") || path.contains("/usr/"),
            "予期しないパス: \(path)"
        )
    }

    /// adbPath が実行可能なファイルを指しているか確認する。
    func testADBPathIsExecutable() {
        guard let path = ADBManager.adbPath else {
            XCTSkip("adb 未インストールのためスキップ")
        }
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: path),
            "\(path) は実行可能ではありません"
        )
    }

    // MARK: - 定数

    func testPort() {
        XCTAssertEqual(ADBManager.port, 9000)
    }

    func testSocketName() {
        XCTAssertEqual(ADBManager.socketName, "tablet_mirror")
    }

    // MARK: - checkDevice (adb devices の出力パース)

    /// "List of devices attached\nCB5A2\tdevice\n" のような出力で true を返すか確認する。
    /// 実際の adb 出力を模したテキストでパースロジックを検証する。
    func testDeviceDetectionFromOutput() {
        // adb devices の実際の出力形式
        let connectedOutput = "List of devices attached\nCB5A2XXXXXX\tdevice\n"
        let disconnectedOutput = "List of devices attached\n"
        let unauthorizedOutput = "List of devices attached\nCB5A2XXXXXX\tunauthorized\n"

        XCTAssertTrue(isDeviceConnected(in: connectedOutput))
        XCTAssertFalse(isDeviceConnected(in: disconnectedOutput))
        XCTAssertFalse(isDeviceConnected(in: unauthorizedOutput), "unauthorized は接続済みとみなさない")
    }

    /// ADBManager.checkDevice 内のパースロジックを切り出して検証するヘルパー。
    private func isDeviceConnected(in output: String) -> Bool {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.dropFirst().contains { $0.contains("\tdevice") }
    }
}
