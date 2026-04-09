import XCTest
@testable import TabletMirror

/// StreamSender のユニットテスト。
///
/// パケットフォーマットの正確性を検証する。
/// Android 側の DataInputStream.readInt() + readFully() と対称になっていること。
final class StreamSenderTests: XCTestCase {

    private let sender = StreamSender()

    // MARK: - buildPacket

    /// パケットの先頭 4 バイトがペイロード長の big-endian 表現になっているか確認する。
    ///
    /// Android 側: `val length = input.readInt()` (big-endian)
    /// Mac 側:    `UInt32(payload.count).bigEndian`
    func testPacketHasBigEndianLengthHeader() {
        let payload = Data([0x01, 0x02, 0x03, 0x04, 0x05]) // 5 バイト
        let packet = sender.buildPacket(payload: payload)

        // 先頭 4 バイトを big-endian UInt32 として読む
        let lengthBytes = packet.prefix(4)
        let length = lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        XCTAssertEqual(Int(length), payload.count, "ヘッダーの長さがペイロードサイズと一致しない")
    }

    /// ヘッダー以降にペイロードがそのまま続くか確認する。
    func testPacketBodyMatchesPayload() {
        let payload = Data("HELLO".utf8)
        let packet = sender.buildPacket(payload: payload)

        let body = packet.dropFirst(4)
        XCTAssertEqual(body, payload, "パケット本体がペイロードと一致しない")
    }

    /// パケット全体の長さが (4 + ペイロード長) になっているか確認する。
    func testPacketTotalLength() {
        let payload = Data(repeating: 0xFF, count: 1024)
        let packet = sender.buildPacket(payload: payload)
        XCTAssertEqual(packet.count, 4 + payload.count)
    }

    /// 空ペイロードでも長さ 0 のヘッダーが付くか確認する。
    func testPacketWithEmptyPayload() {
        let packet = sender.buildPacket(payload: Data())
        XCTAssertEqual(packet.count, 4, "空ペイロードでもヘッダー 4 バイトは存在するはず")

        let length = packet.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        XCTAssertEqual(length, 0)
    }

    /// ヘッダー長フィールドが big-endian であることをバイト列レベルで確認する。
    /// 例: ペイロード 256 バイト → big-endian で 0x00 0x00 0x01 0x00
    func testPacketHeaderByteOrder() {
        let payload = Data(repeating: 0x00, count: 256)
        let packet = sender.buildPacket(payload: payload)

        XCTAssertEqual(packet[0], 0x00)
        XCTAssertEqual(packet[1], 0x00)
        XCTAssertEqual(packet[2], 0x01)
        XCTAssertEqual(packet[3], 0x00)
    }

    // MARK: - pngData

    /// CGImage から PNG Data が生成されるか確認する。
    func testPNGDataFromCGImage() {
        // 1x1 ピクセルの赤い CGImage を作成
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))

        let cgImage = context.makeImage()!
        let data = sender.pngData(from: cgImage)

        XCTAssertNotNil(data, "PNG 変換が nil を返した")
        // PNG マジックバイト: 0x89 0x50 0x4E 0x47
        XCTAssertEqual(data?.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]), "PNG マジックバイトが一致しない")
    }
}
