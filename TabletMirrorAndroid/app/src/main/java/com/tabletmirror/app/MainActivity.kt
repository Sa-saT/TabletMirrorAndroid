package com.tabletmirror.app

import android.app.Activity
import android.os.Bundle
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.Window
import android.view.WindowManager

class MainActivity : Activity(), SurfaceHolder.Callback {

    private lateinit var surfaceView: SurfaceView
    private var streamReceiver: StreamReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // タイトルバー非表示 + フルスクリーン + 画面ON維持
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        surfaceView = SurfaceView(this)
        surfaceView.holder.addCallback(this)
        setContentView(surfaceView)
    }

    // Surface が準備できたら受信スレッドを開始
    override fun surfaceCreated(holder: SurfaceHolder) {
        streamReceiver = StreamReceiver(holder).also { it.start() }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

    // Surface が破棄されたら受信スレッドを停止
    override fun surfaceDestroyed(holder: SurfaceHolder) {
        streamReceiver?.stopReceiving()
        streamReceiver = null
    }

    override fun onDestroy() {
        super.onDestroy()
        streamReceiver?.stopReceiving()
    }
}
