import AppKit
import CoreGraphics
import Foundation
import Network

/// Mac 側の送信クラス。
///
/// # Phase 1 (現在)
/// 仮想ディスプレイを PNG としてキャプチャし、TCP 経由で Android に送信する。
///
/// # Phase 2 (予定)
/// `VideoEncoder` が生成した H.264 NAL ユニット列をストリーミング送信に切り替える。
///
/// # パケットフォーマット
/// ```
/// ┌──────────────────┬──────────────────────┐
/// │  4 bytes         │  N bytes             │
/// │  length (BE)     │  PNG / H.264 data    │
/// └──────────────────┴──────────────────────┘
/// BE = big-endian。Android 側の DataInputStream.readInt() と対応。
/// ```
class StreamSender {

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.tabletmirror.sender")

    /// 接続状態。メインスレッドから参照すること。
    private(set) var isConnected = false

    /// 状態変化をメインスレッドで通知するコールバック。
    var onStatusChange: ((String) -> Void)?

    // MARK: - 接続管理

    /// localhost:9000 への TCP 接続を開始する。
    /// `adb forward` が完了してから呼ぶこと。
    func connect() {
        connection?.cancel()

        let conn = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(integerLiteral: UInt16(ADBManager.port)),
            using: .tcp
        )

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // adb forward 経由でタブレット側の LocalServerSocket に接続完了
                self?.isConnected = true
                DispatchQueue.main.async { self?.onStatusChange?("接続済み (port \(ADBManager.port))") }
            case let .failed(error):
                // タブレット未接続 or adb forward 未実行の場合ここに来る
                self?.isConnected = false
                DispatchQueue.main.async { self?.onStatusChange?("接続失敗: \(error)") }
                self?.scheduleReconnect()
            case .cancelled:
                self?.isConnected = false
            default:
                break
            }
        }

        conn.start(queue: queue)
        connection = conn
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    /// 2 秒後に再接続を試みる。
    /// ケーブル接続前に起動した場合に自動復旧させるため。
    private func scheduleReconnect() {
        queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.connect()
        }
    }

    // MARK: - Phase 1: 静止画送信

    /// 仮想ディスプレイを 1 フレームキャプチャして PNG として送信する。
    ///
    /// - Parameter displayID: `CGVirtualDisplay.displayID` を渡す。
    func sendStaticFrame(displayID: CGDirectDisplayID) {
        guard isConnected else {
            DispatchQueue.main.async { self.onStatusChange?("未接続 — adb forward を確認してください") }
            return
        }

        // CGDisplayCreateImage: 指定 displayID の現在フレームを CGImage として取得
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            DispatchQueue.main.async { self.onStatusChange?("キャプチャ失敗") }
            return
        }

        guard let pngData = pngData(from: cgImage) else {
            DispatchQueue.main.async { self.onStatusChange?("PNG 変換失敗") }
            return
        }

        let packet = buildPacket(payload: pngData)

        connection?.send(content: packet, completion: .contentProcessed { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.onStatusChange?("送信失敗: \(error)")
                } else {
                    self?.onStatusChange?("送信完了 (\(pngData.count / 1024) KB)")
                }
            }
        })
    }

    // MARK: - Internal (テスト可能)

    /// ペイロードを [4 バイト big-endian 長さ + データ] に組み立てる。
    ///
    /// Android 側の `DataInputStream.readInt()` は big-endian 4 バイトを読むため、
    /// Swift の `UInt32.bigEndian` で合わせる。
    ///
    /// - Parameter payload: 送信するデータ (PNG / H.264 NAL ユニット)
    /// - Returns: ヘッダー付きパケット
    func buildPacket(payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(payload)
        return packet
    }

    /// CGImage を PNG Data に変換する。
    func pngData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
