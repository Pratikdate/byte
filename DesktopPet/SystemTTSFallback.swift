import AVFoundation

/// Fallback TTS using macOS native speech synthesis
/// Used when Kokoro server is not available
class SystemTTSFallback: NSObject, AVSpeechSynthesizerDelegate {

    static let shared = SystemTTSFallback()
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, emotion: String = "neutral", completion: (() -> Void)? = nil) {
        self.completion = completion
        let processedText = DialogueNaturalness.enhanceForSpeech(text, emotion: emotion)
        guard !processedText.isEmpty else {
            completion?()
            return
        }

        let utterance = AVSpeechUtterance(string: processedText)

        // Map emotion to speech characteristics
        utterance.rate = SystemTTSFallback.speechRateForEmotion(emotion)
        utterance.pitchMultiplier = SystemTTSFallback.pitchForEmotion(emotion)
        utterance.volume = 0.9

        // Use system voice
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }

        synthesizer.speak(utterance)
    }

    /// Immediately stop any in-progress speech (barge-in).
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        completion?()
        completion = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completion?()
        completion = nil
    }

    private static func speechRateForEmotion(_ emotion: String) -> Float {
        switch emotion.lowercased() {
        case "excited", "happy":
            return AVSpeechUtteranceDefaultSpeechRate * 1.1  // Slightly faster
        case "sleepy", "sad", "bored":
            return AVSpeechUtteranceDefaultSpeechRate * 0.9  // Slightly slower
        case "annoyed", "angry":
            return AVSpeechUtteranceDefaultSpeechRate * 1.05 // A bit faster
        default:
            return AVSpeechUtteranceDefaultSpeechRate        // Normal speed
        }
    }

    private static func pitchForEmotion(_ emotion: String) -> Float {
        switch emotion.lowercased() {
        case "happy", "excited":
            return 1.4  // Higher pitch
        case "sad", "lonely":
            return 1.0  // Lower pitch
        case "annoyed", "angry":
            return 1.3  // Slightly higher
        default:
            return 1.2  // Normal (softer/smaller)
        }
    }
}
