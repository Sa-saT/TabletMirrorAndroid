import CoreMedia
import Foundation
import VideoToolbox

// Phase 2: VTCompressionSession によるH.264ハードウェアエンコード
// Phase 1では使用しない。Phase 2でStreamSenderのPNG送信と差し替える。
//
// 実装予定:
//   - IOSurface → CVPixelBuffer (ゼロコピー)
//   - VTCompressionSession でH.264 Baselineエンコード
//   - Annex B NALユニット列をStreamSenderへ渡す
//   - 設定: 1280x800, 30fps, 4Mbps, Bフレームなし (低レイテンシ)
class VideoEncoder {
    // TODO: Phase 2で実装
}
