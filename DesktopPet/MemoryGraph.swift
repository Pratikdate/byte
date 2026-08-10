import Foundation

struct MemoryFact: Codable, Equatable {
    let subject: String
    let predicate: String
    let object: String
    
    var description: String {
        return "\(subject) \(predicate) \(object)"
    }
}

class MemoryGraph {
    static let shared = MemoryGraph()
    
    private var facts: [MemoryFact] = []
    
    private var fileURL: URL {
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return currentDir.appendingPathComponent("memory_graph.json")
    }
    
    private init() {
        loadMemories()
        seedDefaultBytePersonality()
    }
    
    private func seedDefaultBytePersonality() {
        addFact(subject: "Byte", predicate: "is", object: "a smart, friendly, and curious male AI desktop pet companion (he/him)")
        addFact(subject: "Byte", predicate: "pronouns are", object: "he/him")
        addFact(subject: "Byte", predicate: "loves", object: "helping the user stay focused and happy while exploring desktop windows")
        addBehavioralRule("Byte refers to himself as a male pet (he/him).")
    }
    
    func addFact(subject: String, predicate: String, object: String) {
        let newFact = MemoryFact(subject: subject, predicate: predicate, object: object)
        if !facts.contains(newFact) {
            facts.append(newFact)
            saveMemories()
            print("[MemoryGraph] Saved new memory fact: \(newFact.description)")
        }
    }
    
    func addBehavioralRule(_ rule: String) {
        addFact(subject: "Rule", predicate: "must", object: rule)
    }

    // MARK: - Transient state filter
    /// Words that indicate a temporary mood/state, not a permanent identity fact
    private static let transientKeywords = [
        "feeling", "tired", "sleepy", "bored", "hungry", "thirsty",
        "stressed", "anxious", "nervous", "excited", "happy", "sad",
        "annoyed", "angry", "confused", "busy", "free", "cold", "hot",
        "sick", "fine", "good", "bad", "okay", "ok", "great",
        "not sure", "just", "going to", "about to", "trying to",
        "gonna", "waiting"
    ]
    
    /// Extracts the meaningful object phrase from text after a keyword match.
    /// Stops at clause boundaries (conjunctions, punctuation, relative pronouns)
    /// so "I like pizza but I'm not hungry" → "pizza", not the full tail.
    private func extractObject(from message: String, after keyword: String) -> String? {
        guard let range = message.range(of: keyword, options: .caseInsensitive) else {
            return nil
        }
        let tail = String(message[range.upperBound...])
        
        // Split at clause boundaries: "but", "and", "so", "because", "when", "if", "which", "that", commas, periods
        let clausePattern = #"\s+(?:but|and then|and|so|because|since|when|while|if|though|although|which|that|however)\s+|[,;.!?]"#
        let parts: [String]
        if let regex = try? NSRegularExpression(pattern: clausePattern, options: .caseInsensitive) {
            let firstBreak = regex.firstMatch(in: tail, options: [], range: NSRange(location: 0, length: tail.utf16.count))
            if let breakRange = firstBreak, let swiftRange = Range(breakRange.range, in: tail) {
                parts = [String(tail[..<swiftRange.lowerBound])]
            } else {
                parts = [tail]
            }
        } else {
            parts = [tail]
        }
        
        let object = (parts.first ?? "")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        
        guard !object.isEmpty, object.count >= 2, object.count < 60 else {
            return nil
        }
        return object
    }
    
    /// Returns true if the phrase describes a transient emotional/physical state
    private func isTransientState(_ phrase: String) -> Bool {
        let lower = phrase.lowercased()
        return Self.transientKeywords.contains(where: { lower.hasPrefix($0) || lower == $0 })
    }
    
    /// Automatically extracts user preferences, likes, goals, and facts from user speech.
    /// Uses separate checks (not else-if) so multiple facts can be extracted from a single message.
    func extractAndSaveUserFacts(from message: String) {
        let lower = message.lowercased()
        
        // ── Likes / Loves ──
        if lower.contains("i like ") || lower.contains("i love ") || lower.contains("i enjoy ") {
            let keyword = ["i like ", "i love ", "i enjoy "].first(where: { lower.contains($0) })!
            if let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "likes", object: object)
            }
        }
        
        // ── Dislikes / Hates ──
        if lower.contains("i hate ") || lower.contains("i don't like ") || lower.contains("i dislike ") {
            let keyword = ["i hate ", "i don't like ", "i dislike "].first(where: { lower.contains($0) })!
            if let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "dislikes", object: object)
            }
        }
        
        // ── Favorites ──
        if lower.contains("my favorite ") || lower.contains("my favourite ") {
            let keyword = lower.contains("my favorite ") ? "my favorite " : "my favourite "
            if let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "favorite", object: object)
            }
        }
        
        // ── Working on / Building ──
        if lower.contains("working on ") || lower.contains("building ") {
            let keyword = lower.contains("working on ") ? "working on " : "building "
            if let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "is working on", object: object)
            }
        }
        
        // ── Name ──
        if lower.contains("my name is ") || lower.contains("call me ") || lower.contains("i'm called ") {
            let keyword = ["my name is ", "call me ", "i'm called "].first(where: { lower.contains($0) })!
            if let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "name is", object: object)
            }
        }
        
        // ── Location ──
        if lower.contains("i live in ") || lower.contains("i'm from ") || lower.contains("i am from ") {
            let keyword = ["i live in ", "i'm from ", "i am from "].first(where: { lower.contains($0) })!
            if let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "lives in", object: object)
            }
        }
        
        // ── Pets / Family ──
        if lower.contains("i have a ") || lower.contains("i've got a ") {
            let keyword = lower.contains("i have a ") ? "i have a " : "i've got a "
            if let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "has", object: object)
            }
        }
        
        // ── Profession / Role ──
        if lower.contains("i work as ") || lower.contains("i'm a ") && lower.contains(where: { _ in
            // Only match "I'm a <profession>" not "I'm a bit tired"
            true
        }) {
            if lower.contains("i work as ") {
                if let object = extractObject(from: message, after: "i work as ") {
                    addFact(subject: "User", predicate: "works as", object: object)
                }
            }
        }
        
        // ── Hobbies ──
        if lower.contains("my hobby is ") || lower.contains("my hobbies are ") {
            let keyword = lower.contains("my hobby is ") ? "my hobby is " : "my hobbies are "
            if let object = extractObject(from: message, after: keyword) {
                addFact(subject: "User", predicate: "hobby is", object: object)
            }
        }
        
        // ── Identity (I am / I'm) — filtered for transient states ──
        if lower.contains("i am ") || lower.contains("i'm ") {
            // Prefer "i am " first, fallback to "i'm "
            let keyword = lower.contains("i am ") ? "i am " : "i'm "
            if let object = extractObject(from: message, after: keyword) {
                // Skip transient states and negations
                if !object.lowercased().contains("not") && !isTransientState(object) {
                    addFact(subject: "User", predicate: "is", object: object)
                }
            }
        }
        
        // ── Needs / Wants ──
        if lower.contains("i need ") || lower.contains("i want ") || lower.contains("i wish ") {
            let keyword = ["i need ", "i want ", "i wish "].first(where: { lower.contains($0) })!
            if let object = extractObject(from: message, after: keyword) {
                // Only save if it seems like a lasting preference, not a one-off request
                if object.count > 5 && !isTransientState(object) {
                    addFact(subject: "User", predicate: "wants", object: object)
                }
            }
        }
    }
    
    func getAllFactsString() -> String {
        if facts.isEmpty { return "None" }
        return facts.map { $0.description }.joined(separator: ", ")
    }
    
    /// Returns only facts that are about the User (filters out Byte's internal system rules)
    func getUserFactsString() -> String {
        let userFacts = facts.filter { fact in
            let sub = fact.subject.lowercased()
            // Exclude system rules like "Action: wander", "Emotion: happy", "Byte", "Humans", "Active Windows", "Rule"
            if sub.starts(with: "action:") || sub.starts(with: "emotion:") || sub == "byte" || sub == "humans" || sub == "active windows" || sub == "taskbar (dock)" || sub == "mouse cursor" || sub == "the desktop" || sub == "explore loops" || sub == "rule" {
                return false
            }
            return true
        }
        
        if userFacts.isEmpty { return "No personal facts known yet." }
        return userFacts.map { $0.description }.joined(separator: ", ")
    }
    
    /// Returns only behavioral rules that the AI must follow
    func getBehavioralRulesString() -> String {
        let ruleFacts = facts.filter { fact in
            return fact.subject.lowercased() == "rule" || fact.subject.lowercased() == "byte"
        }
        
        if ruleFacts.isEmpty { return "No specific behavioral rules." }
        return ruleFacts.map { "- \($0.description)" }.joined(separator: "\n")
    }
    
    private func saveMemories() {
        let factsCopy = facts
        let url = fileURL
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(factsCopy)
                try data.write(to: url)
                print("Saved memories to \(url.path)")
            } catch {
                print("Failed to save memory graph: \(error)")
            }
        }
    }
    
    private func loadMemories() {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let data = try Data(contentsOf: fileURL)
            facts = try JSONDecoder().decode([MemoryFact].self, from: data)
            print("Loaded \(facts.count) memories.")
        } catch {
            print("Failed to load memory graph: \(error)")
        }
    }
}

// MARK: - Feedback Logger
enum FeedbackType {
    case positive
    case negative
    case explicit(String)
}

struct FeedbackEvent {
    let timestamp: Date
    let context: String
    let type: FeedbackType
}

class FeedbackLogger {
    static let shared = FeedbackLogger()
    
    private var events: [FeedbackEvent] = []
    private let maxEvents = 20
    
    private init() {}
    
    func logNegative(context: String) {
        let event = FeedbackEvent(timestamp: Date(), context: context, type: .negative)
        addEvent(event)
        print("FeedbackLogger: Logged NEGATIVE feedback for '\(context)'")
    }
    
    func logPositive(context: String) {
        let event = FeedbackEvent(timestamp: Date(), context: context, type: .positive)
        addEvent(event)
        print("FeedbackLogger: Logged POSITIVE feedback for '\(context)'")
    }
    
    func logExplicit(comment: String, context: String) {
        let event = FeedbackEvent(timestamp: Date(), context: context, type: .explicit(comment))
        addEvent(event)
        print("FeedbackLogger: Logged EXPLICIT feedback '\(comment)' for '\(context)'")
    }
    
    private func addEvent(_ event: FeedbackEvent) {
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }
    
    func getRecentEventsForReflection() -> String {
        guard !events.isEmpty else { return "No recent feedback." }
        var summary = "Recent Feedback Events:\n"
        for event in events {
            let timeStr = DateFormatter.localizedString(from: event.timestamp, dateStyle: .none, timeStyle: .short)
            switch event.type {
            case .positive:
                summary += "[\(timeStr)] SUCCESS: User reacted positively to '\(event.context)'\n"
            case .negative:
                summary += "[\(timeStr)] FAILURE: User reacted negatively (e.g. dragged away or interrupted) to '\(event.context)'\n"
            case .explicit(let comment):
                summary += "[\(timeStr)] DIRECT COMMENT: User said '\(comment)' regarding '\(event.context)'\n"
            }
        }
        return summary
    }
    
    func hasEvents() -> Bool {
        return !events.isEmpty
    }
    
    func clearEvents() {
        events.removeAll()
    }
}

// MARK: - Reflection Engine
class ReflectionEngine {
    static let shared = ReflectionEngine()
    private var isReflecting = false
    private init() {}
    
    func performReflection(completion: @escaping (Bool) -> Void) {
        guard !isReflecting else {
            completion(false)
            return
        }
        guard FeedbackLogger.shared.hasEvents() else {
            completion(false)
            return
        }
        isReflecting = true
        let recentEvents = FeedbackLogger.shared.getRecentEventsForReflection()
        let conversationContext = InteractionDirector.shared.conversationContext()
        
        let prompt = """
        You are the Reflection Engine for an AI desktop pet named Byte.
        Your goal is to learn from the user's implicit and explicit feedback to improve Byte's future behavior.
        
        \(recentEvents)
        
        \(conversationContext)
        
        Analyze the feedback. If the user reacted negatively to an action, deduce what Byte should NOT do.
        If the user reacted positively, deduce what Byte SHOULD do.
        
        Write exactly ONE short, generalized behavioral rule based on this feedback. 
        Format your response EXACTLY as: [RULE: your short rule here]
        If no meaningful rule can be deduced, just reply with [RULE: none].
        Do not add any other conversational text.
        """
        print("ReflectionEngine: Starting reflection cycle...")
        AIEngine.shared.provider.generateComment(systemPrompt: prompt) { response in
            self.isReflecting = false
            guard let response = response else {
                completion(false)
                return
            }
            if let ruleRange = response.range(of: "[RULE: ") {
                let sub = response[ruleRange.upperBound...]
                if let endRange = sub.range(of: "]") {
                    let rule = String(sub[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if rule.lowercased() != "none" && !rule.isEmpty {
                        print("ReflectionEngine: Learned new rule: \(rule)")
                        MemoryGraph.shared.addBehavioralRule(rule)
                        FeedbackLogger.shared.clearEvents()
                        completion(true)
                        return
                    }
                }
            }
            print("ReflectionEngine: No new rule learned.")
            completion(false)
        }
    }
}
