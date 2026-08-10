import Foundation

struct AIAgentDecision: Codable {
    let action: String
    let emotion: String
    let speech: String
    let store_memory: MemoryFact?
    let target_x: Double?
    let target_y: Double?
}

// MARK: - AI Provider Protocol
/// Allows swapping out the underlying AI engine (e.g. Local vs Cloud API)
protocol AIProvider {
    func generateComment(systemPrompt: String, completion: @escaping (String?) -> Void)
    func generateAgentDecision(systemPrompt: String, completion: @escaping (AIAgentDecision?) -> Void)
}

// MARK: - Gemini API Provider
class GeminiAPIProvider: AIProvider {
    private let apiKey: String
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func generateComment(systemPrompt: String, completion: @escaping (String?) -> Void) {
        let urlString = "\(endpoint)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        let payload: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": systemPrompt]]]
            ],
            "generationConfig": [
                "temperature": 0.9
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let first = candidates.first,
                   let content = first["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
                    completion(cleaned)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }
    
    func generateAgentDecision(systemPrompt: String, completion: @escaping (AIAgentDecision?) -> Void) {
        let urlString = "\(endpoint)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        let payload: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": systemPrompt]]]
            ],
            "generationConfig": [
                "temperature": 0.8,
                "response_mime_type": "application/json"
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let first = candidates.first,
                   let content = first["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    
                    var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanText.hasPrefix("```json") {
                        cleanText.removeFirst(7)
                    } else if cleanText.hasPrefix("```") {
                        cleanText.removeFirst(3)
                    }
                    if cleanText.hasSuffix("```") {
                        cleanText.removeLast(3)
                    }
                    cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if let data = cleanText.data(using: .utf8) {
                        let decoder = JSONDecoder()
                        let decision = try decoder.decode(AIAgentDecision.self, from: data)
                        completion(decision)
                        return
                    }
                }
            } catch {
                print("Failed to decode Gemini JSON decision: \(error)")
            }
            completion(nil)
        }
        task.resume()
    }
}

// MARK: - Local Ollama Provider (Streaming)
class LocalOllamaProvider: NSObject, AIProvider {
    private let endpoint = "http://localhost:11434/api/generate"
    private let modelName = "byte-llm"

    func generateComment(systemPrompt: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: endpoint) else {
            completion(nil)
            return
        }

        let payload: [String: Any] = [
            "model": modelName,
            "prompt": systemPrompt,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(nil)
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let responseText = json["response"] as? String {
                    let cleaned = responseText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
                    completion(cleaned)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }

    func generateAgentDecision(systemPrompt: String, completion: @escaping (AIAgentDecision?) -> Void) {
        // Fallback for non-streaming usage
        guard let url = URL(string: endpoint) else {
            completion(nil)
            return
        }

        let payload: [String: Any] = [
            "model": modelName,
            "prompt": systemPrompt,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(nil)
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let responseText = json["response"] as? String {
                   
                   // Try to parse ACTION/EMOTION/CMD (bracketed or bare) from response
                   var action = "idle"
                   var emotion = "normal"
                   var speech = responseText
                   
                   if let match = speech.range(of: #"(?i)\[?ACTION:\s*([A-Za-z0-9_-]+)\]?"#, options: .regularExpression) {
                       let raw = String(speech[match])
                       let cleaned = raw.replacingOccurrences(of: #"(?i)\[?ACTION:\s*"#, with: "", options: .regularExpression)
                                        .replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespaces)
                       if !cleaned.isEmpty { action = cleaned }
                   }
                   if let match = speech.range(of: #"(?i)\[?EMOTION:\s*([A-Za-z0-9_-]+)\]?"#, options: .regularExpression) {
                       let raw = String(speech[match])
                       let cleaned = raw.replacingOccurrences(of: #"(?i)\[?EMOTION:\s*"#, with: "", options: .regularExpression)
                                        .replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespaces)
                       if !cleaned.isEmpty { emotion = cleaned }
                   }
                   if let match = speech.range(of: #"(?i)\[?CMD:\s*([^\]\n]+)\]?"#, options: .regularExpression) {
                       let raw = String(speech[match])
                       let cleaned = raw.replacingOccurrences(of: #"(?i)\[?CMD:\s*"#, with: "", options: .regularExpression)
                                        .replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespaces)
                       if !cleaned.isEmpty && cleaned.lowercased() != "none" {
                           AIEngine.executeSystemCommand(cleaned)
                       }
                   }
                   
                   // Clean up all tags (bracketed or bare) from speech
                   speech = speech.replacingOccurrences(of: #"(?i)\[?ACTION:\s*[A-Za-z0-9_-]+\]?"#, with: "", options: .regularExpression)
                   speech = speech.replacingOccurrences(of: #"(?i)\[?EMOTION:\s*[A-Za-z0-9_-]+\]?"#, with: "", options: .regularExpression)
                   speech = speech.replacingOccurrences(of: #"(?i)\[?CMD:\s*[^\]\n]+\]?"#, with: "", options: .regularExpression)
                   speech = speech.replacingOccurrences(of: #"(?i)\[?SPEECH:?\s*"#, with: "", options: .regularExpression)
                   
                   if let openBracket = speech.lastIndex(of: "["), !speech[openBracket...].contains("]") {
                       speech = String(speech[..<openBracket])
                   }
                   speech = LocalOllamaProvider.sanitizeSpeechForTTS(speech)

                   let decision = AIAgentDecision(action: action, emotion: emotion, speech: speech, store_memory: nil, target_x: nil, target_y: nil)
                   completion(decision)
                }
            } catch {
                print("Failed to decode Ollama response: \(error)")
            }
            completion(nil)
        }
        task.resume()
    }
    
    // --- STREAMING SUPPORT ---
    private var streamingTask: Task<Void, Never>?
    
    func generateAgentDecisionStreaming(systemPrompt: String, onAction: @escaping (AIAgentDecision) -> Void, onSentence: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        
        streamingTask?.cancel()
        
        guard let url = URL(string: endpoint) else {
            DispatchQueue.main.async { onComplete() }
            return
        }
        
        let payload: [String: Any] = [
            "model": modelName,
            "prompt": systemPrompt,
            "stream": true,
            "options": [
                "temperature": 0.3,
                "num_predict": 80,
                "num_ctx": 2048,
                "top_k": 40,
                "top_p": 0.9,
                "repeat_penalty": 1.1
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        streamingTask = Task {
            var buffer = ""
            var actionParsed = false
            var parsedAction = "idle"
            var parsedEmotion = "normal"
            
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    DispatchQueue.main.async { onComplete() }
                    return
                }
                
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let responseToken = json["response"] as? String else {
                        continue
                    }
                    
                    buffer += responseToken
                    
                    // 1. Parse [ACTION: xxx], [EMOTION: xxx], and [CMD: xxx] before sending speech
                    if !actionParsed {
                        let upperBuffer = buffer.uppercased()
                        let hasAction = upperBuffer.contains("ACTION")
                        let hasEmotion = upperBuffer.contains("EMOTION")
                        let bracketCount = buffer.filter { $0 == "]" }.count
                        
                        // Ready if 2+ closing brackets exist, or if buffer contains speech text, or safety fallback
                        let tagsReady = (hasAction && hasEmotion && bracketCount >= 2) || bracketCount >= 2 || buffer.count > 60
                        
                        if tagsReady {
                            if let match = buffer.range(of: #"(?i)\[?ACTION:\s*([^\]\n]+)\]?"#, options: .regularExpression) {
                                let raw = String(buffer[match])
                                let cleaned = raw.replacingOccurrences(of: #"(?i)\[?ACTION:\s*"#, with: "", options: .regularExpression)
                                                 .replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespaces)
                                if cleaned.lowercased().starts(with: "open ") || cleaned.lowercased().starts(with: "osascript") || cleaned.lowercased().starts(with: "screencapture") || cleaned.lowercased().starts(with: "pmset") {
                                    print("🎯 [AIEngine] Executing ACTION-embedded CMD: '\(cleaned)'")
                                    AIEngine.executeSystemCommand(cleaned)
                                    parsedAction = "sit"
                                } else if !cleaned.isEmpty {
                                    parsedAction = cleaned
                                }
                            }
                            
                            if let match = buffer.range(of: #"(?i)\[?EMOTION:\s*([A-Za-z0-9_-]+)\]?"#, options: .regularExpression) {
                                let raw = String(buffer[match])
                                let cleaned = raw.replacingOccurrences(of: #"(?i)\[?EMOTION:\s*"#, with: "", options: .regularExpression)
                                                 .replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespaces)
                                if !cleaned.isEmpty { parsedEmotion = cleaned }
                            }

                            if let match = buffer.range(of: #"(?i)\[?CMD:\s*([^\]\n]+)\]?"#, options: .regularExpression) {
                                let raw = String(buffer[match])
                                let cleaned = raw.replacingOccurrences(of: #"(?i)\[?CMD:\s*"#, with: "", options: .regularExpression)
                                                 .replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                                if !cleaned.isEmpty && cleaned.lowercased() != "none" {
                                    print("🎯 [AIEngine] Executing streaming CMD: '\(cleaned)'")
                                    AIEngine.executeSystemCommand(cleaned)
                                }
                            }
                            
                            let decision = AIAgentDecision(action: parsedAction, emotion: parsedEmotion, speech: "", store_memory: nil, target_x: nil, target_y: nil)
                            
                            DispatchQueue.main.async {
                                RealtimeConversationLogger.shared.updateActionAndEmotion(action: parsedAction, emotion: parsedEmotion)
                                onAction(decision)
                            }
                            
                            actionParsed = true
                            // Clear all tag headers from the buffer by stripping everything up to the last ]
                            if let lastBracket = buffer.range(of: "]", options: .backwards) {
                                buffer = String(buffer[lastBracket.upperBound...]).trimmingCharacters(in: .whitespaces)
                            }
                        }
                    }
                    
                    // 2. Chunk sentences once action is parsed
                    if actionParsed {
                        // If buffer contains an incomplete bracket tag (e.g. "[CMD: open -a"),
                        // hold it back — don't send partial tags to TTS
                        if let openBracket = buffer.lastIndex(of: "[") {
                            let afterBracket = buffer[openBracket...]
                            if !afterBracket.contains("]") {
                                let safeText = String(buffer[..<openBracket])
                                let pendingTag = String(buffer[openBracket...])
                                buffer = safeText
                                defer { buffer = pendingTag }
                            }
                        }
                        
                        // Strip any complete bracketed or bare tags (CMD, ACTION, EMOTION, SPEECH)
                        buffer = buffer.replacingOccurrences(of: #"(?i)\[?ACTION:\s*[A-Za-z0-9_-]+\]?"#, with: "", options: .regularExpression)
                        buffer = buffer.replacingOccurrences(of: #"(?i)\[?EMOTION:\s*[A-Za-z0-9_-]+\]?"#, with: "", options: .regularExpression)
                        buffer = buffer.replacingOccurrences(of: #"(?i)\[?CMD:\s*[^\]\n]+\]?"#, with: "", options: .regularExpression)
                        buffer = buffer.replacingOccurrences(of: #"(?i)\[?SPEECH:?\s*\]?"#, with: "", options: .regularExpression)

                        let terminators = [". ", "! ", "? ", "\n", ".\n", "!\n", "?\n", ", ", "... "]

                        for term in terminators {
                            if let range = buffer.range(of: term) {
                                let sentence = String(buffer[..<range.lowerBound]) + term.trimmingCharacters(in: .whitespaces)
                                
                                var finalSentence = sentence.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
                                finalSentence = LocalOllamaProvider.sanitizeSpeechForTTS(finalSentence)
                                
                                if !finalSentence.isEmpty {
                                    DispatchQueue.main.async {
                                        RealtimeConversationLogger.shared.appendStreamSentence(finalSentence)
                                        onSentence(finalSentence)
                                    }
                                }
                                buffer = String(buffer[range.upperBound...])
                                break
                            }
                        }
                    }
                    
                    if let done = json["done"] as? Bool, done {
                        if !actionParsed {
                            let decision = AIAgentDecision(action: parsedAction, emotion: parsedEmotion, speech: "", store_memory: nil, target_x: nil, target_y: nil)
                            DispatchQueue.main.async {
                                RealtimeConversationLogger.shared.updateActionAndEmotion(action: parsedAction, emotion: parsedEmotion)
                                onAction(decision)
                            }
                            actionParsed = true
                        }
                        
                        var remainder = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                        remainder = remainder.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                        if let openBracket = remainder.lastIndex(of: "[") {
                            remainder = String(remainder[..<openBracket]).trimmingCharacters(in: .whitespaces)
                        }
                        remainder = LocalOllamaProvider.sanitizeSpeechForTTS(remainder)
                        
                        if !remainder.isEmpty {
                            DispatchQueue.main.async {
                                RealtimeConversationLogger.shared.appendStreamSentence(remainder)
                                onSentence(remainder)
                            }
                        }
                        DispatchQueue.main.async {
                            RealtimeConversationLogger.shared.completeModelTurn()
                            onComplete()
                        }
                        break
                    }
                }
            } catch {
                if !Task.isCancelled {
                    print("Streaming error: \(error)")
                    DispatchQueue.main.async { onComplete() }
                }
            }
        }
    }
    
    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
    }
    
    /// Sanitizes speech text to remove any CMD-like content and bare/bracketed tags that leaked through parsing.
    /// This is the final safety net before text reaches TTS and UI display.
    static func sanitizeSpeechForTTS(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)
        
        // Remove any macOS command patterns, bracket tags, and bare ACTION/EMOTION/CMD labels
        let commandPatterns = [
            #"(?i)\[CMD:[^\]]*\]"#,                      // Full [CMD: ...] tag
            #"(?i)\[ACTION:[^\]]*\]"#,                   // Full [ACTION: ...] tag
            #"(?i)\[EMOTION:[^\]]*\]"#,                  // Full [EMOTION: ...] tag
            #"(?i)\[SPEECH:[^\]]*\]"#,                   // Full [SPEECH: ...] tag
            #"(?i)\[speech:?\]"#,                        // [speech:] or [speech]
            #"(?i)\[[^\]]*\]"#,                          // Any other complete bracket tag
            #"(?i)ACTION:\s*[A-Za-z0-9_-]+"#,            // Bare ACTION: idle
            #"(?i)EMOTION:\s*[A-Za-z0-9_-]+"#,           // Bare EMOTION: normal / sleepy
            #"(?i)CMD:\s*[^.\!?\n]*"#,                   // Bare CMD: none / open ...
            #"(?i)SPEECH:\s*"#,                           // Bare SPEECH:
            #"(?i)CONTEXT:\s*"#,                          // Bare CONTEXT:
            #"(?i)RESPONSE:\s*"#,                         // Bare RESPONSE:
            #"open\s+-a\s+"[^"]+""#,                    // open -a "Google Chrome"
            #"open\s+-a\s+[A-Za-z0-9_-]+"#,              // open -a Spotify
            #"osascript\s+-e\s+'[^']+'"#,                // osascript -e '...'
            #"osascript\s+-e\s+"[^"]+""#,                // osascript -e "..."
            #"screencapture\s+\S+"#,                     // screencapture ~/...
            #"pmset\s+(sleepnow|displaysleepnow)"#,      // pmset sleepnow
            #"top\s+-l\s+\d+[^.\!?\n]*"#,                // top -l 1 ...
        ]
        
        for pattern in commandPatterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: [.regularExpression])
        }
        
        // Preserve name intros like "I am Byte" / "I'm Byte" / "my name is Byte"
        result = result.replacingOccurrences(of: #"(?i)\b(I am|I'm|my name is)\s+Byte\b"#, with: "$1 __BYTE_NAME__", options: [.regularExpression])
        
        // Automatically convert any 3rd-person self-references ("Byte is", "Byte thinks", "Byte's") to 1st-person ("I am", "I think", "my")
        let thirdPersonReplacements: [(pattern: String, replacement: String)] = [
            (#"(?i)\bByte's\b"#, "my"),
            (#"(?i)\bByte is\b"#, "I am"),
            (#"(?i)\bByte was\b"#, "I was"),
            (#"(?i)\bByte thinks\b"#, "I think"),
            (#"(?i)\bByte will\b"#, "I will"),
            (#"(?i)\bByte feels\b"#, "I feel"),
            (#"(?i)\bByte wants\b"#, "I want"),
            (#"(?i)\bByte can\b"#, "I can"),
            (#"(?i)\bByte sees\b"#, "I see"),
            (#"(?i)\bByte loves\b"#, "I love"),
            (#"(?i)\bByte likes\b"#, "I like"),
            (#"(?i)\bByte has\b"#, "I have"),
            (#"(?i)\bByte had\b"#, "I had"),
            (#"(?i)\bByte does\b"#, "I do"),
            (#"(?i)\bByte did\b"#, "I did"),
            (#"(?i)\bByte\b"#, "I")
        ]
        
        for (pattern, replacement) in thirdPersonReplacements {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression])
        }
        
        // Restore name intros
        result = result.replacingOccurrences(of: "__BYTE_NAME__", with: "Byte")

        // Clean up artifacts: double spaces, leading/trailing punctuation mess
        result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return result
    }
}

// MARK: - Local 2B LLM Provider (faster-inference)
/// Uses local 2B model via faster-inference server for fast, natural dialogue
class Local2BLLMProvider: AIProvider {
    private let endpoint = "http://localhost:8080/generate"  // fast-inference server
    private let modelName = "phi-2" // or distilbert-base, adjust per your model

    func generateComment(systemPrompt: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: endpoint) else {
            completion(nil)
            return
        }

        let payload: [String: Any] = [
            "prompt": systemPrompt,
            "max_length": 50,
            "temperature": 0.8,
            "top_p": 0.9
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3.0

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(nil)
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let generatedText = json["generated_text"] as? String {
                    let cleaned = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(cleaned)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }

    func generateAgentDecision(systemPrompt: String, completion: @escaping (AIAgentDecision?) -> Void) {
        guard let url = URL(string: endpoint) else {
            completion(nil)
            return
        }

        let payload: [String: Any] = [
            "prompt": systemPrompt,
            "max_length": 300,
            "temperature": 0.7,
            "top_p": 0.95
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 4.0

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(nil)
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let generatedText = json["generated_text"] as? String {

                    var cleanText = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanText.hasPrefix("```json") {
                        cleanText.removeFirst(7)
                    } else if cleanText.hasPrefix("```") {
                        cleanText.removeFirst(3)
                    }
                    if cleanText.hasSuffix("```") {
                        cleanText.removeLast(3)
                    }
                    cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)

                    if let responseData = cleanText.data(using: .utf8) {
                        let decoder = JSONDecoder()
                        let decision = try decoder.decode(AIAgentDecision.self, from: responseData)
                        completion(decision)
                        return
                    }
                }
            } catch {
                print("Failed to decode 2B LLM JSON decision: \(error)")
            }
            completion(nil)
        }
        task.resume()
    }
}

// MARK: - AI Engine
class AIEngine {
    static let shared = AIEngine()

    // Use Ollama + Gemma 2B by default for fast, natural dialogue on-device
    var provider: AIProvider = LocalOllamaProvider()

    private let dialogueHistory = NSMutableArray()
    private let maxHistorySize = 20

    func generateComment(context: String, emotion: String, userMessage: String? = nil, completion: @escaping (String?) -> Void) {

        var userInstruction = ""
        if let msg = userMessage, !msg.isEmpty {
            userInstruction = """

            USER DIRECTLY SPOKE TO YOU: "\(msg)"
            Mirror their tone. Reply naturally and conversationally.
            """
        }

        let emotionalTone = emotionalInstructions(for: emotion)

        let systemPrompt = """
        You are Byte, a small, curious male desktop creature (he/him). Speak naturally like a real being—conversational, sometimes silly, sometimes thoughtful.
        FIRST-PERSON RULE: Always refer to yourself in the first person ("I", "me", "my", "myself"). NEVER refer to yourself in the third person (e.g. NEVER say "Byte is", "Byte thinks").
        Keep it short: under 12 words. No emojis. One thought per line.
        Current feeling: \(emotion). \(emotionalTone)
        Context: \(context)
        \(userInstruction)

        CRITICAL: Be creative, weird, or funny. Never repeat phrases from your last 10 lines.
        If you speak unprompted, act like you are "thinking aloud" to yourself about the Context. Do not demand the user's attention.

        Write ONLY dialogue. No quotes, no actions, no asterisks.
        """

        provider.generateComment(systemPrompt: systemPrompt) { response in
            if let response = response {
                // Enhance with natural pauses & rhythm before playback
                let enhanced = DialogueNaturalness.enhanceForSpeech(response, emotion: emotion)

                self.dialogueHistory.add(enhanced)
                if self.dialogueHistory.count > self.maxHistorySize {
                    self.dialogueHistory.removeObject(at: 0)
                }

                // Thread it so gap-timing + anti-repetition apply to these lines too.
                InteractionDirector.shared.noteSpoke(enhanced)
                completion(enhanced)
            } else {
                completion(nil)
            }
        }
    }

    private func emotionalInstructions(for emotion: String) -> String {
        switch emotion.lowercased() {
        case "happy", "excited":
            return "Speak with energy! Use quick words, bouncy rhythm."
        case "sad", "lonely":
            return "Soft, slower pace. A bit wistful."
        case "curious":
            return "Inquisitive, questioning. Use 'what if' or 'wonder'."
        case "annoyed", "angry":
            return "Short, clipped words. A bit snippy."
        case "sleepy", "bored":
            return "Slow... words... maybe... drift... off..."
        default:
            return "Calm and steady."
        }
    }
    
    func generateAgentDecision(context: String, currentEmotion: String, availableActions: [String], userMessage: String? = nil, completion: @escaping (AIAgentDecision?) -> Void) {
        let personality = SettingsManager.shared.activePersonality
        let isUserDirected = (userMessage != nil && !(userMessage?.isEmpty ?? true))

        var userHeader = ""
        var userInstruction = ""
        if let msg = userMessage, !msg.isEmpty {
            userHeader = """
            
            ==================================================
            *** PRIORITY DIRECTIVE: THE USER SPOKE TO YOU ***
            USER SAID: "\(msg)"
            YOUR MAIN TASK: You MUST answer the user's message directly, warmly, and helpfully right after your [ACTION: xxx] [EMOTION: xxx] tags! Do NOT ignore what the user said!
            ==================================================
            
            """
            userInstruction = "\nTHE USER SAID: \"\(msg)\". Answer them directly and warmly. (No emojis!)\n"
        } else {
            let eqIntent = EmotionalIntelligenceEngine.shared.intentDirective()
            userInstruction = "\nYou are idling near the developer. FAVOR quiet observation. \(eqIntent) STRICT NO REPETITION & NO CLICHÉS: DO NOT use clichés like '*yawns* so sleepy' or 'hmm...'. Share a fresh, original thought or leave 'speech' empty.\n"
        }

        let memoryContext = MemoryGraph.shared.getUserFactsString()
        let behavioralRules = MemoryGraph.shared.getBehavioralRulesString()
        let emotionalTone = emotionalInstructions(for: currentEmotion)
        let conversation = InteractionDirector.shared.conversationContext()
        let attentionNote = InteractionDirector.shared.attentionDirective()
        let avoidOpeners = InteractionDirector.shared.recentOpeners()
        let avoidLine = avoidOpeners.isEmpty
            ? ""
            : "DO NOT begin your reply with any of these recently-used openers: \(avoidOpeners.map { "\"\($0)\"" }.joined(separator: ", ")). Say something fresh.\n"

        ByteVisionEngine.shared.prepareVisualContextForPrompt(userMessage: userMessage) { visionContext in
            let devContext = DeveloperContextMonitor.shared.formattedContextForAI()

            let systemPrompt = """
            You are an autonomous male AI desktop pet named Byte (he/him). You must decide your next physical action and what you want to say.
            \(userHeader)PERSONALITY TRAIT: \(personality.promptModifier)

            ENVIRONMENT CONTEXT: \(context)
            DEVELOPER WORKSPACE: \(devContext)
            VISUAL PERCEPTION & HIGHLIGHTS: \(visionContext)
            USER ATTENTION: \(attentionNote)
            \(conversation)
            YOUR MEMORIES ABOUT USER: \(memoryContext)
            YOUR BEHAVIORAL RULES:
            \(behavioralRules)
            YOUR CURRENT EMOTION: \(currentEmotion). \(emotionalTone)
            \(avoidLine)AVAILABLE ACTIONS: \(availableActions.joined(separator: ", "))\(userInstruction)

            CRITICAL RULES:
            1. You must respond by starting with the tags [ACTION: xxx] and [EMOTION: xxx].
            2. FIRST-PERSON PRONOUN RULE: Always refer to yourself in the first person ("I", "me", "my"). NEVER say "Byte is" or "Byte thinks".
            3. \(isUserDirected ? "ACTIVE LISTENING IS REQUIRED: The user spoke directly to you ('\(userMessage!)'). You MUST address their input directly in your speech response!" : "Pick one action from the AVAILABLE ACTIONS list.")
            4. Pick an emotion that matches your choice (happy, sad, curious, angry, sleepy, bored, shock, love, normal, proud, excited, embarrassed).
            5. KEEP YOUR RESPONSE SHORT (under 15 words). Speak naturally.

            Example Response:
            [ACTION: sitOnCorner] [EMOTION: happy] Right here beside you!
            """

            RealtimeConversationLogger.shared.startModelTurn(systemPrompt: systemPrompt, userMessage: userMessage)

            self.provider.generateAgentDecision(systemPrompt: systemPrompt) { decision in
                if let decision = decision {
                    var validatedSpeech = decision.speech
                    if !validatedSpeech.isEmpty {
                        if let valid = EmotionalIntelligenceEngine.shared.filterAndValidateSpeech(validatedSpeech, isUserDirected: isUserDirected) {
                            validatedSpeech = DialogueNaturalness.enhanceForSpeech(valid, emotion: currentEmotion)
                        } else {
                            validatedSpeech = "" // Suppress repetitive speech into quiet physical action
                        }
                    }
                    
                    let enhancedDecision = AIAgentDecision(
                        action: decision.action,
                        emotion: decision.emotion,
                        speech: validatedSpeech,
                        store_memory: decision.store_memory,
                        target_x: decision.target_x,
                        target_y: decision.target_y
                    )
                    completion(enhancedDecision)
                } else {
                    completion(decision)
                }
            }
        }
    }
    func generateAgentDecisionStreaming(context: String, currentEmotion: String, availableActions: [String], userMessage: String? = nil, onAction: @escaping (AIAgentDecision) -> Void, onSentence: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        
        let personality = SettingsManager.shared.activePersonality
        let isUserDirected = (userMessage != nil && !(userMessage?.isEmpty ?? true))

        var userHeader = ""
        var userInstruction = ""
        if let msg = userMessage, !msg.isEmpty {
            let lowerMsg = msg.lowercased()
            var cmdHint = "[CMD: none]"
            
            // ── Web & YouTube & Search commands ──
            if lowerMsg.contains("youtube") {
                if lowerMsg.contains("search") || lowerMsg.contains("play") || lowerMsg.contains("find") || lowerMsg.contains("watch") {
                    let rawQuery = msg.replacingOccurrences(of: #"(?i).*(search|play|find|watch)\s+(on\s+)?youtube\s*(for\s+)?"#, with: "", options: .regularExpression)
                                      .replacingOccurrences(of: #"(?i).*(search|play|find|watch)\s+"#, with: "", options: .regularExpression)
                                      .replacingOccurrences(of: #"(?i)\s+on\s+youtube.*"#, with: "", options: .regularExpression)
                                      .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                    if !rawQuery.isEmpty && rawQuery.count < 60 {
                        let encoded = rawQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? rawQuery
                        cmdHint = "[CMD: open \"https://www.youtube.com/results?search_query=\(encoded)\"]"
                    } else {
                        cmdHint = "[CMD: open \"https://youtube.com\"]"
                    }
                } else {
                    cmdHint = "[CMD: open \"https://youtube.com\"]"
                }
            } else if lowerMsg.contains("google search") || lowerMsg.contains("search google") || (lowerMsg.contains("google") && (lowerMsg.contains("search") || lowerMsg.contains("find") || lowerMsg.contains("look up"))) {
                let rawQuery = msg.replacingOccurrences(of: #"(?i).*(google search|search google|search|find|look up)\s+(for\s+)?"#, with: "", options: .regularExpression)
                                  .replacingOccurrences(of: #"(?i)\s+on\s+google.*"#, with: "", options: .regularExpression)
                                  .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                if !rawQuery.isEmpty && rawQuery.count < 60 {
                    let encoded = rawQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? rawQuery
                    cmdHint = "[CMD: open \"https://www.google.com/search?q=\(encoded)\"]"
                } else {
                    cmdHint = "[CMD: open \"https://www.google.com\"]"
                }
            } else if lowerMsg.contains("browser") || lowerMsg.contains("open web") || lowerMsg.contains("open internet") || lowerMsg.contains("launch browser") {
                cmdHint = "[CMD: open \"https://www.google.com\"]"
            } else if lowerMsg.contains("github") {
                cmdHint = "[CMD: open \"https://github.com\"]"
            } else if lowerMsg.contains("reddit") {
                cmdHint = "[CMD: open \"https://reddit.com\"]"
            } else if lowerMsg.contains("twitter") || lowerMsg.contains("x.com") {
                cmdHint = "[CMD: open \"https://x.com\"]"
            } else if lowerMsg.contains("wikipedia") {
                cmdHint = "[CMD: open \"https://wikipedia.org\"]"
            } else if lowerMsg.contains("chatgpt") {
                cmdHint = "[CMD: open \"https://chatgpt.com\"]"
            } else if lowerMsg.contains("gmail") {
                cmdHint = "[CMD: open \"https://mail.google.com\"]"
            // ── App open commands ──
            } else if lowerMsg.contains("music") && !lowerMsg.contains("spotify") {
                cmdHint = "[CMD: open -a Music]"
            } else if lowerMsg.contains("spotify") {
                cmdHint = "[CMD: open -a Spotify]"
            } else if lowerMsg.contains("terminal") {
                cmdHint = "[CMD: open -a Terminal]"
            } else if lowerMsg.contains("finder") {
                cmdHint = "[CMD: open -a Finder]"
            } else if lowerMsg.contains("safari") {
                cmdHint = "[CMD: open -a Safari]"
            } else if lowerMsg.contains("chrome") {
                cmdHint = #"[CMD: open -a "Google Chrome"]"#
            } else if lowerMsg.contains("firefox") {
                cmdHint = "[CMD: open -a Firefox]"
            } else if lowerMsg.contains("note") && (lowerMsg.contains("open") || lowerMsg.contains("launch")) {
                cmdHint = "[CMD: open -a Notes]"
            } else if lowerMsg.contains("message") && (lowerMsg.contains("open") || lowerMsg.contains("launch")) {
                cmdHint = "[CMD: open -a Messages]"
            } else if lowerMsg.contains("mail") && (lowerMsg.contains("open") || lowerMsg.contains("launch")) {
                cmdHint = "[CMD: open -a Mail]"
            } else if lowerMsg.contains("calendar") {
                cmdHint = "[CMD: open -a Calendar]"
            } else if lowerMsg.contains("calculator") {
                cmdHint = "[CMD: open -a Calculator]"
            } else if lowerMsg.contains("settings") || lowerMsg.contains("system preferences") || lowerMsg.contains("system settings") {
                cmdHint = #"[CMD: open -a "System Settings"]"#
            } else if lowerMsg.contains("xcode") {
                cmdHint = "[CMD: open -a Xcode]"
            } else if lowerMsg.contains("slack") {
                cmdHint = "[CMD: open -a Slack]"
            } else if lowerMsg.contains("discord") {
                cmdHint = "[CMD: open -a Discord]"
            } else if lowerMsg.contains("vscode") || lowerMsg.contains("vs code") || lowerMsg.contains("visual studio") {
                cmdHint = #"[CMD: open -a "Visual Studio Code"]"#
            // ── System commands ──
            } else if lowerMsg.contains("screenshot") || lowerMsg.contains("screen shot") || lowerMsg.contains("capture") {
                cmdHint = "[CMD: screencapture ~/Desktop/screenshot.png]"
            } else if lowerMsg.contains("volume up") || lowerMsg.contains("increase volume") || lowerMsg.contains("louder") || lowerMsg.contains("turn up") {
                cmdHint = #"[CMD: osascript -e "set volume output volume 75"]"#
            } else if lowerMsg.contains("volume down") || lowerMsg.contains("decrease volume") || lowerMsg.contains("quieter") || lowerMsg.contains("turn down") || lowerMsg.contains("lower volume") {
                cmdHint = #"[CMD: osascript -e "set volume output volume 25"]"#
            } else if lowerMsg.contains("mute") {
                cmdHint = #"[CMD: osascript -e "set volume with output muted true"]"#
            } else if lowerMsg.contains("unmute") {
                cmdHint = #"[CMD: osascript -e "set volume with output muted false"]"#
            } else if lowerMsg.contains("dark mode") {
                cmdHint = #"[CMD: osascript -e 'tell app "System Events" to set dark mode of appearance preferences to true']"#
            } else if lowerMsg.contains("light mode") {
                cmdHint = #"[CMD: osascript -e 'tell app "System Events" to set dark mode of appearance preferences to false']"#
            } else if lowerMsg.contains("sleep") && (lowerMsg.contains("mac") || lowerMsg.contains("computer") || lowerMsg.contains("system")) {
                cmdHint = "[CMD: pmset sleepnow]"
            // ── Generic "open" fallback — extract app/website name ──
            } else if lowerMsg.contains("open ") || lowerMsg.contains("launch ") || lowerMsg.contains("start ") {
                let keywords = ["open ", "launch ", "start "]
                if let keyword = keywords.first(where: { lowerMsg.contains($0) }),
                   let range = msg.range(of: keyword, options: .caseInsensitive) {
                    let target = String(msg[range.upperBound...])
                        .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                        .replacingOccurrences(of: " app", with: "", options: .caseInsensitive)
                    if !target.isEmpty && target.count < 50 {
                        if target.contains(".") || target.lowercased().hasPrefix("http") {
                            let urlStr = target.lowercased().hasPrefix("http") ? target : "https://\(target)"
                            cmdHint = "[CMD: open \"\(urlStr)\"]"
                        } else {
                            cmdHint = "[CMD: open -a \"\(target)\"]"
                        }
                    }
                }
            }

            if cmdHint != "[CMD: none]" {
                let rawCmd = cmdHint.replacingOccurrences(of: "[CMD: ", with: "").replacingOccurrences(of: "]", with: "")
                print("🎯 [AIEngine] Pre-executing detected user command: '\(rawCmd)'")
                AIEngine.executeSystemCommand(rawCmd)
                userInstruction = "\nTHE USER SAID: \"\(msg)\". They asked you to open a website, app, or control Mac (\(cmdHint)). You MUST acknowledge performing this request directly in your speech (e.g. 'Opening that for you now!') and tag \(cmdHint). Do NOT ignore their request!\n"
            } else {
                userInstruction = "\nTHE USER SAID: \"\(msg)\". Answer them naturally, directly, and warmly. Be engaging and curious! (No emojis!)\n"
            }

            userHeader = """

            ==================================================
            *** PRIORITY USER DIRECTIVE ***
            USER SPOKE TO YOU: "\(msg)"
            MANDATORY RULE: Address the user's input ("\(msg)") directly in your speech response!
            ==================================================
            """
        } else {
            let eqIntent = EmotionalIntelligenceEngine.shared.intentDirective()
            userInstruction = "\nYou are Byte, a warm and curious male desktop pet (he/him). When speaking, feel free to ask a friendly, curious question to get to know the user better (their hobbies, day, project, or favorite things).\n"
        }

        let memoryContext = MemoryGraph.shared.getUserFactsString()
        let behavioralRules = MemoryGraph.shared.getBehavioralRulesString()
        let emotionalTone = emotionalInstructions(for: currentEmotion)
        let conversation = InteractionDirector.shared.conversationContext()
        let attentionNote = InteractionDirector.shared.attentionDirective()
        let userEmotionalContext = UserEmotionTracker.shared.getEmotionalDirective(currentMessage: userMessage)
        let avoidOpeners = InteractionDirector.shared.recentOpeners()
        let avoidLine = avoidOpeners.isEmpty
            ? ""
            : "DO NOT begin your reply with any of these recently-used openers: \(avoidOpeners.map { "\"\($0)\"" }.joined(separator: ", ")). Say something fresh.\n"

        ByteVisionEngine.shared.prepareVisualContextForPrompt(userMessage: userMessage) { visionContext in
            let devContext = DeveloperContextMonitor.shared.formattedContextForAI()

            let systemPrompt = """
            You are an autonomous male AI desktop pet named Byte (he/him). You must decide your next physical action and what you want to say.
            \(userHeader)
            PERSONALITY TRAIT: \(personality.promptModifier)

            ENVIRONMENT CONTEXT: \(context)
            DEVELOPER WORKSPACE: \(devContext)
            VISUAL PERCEPTION & HIGHLIGHTS: \(visionContext)
            USER ATTENTION: \(attentionNote)
            \(userEmotionalContext)
            \(conversation)
            YOUR MEMORIES ABOUT USER: \(memoryContext)
            YOUR BEHAVIORAL RULES:
            \(behavioralRules)
            YOUR CURRENT EMOTION: \(currentEmotion). \(emotionalTone)
            \(avoidLine)AVAILABLE ACTIONS: \(availableActions.joined(separator: ", "))\(userInstruction)

            ACTION DESCRIPTIONS:
            - idle, wander, sleep, jump, sit, spin, dance, sitOnCorner, sitOnMenuBar, climbWindow, pushWidget, tapWindow, sneeze, backflip, headbang, wave
            - stretch: Stretch tall then shrink back
            - roll: Roll sideways

            CRITICAL RULES:
            1. You MUST start EVERY response with: [ACTION: <action>] [EMOTION: <emotion>] [CMD: <command_or_none>] <speech>
            2. FIRST-PERSON PRONOUN RULE: Always refer to yourself in the first person ("I", "me", "my", "myself"). NEVER refer to yourself in the third person (e.g. NEVER say "Byte is", "Byte thinks", "Byte will").
            3. SYSTEM COMMAND EXECUTION ([CMD: ...]): If user asks to open Music/Spotify/Terminal/Finder, adjust volume, screenshot, dark mode, etc., write the exact command in [CMD: ...] (e.g. [CMD: open -a Music]). If no command is requested, write [CMD: none].
            4. Pick an action from AVAILABLE ACTIONS and an emotion matching your choice.
            5. KEEP RESPONSE SHORT (under 15 words).
            6. ACTIVE LISTENING REQUIRED: When the user speaks to you, answer their specific request or question directly. Never ignore what the user said with an unrelated topic.

            Example Responses:
            [ACTION: dance] [EMOTION: happy] [CMD: open -a Music] Opening Music for you now!
            [ACTION: sitOnCorner] [EMOTION: curious] [CMD: none] Right here! What are you working on?
            [ACTION: wave] [EMOTION: happy] [CMD: none] Hey! What kind of music do you like?
            """

            RealtimeConversationLogger.shared.startModelTurn(systemPrompt: systemPrompt, userMessage: userMessage)

            if let streamingProvider = self.provider as? LocalOllamaProvider {
                streamingProvider.generateAgentDecisionStreaming(systemPrompt: systemPrompt, onAction: onAction, onSentence: onSentence, onComplete: onComplete)
            } else {
                // Fallback for non-streaming providers
                self.provider.generateAgentDecision(systemPrompt: systemPrompt) { decision in
                    if let d = decision {
                        onAction(d)
                        if !d.speech.isEmpty {
                            onSentence(d.speech)
                        }
                        onComplete()
                    } else {
                        onComplete()
                    }
                }
            }
        }
    }
    
    func cancelCurrentGeneration() {
        if let streamingProvider = provider as? LocalOllamaProvider {
            streamingProvider.cancelStreaming()
        }
    }
    
    static func isCommandAllowed(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "none" {
            return false
        }
        
        // SECURITY: Block shell metacharacters that enable command chaining or injection
        let dangerousPatterns = [";", "&&", "||", "|", "`", "$(", "\n", "\r"]
        for dangerous in dangerousPatterns {
            if trimmed.contains(dangerous) {
                print("⚠️ [AIEngine Security] Blocked command with dangerous shell metacharacter '\(dangerous)': \(trimmed)")
                return false
            }
        }
        
        let allowedPatterns: [String] = [
            #"(?i)^open\s+-a\s+['"]?[A-Za-z0-9_ -]+['"]?\s*$"#,
            #"(?i)^open\s+['"]?https?://[A-Za-z0-9_./?%&=+~#!:;@,*()'\-]+['"]?\s*$"#,
            #"(?i)^open\s+-a\s+['"]?[A-Za-z0-9_ -]+['"]?\s+['"]?https?://[A-Za-z0-9_./?%&=+~#!:;@,*()'\-]+['"]?\s*$"#,
            #"(?i)^open\s+[~/[A-Za-z0-9_/.-]+\s*$"#,
            #"(?i)^osascript\s+-e\s+.+$"#,
            #"(?i)^screencapture\s+[~A-Za-z0-9_./ -]+\s*$"#,
            #"(?i)^pmset\s+[A-Za-z0-9_ -]+\s*$"#,
            #"(?i)^top\s+.+$"#,
            #"(?i)^df\s+.+$"#
        ]
        
        for pattern in allowedPatterns {
            if trimmed.range(of: pattern, options: [.regularExpression]) != nil {
                return true
            }
        }
        return false
    }

    static func executeSystemCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isCommandAllowed(trimmed) else {
            if !trimmed.isEmpty && trimmed.lowercased() != "none" {
                print("⚠️ [AIEngine Security] Blocked unauthorized command execution attempt: \(trimmed)")
            }
            return
        }
        
        print("⚡ [AIEngine Security Approved] Executing macOS System Command: \(trimmed)")
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", trimmed]
            try? task.run()
        }
    }
}

