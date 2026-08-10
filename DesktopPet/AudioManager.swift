import Foundation
import AVFoundation

/// Wraps faster-whisper (local speech-to-text) + Kokoro TTS (local speech synthesis)
/// All processing runs on-device, no cloud dependency.
class AudioManager {
    static let shared = AudioManager()

    private let whisperEndpoint = "http://localhost:9000/transcribe"
    private let kokoroEndpoint = "http://localhost:8000/synthesize"

    private let audioEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayerNode?
    private let audioQueue = DispatchQueue(label: "com.byte.audio.queue")

    var onTranscriptionUpdate: ((String) -> Void)?
    var onTranscriptionFinished: ((String) -> Void)?
    var onSpeakingFinished: (() -> Void)?

    private(set) var isListening = false
    private(set) var isSpeaking = false

    private var accumulatedAudio = Data()
    private var lastSendTime = Date.distantPast

    func startListening() {
        guard !isListening else { return }
        isListening = true

        SystemSTT.shared.onTranscriptionUpdate = { [weak self] text in
            DispatchQueue.main.async {
                self?.onTranscriptionUpdate?(text)
            }
        }

        SystemSTT.shared.onTranscriptionFinished = { [weak self] text in
            DispatchQueue.main.async {
                self?.onTranscriptionFinished?(text)
            }
        }

        SystemSTT.shared.startListening()

        // Also run PCM capture in parallel as backup for Whisper
        audioQueue.async {
            self.accumulatedAudio.removeAll()
            self.lastSendTime = Date()
            self.captureAudioAndTranscribe()
        }
    }

    func stopListening() {
        isListening = false

        SystemSTT.shared.stopListeningAndTranscribe { [weak self] systemText in
            guard let self = self else { return }

            if self.audioEngine.isRunning {
                try? self.audioEngine.stop()
            }
            let inputNode = self.audioEngine.inputNode
            inputNode.removeTap(onBus: 0)

            let cleanSystemText = systemText.trimmingCharacters(in: .whitespacesAndNewlines)

            if !cleanSystemText.isEmpty {
                print("[AudioManager] System STT captured: '\(cleanSystemText)'")
                DispatchQueue.main.async {
                    self.onTranscriptionFinished?(cleanSystemText)
                }
            } else {
                print("[AudioManager] System STT empty or stalled, falling back to Whisper server on port 9000...")
                self.forceSendAudioToWhisper()
            }
        }
    }

    private func forceSendAudioToWhisper() {
        let dataToSend = self.accumulatedAudio
        guard let url = URL(string: self.whisperEndpoint) else {
            DispatchQueue.main.async {
                self.onTranscriptionFinished?("")
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = dataToSend
        request.timeoutInterval = 2.5

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let cleanWhisperText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[AudioManager] Whisper server returned: '\(cleanWhisperText)'")
                DispatchQueue.main.async {
                    self.onTranscriptionUpdate?(cleanWhisperText)
                    self.onTranscriptionFinished?(cleanWhisperText)
                }
            } else {
                print("[AudioManager] Whisper fallback empty or unreachable.")
                DispatchQueue.main.async {
                    self.onTranscriptionFinished?("")
                }
            }
        }.resume()
    }

    private var audioConverter: AVAudioConverter?

    /// Stream microphone → faster-whisper for real-time transcription
    private func captureAudioAndTranscribe() {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            print("[AudioManager] Failed to create 16kHz format")
            DispatchQueue.main.async {
                self.isListening = false
            }
            return
        }

        audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat)

        // Remove any existing tap before installing new one
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let converter = self.audioConverter else { return }

            let capacity = UInt32(Double(buffer.frameLength) * 16000.0 / inputFormat.sampleRate)
            // Add a little padding to capacity just in case
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity + 1024) else { return }

            var error: NSError?
            var allDone = false
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                if allDone {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                allDone = true
                outStatus.pointee = .haveData
                return buffer
            }

            if status != .error && status != .endOfStream {
                self.sendAudioToWhisper(convertedBuffer)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("[AudioManager] Audio engine failed: \(error)")
            DispatchQueue.main.async {
                self.isListening = false
            }
        }
    }

    /// POST PCM buffer to faster-whisper server
    private func sendAudioToWhisper(_ buffer: AVAudioPCMBuffer) {
        guard isListening else { return }

        // Safely extract audio data from buffer
        let audioBufferList = buffer.audioBufferList
        let audioBuffer = audioBufferList.pointee.mBuffers

        guard let pcmData = audioBuffer.mData else {
            print("[AudioManager] No PCM data in buffer")
            return
        }

        let frameLength = Int(buffer.frameLength)
        let bytesPerFrame = Int(audioBuffer.mDataByteSize) / max(frameLength, 1)
        let totalBytes = frameLength * bytesPerFrame

        let audioData = Data(bytes: pcmData, count: totalBytes)

        audioQueue.async { [weak self] in
            guard let self = self, self.isListening else { return }
            self.accumulatedAudio.append(audioData)

            let now = Date()
            if now.timeIntervalSince(self.lastSendTime) < 0.5 {
                return
            }
            self.lastSendTime = now

            let dataToSend = self.accumulatedAudio

            // Build request safely
            guard let url = URL(string: self.whisperEndpoint) else {
                print("[AudioManager] Invalid whisper endpoint URL")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.httpBody = dataToSend
            request.timeoutInterval = 2.0

            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("[AudioManager] Whisper request error: \(error.localizedDescription)")
                return
            }

            guard let data = data, !data.isEmpty else {
                print("[AudioManager] No data from whisper server")
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["text"] as? String,
                   !text.isEmpty {
                    DispatchQueue.main.async {
                        self.onTranscriptionUpdate?(text)
                        if json["is_final"] as? Bool == true {
                            self.onTranscriptionFinished?(text)
                        }
                    }
                }
            } catch {
                print("[AudioManager] Failed to parse whisper response: \(error)")
            }
        }.resume()
        }
    }

    /// Immediately stop any in-progress speech (barge-in for user interaction).
    func stopSpeaking() {
        downloadQueue.removeAll()
        readyAudioQueue.removeAll()
        audioQueue.async {
            self.audioPlayer?.stop()
        }
        SystemTTSFallback.shared.stop()
        isSpeaking = false
        isDownloading = false
    }

    private var downloadQueue: [(String, String, Float)] = []
    private var readyAudioQueue: [Data] = []
    private var isDownloading = false
    
    /// Generate speech with Kokoro TTS or fallback to system TTS
    /// - Parameter interrupt: if true, cut off any current speech first (used for user-directed replies)
    func speak(_ text: String, emotion: String = "neutral", speed: Float = 1.0, interrupt: Bool = false) {
        guard !text.isEmpty else { return }

        if interrupt {
            stopSpeaking()
        }

        downloadQueue.append((text, emotion, speed))
        processDownloadQueue()
    }

    private func processDownloadQueue() {
        guard !isDownloading, !downloadQueue.isEmpty else { return }

        let (text, emotion, speed) = downloadQueue.removeFirst()
        isDownloading = true

        let payload: [String: Any] = [
            "text": text,
            "emotion": emotion,
            "speed": speed,
            "voice_id": "am_onyx" // American Male TTS voice profile
        ]

        guard let url = URL(string: kokoroEndpoint) else {
            print("[AudioManager] Invalid Kokoro endpoint URL")
            DispatchQueue.main.async {
                SystemTTSFallback.shared.speak(text, emotion: emotion) {
                    DispatchQueue.main.async {
                        self.isDownloading = false
                        if self.readyAudioQueue.isEmpty && self.downloadQueue.isEmpty {
                            self.onSpeakingFinished?()
                        }
                        self.processDownloadQueue()
                    }
                }
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0 // More time for network variance

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            print("[AudioManager] Failed to serialize Kokoro payload: \(error)")
            DispatchQueue.main.async {
                SystemTTSFallback.shared.speak(text, emotion: emotion) {
                    DispatchQueue.main.async {
                        self.isDownloading = false
                        if self.readyAudioQueue.isEmpty && self.downloadQueue.isEmpty {
                            self.onSpeakingFinished?()
                        }
                        self.processDownloadQueue()
                    }
                }
            }
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // Fallback to system TTS if Kokoro unavailable
            if error != nil || data == nil {
                print("[AudioManager] Kokoro TTS unavailable, using system TTS")
                DispatchQueue.main.async {
                    self.isSpeaking = true
                    SystemTTSFallback.shared.speak(text, emotion: emotion) {
                        DispatchQueue.main.async {
                            self.isSpeaking = false
                            self.isDownloading = false
                            if self.readyAudioQueue.isEmpty && self.downloadQueue.isEmpty {
                                self.onSpeakingFinished?()
                            }
                            self.processDownloadQueue()
                        }
                    }
                }
                return
            }

            guard let audioData = data else {
                print("[AudioManager] No audio data from Kokoro")
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.processDownloadQueue()
                }
                return
            }

            DispatchQueue.main.async {
                self.readyAudioQueue.append(audioData)
                self.isDownloading = false
                self.processDownloadQueue() // keep downloading next items in background!
                self.processPlaybackQueue() // trigger playback if it's idle
            }
        }.resume()
    }

    private func processPlaybackQueue() {
        guard !isSpeaking, !readyAudioQueue.isEmpty else { return }
        
        let audioData = readyAudioQueue.removeFirst()
        isSpeaking = true
        playAudioData(audioData)
    }

    /// Play audio bytes from TTS server
    private func playAudioData(_ audioData: Data) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1) else {
            print("[AudioManager] Failed to create audio format for playback")
            isSpeaking = false
            processPlaybackQueue()
            return
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tts_\(UUID().uuidString).wav")

        do {
            try audioData.write(to: tempURL)

            let audioFile = try AVAudioFile(forReading: tempURL)
            let playerNode = AVAudioPlayerNode()

            // Detach any existing player nodes to prevent resource leaks
            if let existingPlayer = audioPlayer {
                audioEngine.detach(existingPlayer)
            }

            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFile.processingFormat)

            try audioEngine.start()
            playerNode.play()
            try playerNode.scheduleFile(audioFile, at: nil)

            audioPlayer = playerNode

            // Calculate duration with precision
            let sampleRate = Double(audioFile.processingFormat.sampleRate)
            let duration = sampleRate > 0 ? Double(audioFile.length) / sampleRate : 1.0

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.isSpeaking = false
                if self.readyAudioQueue.isEmpty && self.downloadQueue.isEmpty {
                    self.onSpeakingFinished?()
                }

                // Clean up
                playerNode.stop()
                try? FileManager.default.removeItem(at: tempURL)
                
                self.processPlaybackQueue()
            }
        } catch {
            print("[AudioManager] Audio playback error: \(error)")
            isSpeaking = false
            try? FileManager.default.removeItem(at: tempURL)
            processPlaybackQueue()
        }
    }
}
