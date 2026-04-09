# CLAUDE.md — MacBook + Androidタブレット 有線サブモニタ化

## プロジェクト目的

MacBook (Apple Silicon M1/M2) の画面を、Sony Xperia Tablet Z (SGP312) に有線で拡張ディスプレイとして映す。
Macのウィンドウをタブレット側にドラッグ移動でき、安定した低レイテンシ描画を実現する。

---

## ハードウェア

| 項目 | 詳細 |
|------|------|
| Mac | MacBook Apple Silicon (M1/M2), macOS Sonoma/Ventura |
| タブレット | Sony Xperia Tablet Z SGP312 |
| タブレットSoC | Qualcomm Snapdragon S4 Pro APQ8064 |
| タブレットAndroid | 4.4 KitKat (最終版) |
| タブレットUSB | micro USB 2.0 (OTG対応) |
| ケーブル | USB-C (Mac) ⇄ micro USB (タブレット) データ通信対応ケーブル |

**接続**: Wi-Fi / LAN 不使用。ADB over USB のみ。

---

## アーキテクチャ

```
[Mac: Swift アプリ]
  CGVirtualDisplay          → macOSにDisplay 2として認識させる
  ScreenCaptureKit          → Display 2のフレームをキャプチャ (CMSampleBuffer)
  VideoToolbox              → H.264エンコード (VTCompressionSession)
  Annex B NAL unitフレーミング
  TCP socket → localhost:9000
  adb forward tcp:9000 localabstract:tablet_mirror

[Android: APK (Java, minSdk 19)]
  ServerSocket (localabstract:tablet_mirror)
  InputStream → MediaCodec H.264デコード (Surface出力)
  SurfaceView フルスクリーン描画
```

---

## 参照OSSプロジェクト

### DeskPad (MIT) — github.com/Stengo/DeskPad
- **用途**: CGVirtualDisplay実装の参考
- **重要ファイル**: `VirtualDisplay.swift`, `AppDelegate.swift`
- **核心API**: `CGVirtualDisplayCreate()`, `CGVirtualDisplaySetModes()`
- `CGVirtualDisplay` はmacOS 12.3以降で使用可能
- 無料Apple Developerアカウントで個人ローカル実行が可能 (App Store配布は不要)
- メンテナンスは低調 (2022〜2023以降更新少)、参考実装として使う

### scrcpy (Apache 2.0) — github.com/Genymobile/scrcpy
- **用途**: ADB USBトンネル設計 + Android MediaCodecパイプラインの参考 (逆方向に応用)
- **重要ファイル**:
  - Mac側: `app/src/adb/adb_tunnel.c` (adb forward管理)
  - Mac側: `app/src/server.c` (デバイス接続ライフサイクル)
  - Android側: `DesktopConnection.java` (TCPソケット管理)
  - Android側: `ScreenEncoder.java` (MediaCodec設定パターン → デコーダー側に逆用)
- scrcpy自体はAndroid→Macの一方向だが、**逆方向アーキテクチャの参考として最適**
- ADB transport: `adb forward tcp:PORT localabstract:scrcpy` パターンをそのまま流用
- Android側はAPKが必要 (scrcpyのapp_process方式は可視Surfaceを持てないため)

### Deskreen (GPL-3.0) — github.com/pavlobu/deskreen
- **用途**: ディスプレイ選択キャプチャのアーキテクチャ参考のみ
- **注意**: WebRTC + VP8/VP9を使用。Android 4.4非対応。USB非対応。コードの直接流用は不可
- 2022年以降実質メンテナンス停止

---

## 重要な技術制約

### Android 4.4 (API 19) MediaCodec
- 非同期モード不可 (API 21から)。**同期ポーリングループ必須**:
  ```java
  while (running) {
      int inputIndex = codec.dequeueInputBuffer(10000);
      // feed NAL data...
      int outputIndex = codec.dequeueOutputBuffer(bufferInfo, 10000);
      // render...
  }
  ```
- H.264デコーダーコンポーネント名: `OMX.qcom.video.decoder.avc`
- 対応プロファイル: Baseline / Main / High, Level 4.1まで (1080p@30fps)
- コールドスタート遅延: 200〜400ms
- ストリーム途中の解像度変更不可 (flush + reconfigure が必要)
- `KEY_OPERATING_RATE`, `KEY_PRIORITY` などのキーはAPI 19では存在しない

### H.264エンコード設定 (VideoToolbox)
- プロファイル: **Baseline** (SGP312の古いHWデコーダーへの互換性最大化)
- ビットレート: 4Mbps デフォルト (2〜8Mbps adaptive)
- 解像度: 1280x800
- FPS: 30 (負荷が高い場合は15に下げる)
- 低レイテンシのためにBフレームを無効にすること

### CGVirtualDisplay
- macOS 12.3以降のプライベートAPIだが、macOS 15まで動作確認済
- オブジェクトを解放すると即座に仮想ディスプレイが消える → ライフサイクル管理注意
- 解像度変更は destroy → recreate が必要
- Appleの署名エンタイトルメントなしでも開発・個人利用は可能

### USB 2.0帯域
- H.264圧縮後 (4〜10Mbps) はUSB 2.0帯域 (実効25〜40MB/s) の5%未満 → ボトルネックにならない

---

## 開発フェーズ

### Phase 0: 仮想ディスプレイ検証 (ケーブル不要)
- DeskPadのCGVirtualDisplay実装を参考にmacOSアプリを最小実装
- macOSのSystem SettingsにDisplay 2として表示されることを確認
- **ここが失敗すると全体が崩れるため最初に検証**

### Phase 1 MVP (ケーブル必要)
- ADB接続 + `adb forward` 動作確認
- 静止画 (PNG) をTCP経由でAndroidに送信
- SurfaceViewに表示 (エンコード/デコードなし)

### Phase 2
- ライブH.264ストリーミング (15fps)
- VideoToolbox エンコード + MediaCodec デコード
- エンドツーエンドのパイプライン確立

### Phase 3
- 30fps + 低レイテンシ最適化
- レイテンシ目標: < 50ms (理想: 20〜30ms)
- バッファサイズ / キーフレーム間隔チューニング

### Phase 4
- 拡張ディスプレイ対応 (Phase 0の仮想ディスプレイを本統合)
- Macウィンドウのドラッグ移動

---

## 接続テスト手順 (ケーブル購入後)

```bash
# 1. SGP312のUSBデバッグを有効化
# 設定 → タブレット情報 → ビルド番号を7回タップ → 開発者向けオプション → USBデバッグ ON

# 2. Mac側準備
brew install android-platform-tools
adb kill-server

# 3. ケーブル接続 (タブレットの画面ロックを解除した状態で)
# タブレットに「RSA鍵を許可しますか？」が表示されたら「常に許可」

# 4. 確認
adb devices
# 期待: <シリアル>    device

adb shell getprop ro.product.model
# 期待: SGP312

# 5. MediaCodecデコーダー確認
adb shell stagefright --list-components 2>&1 | grep -i avc
# 期待: OMX.qcom.video.decoder.avc が含まれる

# 6. adb forward動作確認
adb forward tcp:9000 localabstract:tablet_mirror
adb forward --list
```

---

## エラーハンドリング早見表

| 症状 | 原因 | 対処 |
|------|------|------|
| `adb devices` に何も出ない | 充電専用ケーブル | データ通信対応ケーブルに交換 |
| `unauthorized` | RSA承認されていない | タブレット画面の承認ダイアログを確認 |
| デバイスが数秒で消える | 画面オフでデバッグ停止 | 開発者オプション「スリープにしない」をON |
| 黒画面 | MediaCodec初期化失敗またはSurface未準備 | codecの初期化ログを確認 |
| 高レイテンシ | ビットレートまたは解像度が高すぎる | fps→15, bitrate→2Mbps, 解像度→1024x768に下げる |

---

## 有料アプリ不使用の方針

- BetterDisplay Pro など有料アプリは使用しない
- 仮想ディスプレイはCGVirtualDisplayを自前実装で解決
- 全コンポーネントを自前開発またはOSS参考で実装する
