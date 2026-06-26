import AVFoundation
import Foundation

/// Mixes the mic + system recordings into a single 16 kHz mono m4a for
/// transcription. Real sample-level mix with adaptive ducking (system is
/// attenuated while the user speaks) and clipping protection — ported from the
/// Rust `ffmpeg_mixer` behaviour. Output is 16 kHz mono (ideal for Whisper).
public enum AudioMixer {
    private static let sr: Double = 16000
    private static let duckThreshold: Float = 0.01
    private static let duckGain: Float = 0.6

    public static func mix(mic: URL?, system: URL?, output: URL) async -> URL? {
        let micS = mic.flatMap { decode16kMono($0) }
        let sysS = system.flatMap { decode16kMono($0) }
        guard micS != nil || sysS != nil else { return nil }
        let out = mixSamples(micS ?? [], sysS ?? [])
        guard !out.isEmpty else { return mic ?? system }
        return encodeM4A(out, to: output) ? output : (mic ?? system)
    }

    /// Mixes two 16 kHz mono sample streams (mic + system) into one, index-aligned,
    /// with adaptive ducking (system attenuated while the user speaks) and clipping
    /// protection. The shorter stream is padded with silence. Used for the LIVE
    /// transcript only — the FINAL transcript transcribes mic and system SEPARATELY
    /// and de-duplicates (see AppModel.process / TranscriptMerge), so the quieter
    /// side is never lost in a mono mix.
    public static func mixSamples(_ mic: [Float], _ system: [Float]) -> [Float] {
        let n = max(mic.count, system.count)
        guard n > 0 else { return [] }
        var out = [Float](repeating: 0, count: n)
        let win = 1600
        var i = 0
        while i < n {
            let end = min(i + win, n)
            var sum: Float = 0
            var cnt = 0
            var j = i
            while j < end {
                if j < mic.count { let v = mic[j]; sum += v * v; cnt += 1 }; j += 1
            }
            let micRMS = cnt > 0 ? (sum / Float(cnt)).squareRoot() : 0
            let gain: Float = micRMS > duckThreshold ? duckGain : 1.0
            j = i
            while j < end {
                let a = j < mic.count ? mic[j] : 0
                let b = j < system.count ? system[j] : 0
                var v = a + b * gain
                if v > 1 { v = 1 } else if v < -1 { v = -1 }
                out[j] = v
                j += 1
            }
            i = end
        }
        return out
    }

    /// Decodes any audio file to a 16 kHz mono float array.
    private static func decode16kMono(_ url: URL) -> [Float]? {
        guard FileManager.default.fileExists(atPath: url.path),
              let file = try? AVAudioFile(forReading: url) else { return nil }
        let inFmt = file.processingFormat
        guard let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sr, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: inFmt, to: outFmt) else { return nil }
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: frames) else { return nil }
        do { try file.read(into: inBuf) } catch { return nil }
        let cap = AVAudioFrameCount(Double(frames) * sr / inFmt.sampleRate + 1024)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap) else { return nil }
        var done = false
        var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, status in
            if done { status.pointee = .noDataNow; return nil }
            done = true; status.pointee = .haveData; return inBuf
        }
        guard err == nil, let ch = outBuf.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: ch, count: Int(outBuf.frameLength)))
    }

    private static func encodeM4A(_ samples: [Float], to url: URL) -> Bool {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        guard let file = try? AVAudioFile(forWriting: url, settings: settings),
              let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sr, channels: 1, interleaved: false)
        else { return false }
        let chunk = 16000
        var i = 0
        while i < samples.count {
            let end = min(i + chunk, samples.count)
            let cnt = AVAudioFrameCount(end - i)
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: cnt) else { return false }
            buf.frameLength = cnt
            if let ch = buf.floatChannelData?[0] {
                samples.withUnsafeBufferPointer { p in
                    for k in 0 ..< Int(cnt) {
                        ch[k] = p[i + k]
                    }
                }
            }
            do { try file.write(from: buf) } catch { return false }
            i = end
        }
        return true
    }
}
