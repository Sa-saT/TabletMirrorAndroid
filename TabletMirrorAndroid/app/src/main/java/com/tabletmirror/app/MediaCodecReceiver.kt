package com.tabletmirror.app

import android.media.MediaCodec
import android.media.MediaFormat
import android.view.SurfaceHolder

/**
 * Phase 2: H.264 NALユニットを受信して MediaCodec でデコードし SurfaceView に描画する。
 * Phase 1 完了後に StreamReceiver と差し替える。
 *
 * 実装予定:
 *   - LocalServerSocket("tablet_mirror") で受信 (StreamReceiver と同じ)
 *   - Annex B NALユニットのパース (スタートコード 00 00 00 01 で区切る)
 *   - MediaCodec "video/avc" デコーダー初期化
 *     - ハードウェアデコーダー: OMX.qcom.video.decoder.avc (SGP312)
 *     - Surface 出力モード (CPU コピーなし)
 *   - Android 4.4 (API 19) の制約:
 *     - 非同期コールバック不可 → 同期ポーリングループで実装
 *     - dequeueInputBuffer / dequeueOutputBuffer を繰り返す
 *
 * TODO: Phase 2 で実装
 */
class MediaCodecReceiver(private val holder: SurfaceHolder) : Thread() {

    @Volatile private var running = true

    fun stopReceiving() {
        running = false
        interrupt()
    }

    override fun run() {
        // TODO: Phase 2 で実装
        //
        // val codec = MediaCodec.createDecoderByType("video/avc")
        // val format = MediaFormat.createVideoFormat("video/avc", 1280, 800)
        // codec.configure(format, holder.surface, null, 0)
        // codec.start()
        //
        // val serverSocket = LocalServerSocket("tablet_mirror")
        // val client = serverSocket.accept()
        // val input = client.inputStream
        //
        // while (running) {
        //     // NALユニット読み込み → codec.dequeueInputBuffer → queueInputBuffer
        //     // codec.dequeueOutputBuffer → releaseOutputBuffer(index, true)
        // }
    }
}
