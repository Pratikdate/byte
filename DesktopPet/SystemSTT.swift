import Foundation
import AVFoundation
import Speech

/// Native macOS Speech Recognizer using Apple's Speech Framework (SFSpeechRecognizer)
/// Uses macOS built-in Neural Engine dictation for instant real-time STT with zero latency.
class SystemSTT {
    static let shared = SystemSTT()

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    var onTranscriptionUpdate: ((String) -> Void)?
    var onTranscriptionFinished: ((String) -> Void)?

    private(set) var isListening = false
    private(set) var currentTranscript = ""

    private init() {
        requestPermission()
    }

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                print("[SystemSTT] macOS Speech Recognition Authorized.")
            case .denied:
                print("[SystemSTT] Speech Recognition Denied by user.")
            case .restricted:
                print("[SystemSTT] Speech Recognition Restricted on this Mac.")
            case .notDetermined:
                print("[SystemSTT] Speech Recognition Not Determined.")
            @unknown default:
                break
            }
        }
    }

    func startListening() {
        guard !isListening else { return }

        // Cancel previous recognition task if active
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        let inputNode = audioEngine.inputNode

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("[SystemSTT] Unable to create recognition request.")
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            recognitionRequest.addsPunctuation = true
        }

        isListening = true
        currentTranscript = ""

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                self.currentTranscript = text
                DispatchQueue.main.async {
                    self.onTranscriptionUpdate?(text)
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                if self.audioEngine.isRunning {
                    self.audioEngine.stop()
                }
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
                self.isListening = false
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("[SystemSTT] Native macOS Speech Engine Started.")
        } catch {
            print("[SystemSTT] Audio Engine failed to start: \(error)")
            isListening = false
        }
    }

    func stopListeningAndTranscribe(completion: @escaping (String) -> Void) {
        guard isListening else {
            completion(currentTranscript)
            return
        }

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        let resultText = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        isListening = false

        DispatchQueue.main.async {
            if !resultText.isEmpty {
                self.onTranscriptionFinished?(resultText)
            }
            completion(resultText)
        }
    }
}
