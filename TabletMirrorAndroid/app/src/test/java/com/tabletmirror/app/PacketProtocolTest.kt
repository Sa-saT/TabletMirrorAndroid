package com.tabletmirror.app

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.DataInputStream

/**
 * パケットプロトコルのユニットテスト。
 *
 * Mac 側 (Swift / StreamSender) と Android 側 (Kotlin / StreamReceiver) の
 * パケットフォーマットが対称になっていることを検証する。
 *
 * # テスト対象のプロトコル
 * ```
 * ┌──────────────────┬──────────────────────┐
 * │  4 bytes (BE)    │  N bytes             │
 * │  payload length  │  PNG / H.264 data    │
 * └──────────────────┴──────────────────────┘
 * BE = big-endian
 * Mac:     UInt32(count).bigEndian → Data
 * Android: DataInputStream.readInt() (big-endian 固定)
 * ```
 *
 * # 実行方法
 * Android Studio → 左ペインのテストファイルを右クリック → Run
 */
class PacketProtocolTest {

    // MARK: - 長さヘッダーのパース

    /**
     * 正常なパケット (4 バイトヘッダー + ペイロード) を正しく読めるか確認する。
     *
     * Mac 側が送る: [0x00, 0x00, 0x00, 0x05, 0x48, 0x45, 0x4C, 0x4C, 0x4F]
     *               ← length=5 (BE) →  ← "HELLO" →
     */
    @Test
    fun testReadLengthFromHeader() {
        val payload = "HELLO".toByteArray()
        val packet = buildPacket(payload)

        val input = DataInputStream(ByteArrayInputStream(packet))
        val length = input.readInt() // big-endian で読む

        assertEquals("長さヘッダーがペイロードサイズと一致しない", payload.size, length)
    }

    /**
     * ヘッダー後のペイロードが元のデータと一致するか確認する。
     */
    @Test
    fun testReadPayloadAfterHeader() {
        val payload = byteArrayOf(0x01, 0x02, 0x03)
        val packet = buildPacket(payload)

        val input = DataInputStream(ByteArrayInputStream(packet))
        val length = input.readInt()
        val readData = ByteArray(length)
        input.readFully(readData)

        assertArrayEquals("ペイロードが一致しない", payload, readData)
    }

    /**
     * 大きなペイロード (100KB) でも正しく長さを読めるか確認する。
     * PNG フレームは数十〜数百 KB になりうる。
     */
    @Test
    fun testLargePayload() {
        val payload = ByteArray(100 * 1024) { it.toByte() } // 100KB
        val packet = buildPacket(payload)

        val input = DataInputStream(ByteArrayInputStream(packet))
        val length = input.readInt()

        assertEquals(100 * 1024, length)
    }

    // MARK: - 長さバリデーション

    /**
     * 長さが 0 以下のパケットを拒否するか確認する。
     * StreamReceiver の `if (length <= 0 || length > MAX_FRAME_BYTES)` に対応。
     */
    @Test
    fun testRejectZeroLength() {
        assertFalse("長さ 0 は無効", isValidLength(0))
        assertFalse("負の長さは無効", isValidLength(-1))
    }

    /**
     * 10MB を超えるパケットを拒否するか確認する。
     * 異常データや攻撃的なペイロードへの防御。
     */
    @Test
    fun testRejectTooLargeLength() {
        val maxBytes = 10 * 1024 * 1024 // 10MB
        assertFalse("10MB 超は無効", isValidLength(maxBytes + 1))
        assertTrue("10MB ちょうどは有効", isValidLength(maxBytes))
    }

    /**
     * 典型的な PNG サイズ (1MB) は有効と判定されるか確認する。
     */
    @Test
    fun testAcceptTypicalPNGSize() {
        assertTrue("1MB は有効", isValidLength(1 * 1024 * 1024))
    }

    // MARK: - big-endian バイト順の確認

    /**
     * 256 バイトのペイロードの長さヘッダーが
     * big-endian で 0x00 0x00 0x01 0x00 になるか確認する。
     *
     * little-endian だと 0x00 0x01 0x00 0x00 になるため、
     * Mac 側と Android 側でバイト順が一致しているかの検証。
     */
    @Test
    fun testHeaderIsBigEndian() {
        val payload = ByteArray(256)
        val packet = buildPacket(payload)

        assertEquals("byte[0]", 0x00.toByte(), packet[0])
        assertEquals("byte[1]", 0x00.toByte(), packet[1])
        assertEquals("byte[2]", 0x01.toByte(), packet[2])
        assertEquals("byte[3]", 0x00.toByte(), packet[3])
    }

    // MARK: - ヘルパー

    /**
     * テスト用パケット組み立て。
     * Mac 側 StreamSender.buildPacket() と同じフォーマット。
     */
    private fun buildPacket(payload: ByteArray): ByteArray {
        val length = payload.size
        return byteArrayOf(
            (length shr 24 and 0xFF).toByte(),
            (length shr 16 and 0xFF).toByte(),
            (length shr 8  and 0xFF).toByte(),
            (length        and 0xFF).toByte()
        ) + payload
    }

    /**
     * StreamReceiver の長さバリデーションロジックを抽出したヘルパー。
     */
    private fun isValidLength(length: Int): Boolean {
        val maxFrameBytes = 10 * 1024 * 1024
        return length > 0 && length <= maxFrameBytes
    }
}
