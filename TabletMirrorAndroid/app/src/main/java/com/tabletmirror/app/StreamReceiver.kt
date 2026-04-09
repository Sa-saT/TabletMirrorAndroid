package com.tabletmirror.app

import android.graphics.BitmapFactory
import android.graphics.RectF
import android.net.LocalServerSocket
import android.util.Log
import android.view.SurfaceHolder
import java.io.DataInputStream

/**
 * Phase 1: Mac側から送られてくる PNG 静止画を受信して SurfaceView に描画する。
 *
 * 通信プロトコル:
 *   adb forward tcp:9000 localabstract:tablet_mirror
 *   → Android 側は LocalServerSocket("tablet_mirror") で待ち受け
 *
 * パケット形式:
 *   [4バイト big-endian 長さ][PNG データ]
 *
 * Phase 2 では MediaCodecReceiver.kt に差し替える。
 */
class StreamReceiver(private val holder: SurfaceHolder) : Thread() {

    companion object {
        private const val TAG = "StreamReceiver"
        private const val SOCKET_NAME = "tablet_mirror"
        private const val MAX_FRAME_BYTES = 10 * 1024 * 1024 // 10MB 上限
    }

    @Volatile private var running = true

    fun stopReceiving() {
        running = false
        interrupt()
    }

    override fun run() {
        try {
            val serverSocket = LocalServerSocket(SOCKET_NAME)
            Log.d(TAG, "Waiting on localabstract:$SOCKET_NAME")

            val client = serverSocket.accept()
            Log.d(TAG, "Connected")

            val input = DataInputStream(client.inputStream)

            while (running) {
                // 4バイト big-endian 長さヘッダーを読む
                val length = input.readInt()

                if (length <= 0 || length > MAX_FRAME_BYTES) {
                    Log.w(TAG, "Invalid frame length: $length — closing")
                    break
                }

                // PNG データを読む (readFully で length バイト必ず読む)
                val data = ByteArray(length)
                input.readFully(data)

                // PNG → Bitmap
                val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size)
                if (bitmap == null) {
                    Log.w(TAG, "BitmapFactory returned null")
                    continue
                }

                // SurfaceView に描画 (フルスクリーンにフィット)
                val canvas = holder.lockCanvas() ?: continue
                try {
                    val dst = RectF(0f, 0f, canvas.width.toFloat(), canvas.height.toFloat())
                    canvas.drawBitmap(bitmap, null, dst, null)
                } finally {
                    holder.unlockCanvasAndPost(canvas)
                }

                bitmap.recycle()
            }

            client.close()
            serverSocket.close()
            Log.d(TAG, "Stopped")

        } catch (e: Exception) {
            if (running) Log.e(TAG, "Error: ${e.message}", e)
        }
    }
}
