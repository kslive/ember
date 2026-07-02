import CoreGraphics

/// Shared audio-level math. The RMS loop and the meter-bar transform were hand-copied
/// across RecordingEngine / SystemAudioTap / AppModel; keeping ONE definition means the
/// mic and system level bars scale identically (and the DSP can't drift between copies).
public enum AudioLevel {
    /// Root-mean-square over `n` contiguous Floats (no allocation).
    public static func rms(_ p: UnsafePointer<Float>, _ n: Int) -> Float {
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0 ..< n {
            sum += p[i] * p[i]
        }
        return (sum / Float(n)).squareRoot()
    }

    public static func rms(_ samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return 0 }
            return rms(base, buf.count)
        }
    }

    /// Peak (max |sample|) over `n` contiguous Floats. Speech-vs-silence detection
    /// must use PEAK, not mean RMS: a window/recording of real speech mixed with
    /// pauses has a LOW average RMS but clear peaks, so an RMS gate wrongly drops a
    /// quiet-but-real microphone channel while keeping continuous loud system audio.
    public static func peak(_ p: UnsafePointer<Float>, _ n: Int) -> Float {
        guard n > 0 else { return 0 }
        var m: Float = 0
        for i in 0 ..< n {
            let a = abs(p[i])
            if a > m { m = a }
        }
        return m
    }

    public static func peak(_ samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return 0 }
            return peak(base, buf.count)
        }
    }

    /// Maps an RMS amplitude to a 0...1 meter-bar value. Mic and system bars MUST use
    /// this single definition so they scale identically.
    public static func meter(_ rms: Float) -> CGFloat {
        CGFloat(min(1, Double(rms).squareRoot() * 3))
    }

    /// Count of leading samples to drop as silence (up to the first sample exceeding
    /// `threshold`, minus `leadIn` samples of context). Whisper "snaps" speech to t=0
    /// when fed a clip with a long silent lead-in, misplacing timecodes — trim it and
    /// add the trimmed offset back as the segment base. Returns 0 when speech starts
    /// immediately; `samples.count` when the whole buffer is silent.
    public static func leadingSilence(_ samples: [Float], threshold: Float, leadIn: Int = 1600) -> Int {
        var i = 0
        while i < samples.count, abs(samples[i]) <= threshold {
            i += 1
        }
        return max(0, i - leadIn)
    }
}
