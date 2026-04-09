import Foundation

/// ADB (Android Debug Bridge) の管理クラス。
///
/// # 役割
/// `adb forward` コマンドを実行して Mac の TCP ポートを
/// Android の Unix ドメインソケットにトンネリングする。
///
/// # 通信経路
/// ```
/// StreamSender (Mac)
///   → localhost:9000 (TCP)
///   → adb forward (USB トンネル)
///   → localabstract:tablet_mirror (Android)
///   → StreamReceiver / MediaCodecReceiver (Android APK)
/// ```
///
/// # adb のインストール
/// ```bash
/// brew install android-platform-tools
/// ```
class ADBManager {

    static let shared = ADBManager()

    /// Mac → Android の TCP トンネルに使用するポート番号。
    /// Android 側の ServerSocket / LocalServerSocket と一致させること。
    static let port = 9000

    /// Android 側の LocalServerSocket に使用するソケット名。
    /// `adb forward tcp:PORT localabstract:SOCKET_NAME` の SOCKET_NAME に対応。
    static let socketName = "tablet_mirror"

    // MARK: - adb パス解決

    /// Homebrew でインストールされる adb の候補パス。
    /// Finder / Dock から起動したアプリは PATH が通っていないため、
    /// 絶対パスで検索する必要がある。
    ///
    /// - `/opt/homebrew/bin/adb` : Apple Silicon Mac (M1/M2)
    /// - `/usr/local/bin/adb`    : Intel Mac
    /// - `/usr/bin/adb`          : システム標準 (通常は存在しない)
    private static let adbSearchPaths = [
        "/opt/homebrew/bin/adb",
        "/usr/local/bin/adb",
        "/usr/bin/adb",
    ]

    /// 実行可能な adb バイナリの絶対パスを返す。見つからない場合は nil。
    static var adbPath: String? {
        adbSearchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// adb がインストール済みかどうか。
    static var isInstalled: Bool { adbPath != nil }

    // MARK: - adb forward

    /// `adb forward tcp:9000 localabstract:tablet_mirror` を実行する。
    ///
    /// 成功すると Mac の localhost:9000 への書き込みが
    /// USB 経由で Android の localabstract:tablet_mirror に届く。
    ///
    /// - Parameter completion: メインスレッドで呼ばれる。(成功フラグ, エラーメッセージ)
    func setupForward(completion: @escaping (Bool, String) -> Void) {
        guard let adb = ADBManager.adbPath else {
            DispatchQueue.main.async {
                completion(false, "adb が見つかりません。\nターミナルで以下を実行してください:\n  brew install android-platform-tools")
            }
            return
        }

        run(adb, args: [
            "forward",
            "tcp:\(ADBManager.port)",
            "localabstract:\(ADBManager.socketName)",
        ], completion: completion)
    }

    /// `adb devices` を実行してタブレットが接続済みか確認する。
    ///
    /// `adb devices` の出力例:
    /// ```
    /// List of devices attached
    /// CB5A2XXXXXX    device    ← この行があれば接続済み
    /// ```
    ///
    /// - Parameter completion: メインスレッドで呼ばれる。接続済みなら true。
    func checkDevice(completion: @escaping (Bool) -> Void) {
        guard let adb = ADBManager.adbPath else {
            DispatchQueue.main.async { completion(false) }
            return
        }

        let process = makeProcess(adb, args: ["devices"])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        process.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
            // 先頭行 "List of devices attached" を除いた行に
            // タブ + "device" が含まれていれば接続済み
            let connected = lines.dropFirst().contains { $0.contains("\tdevice") }
            DispatchQueue.main.async { completion(connected) }
        }

        try? process.run()
    }

    // MARK: - Private

    private func run(_ adb: String, args: [String], completion: @escaping (Bool, String) -> Void) {
        let process = makeProcess(adb, args: args)
        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        process.terminationHandler = { p in
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errString = String(data: errData, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                completion(p.terminationStatus == 0, errString)
            }
        }

        do {
            try process.run()
        } catch {
            DispatchQueue.main.async {
                completion(false, error.localizedDescription)
            }
        }
    }

    private func makeProcess(_ executablePath: String, args: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args
        return process
    }
}
