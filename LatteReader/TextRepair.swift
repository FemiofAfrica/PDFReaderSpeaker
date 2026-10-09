import Foundation

/// Repairs common PDF text extraction issues: missing ligatures (U+0000) and broken apostrophes/quotes.
struct TextRepair {
    private static var dictionaryWords: Set<String>?
    private static var repairCache: [String: String] = [:]
    private static let cacheQueue = DispatchQueue(label: "LatteReader.TextRepairCache")
    
    /// Load dictionary words once
    private static func loadDictionary() -> Set<String> {
        if let cached = dictionaryWords {
            return cached
        }
        
        var words = Set<String>()
        if let dictPath = ["/usr/share/dict/words", "/usr/dict/words"].first(where: { FileManager.default.fileExists(atPath: $0) }),
           let content = try? String(contentsOfFile: dictPath, encoding: .utf8) {
            words = Set(content.lowercased().components(separatedBy: .newlines).filter { !$0.isEmpty })
        }
        dictionaryWords = words
        return words
    }
    
    /// Check if a word is in the dictionary (case-insensitive, ignoring trailing punctuation)
    /// Also accepts if stripping common suffixes gives a dictionary word
    private static func isWord(_ candidate: String) -> Bool {
        let dictionary = loadDictionary()
        let cleaned = candidate.lowercased().trimmingCharacters(in: CharacterSet.letters.inverted)
        
        // Check exact match first
        if dictionary.contains(cleaned) {
            return true
        }
        
        // Try stripping common suffixes
        let suffixes = ["ers", "ing", "ed", "es", "ly", "er", "s", "d"]
        for suffix in suffixes {
            if cleaned.hasSuffix(suffix) {
                let stem = String(cleaned.dropLast(suffix.count))
                if !stem.isEmpty && dictionary.contains(stem) {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Repair common PDF extraction issues
    static func repair(_ text: String) -> String {
        var result = text
        
        // 1. Fix apostrophes and quotes (handles U+2019 and \n)
        result = fixQuotesAndApostrophes(result)
        
        // 2. Fix missing ligatures (U+0000 → fi/ff/fl/ffi/ffl)
        result = fixLigatures(result)
        
        return result
    }
    
    /// Remove whitespace around apostrophes (U+2019 ') and quotes (U+201C/U+201D), including newlines
    private static func fixQuotesAndApostrophes(_ text: String) -> String {
        var result = text
        
        // Fix opening quotes: keep one space after a letter, remove whitespace after the quote
        // U+201C is " (left double quotation mark)
        // Handle: understand\n"\namortization → understand "amortization
        result = result.replacingOccurrences(of: "(\\p{L})\\s*([\"\u{201C}])", with: "$1 $2", options: .regularExpression)
        result = result.replacingOccurrences(of: "([\"\u{201C}])\\s+", with: "$1", options: .regularExpression)
        
        // Fix closing quotes: remove whitespace before the quote, keep one space after when followed by letter
        // U+201D is " (right double quotation mark)
        result = result.replacingOccurrences(of: "\\s+([\"\u{201D}])", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "([\"\u{201D}])(\\p{L})", with: "$1 $2", options: .regularExpression)
        
        // Fix apostrophes: collapse whitespace (including \n) around ' (ASCII) or ' (U+2019) between letters
        // Handle: it'\ns, you\n're, there\n'\ns, he\n'\ns, you\n'\nve, etc.
        // U+2019 is ' (right single quotation mark)
        let apostrophePattern = "(\\p{L})\\s*['\u{2019}]\\s*(\\p{L})"
        result = result.replacingOccurrences(of: apostrophePattern, with: "$1'$2", options: .regularExpression)
        
        return result
    }
    
    /// Fix missing ligatures: U+0000 (NUL) → fi, ff, fl, ffi, ffl
    private static func fixLigatures(_ text: String) -> String {
        let ligatures = ["fi", "ff", "fl", "ffi", "ffl"]
        
        // Find all words (maximal runs of letters plus U+0000)
        var result = ""
        var currentWord = ""
        
        for char in text {
            if char.isLetter || char == "\u{0}" {
                currentWord.append(char)
            } else {
                // End of word
                if currentWord.contains("\u{0}") {
                    // Check cache first
                    let cached = cacheQueue.sync { repairCache[currentWord] }
                    if let cached = cached {
                        result.append(cached)
                    } else {
                        let repaired = repairWord(currentWord, ligatures: ligatures)
                        cacheQueue.sync { repairCache[currentWord] = repaired }
                        result.append(repaired)
                    }
                } else {
                    result.append(currentWord)
                }
                result.append(char)
                currentWord = ""
            }
        }
        
        // Handle last word
        if !currentWord.isEmpty {
            if currentWord.contains("\u{0}") {
                let cached = cacheQueue.sync { repairCache[currentWord] }
                if let cached = cached {
                    result.append(cached)
                } else {
                    let repaired = repairWord(currentWord, ligatures: ligatures)
                    cacheQueue.sync { repairCache[currentWord] = repaired }
                    result.append(repaired)
                }
            } else {
                result.append(currentWord)
            }
        }
        
        return result
    }
    
    /// Repair a single word containing U+0000 by trying ligature replacements
    /// Prefers ffi/ffl over fi/fl when context suggests it
    private static func repairWord(_ word: String, ligatures: [String]) -> String {
        // Find all positions of U+0000
        let nulPositions = word.enumerated().compactMap { $0.element == "\u{0}" ? $0.offset : nil }
        
        guard !nulPositions.isEmpty else { return word }
        
        // Reorder ligatures to prefer longer ones when context suggests it
        // For "o\u{0}cers", prefer ffi before fi (gives "officers" vs "oficers")
        var orderedLigatures = ligatures
        if nulPositions.count == 1 {
            let pos = nulPositions[0]
            let before = pos > 0 ? String(word[word.index(word.startIndex, offsetBy: pos - 1)]) : ""
            let after = pos < word.count - 1 ? String(word[word.index(word.startIndex, offsetBy: pos + 1)]) : ""
            
            // If surrounded by letters that could be part of ffi/ffl, try those first
            if before == "f" || before == "o" {
                orderedLigatures = ["ffi", "ffl", "fi", "ff", "fl"]
            }
        }
        
        // Generate all combinations of ligature replacements (cartesian product)
        func generateCandidates(_ positions: [Int], _ ligatures: [String], _ baseWord: String) -> [String] {
            guard let firstPos = positions.first else {
                return [baseWord]
            }
            
            var candidates: [String] = []
            let remainingPositions = Array(positions.dropFirst())
            
            for ligature in ligatures {
                var modified = baseWord
                let index = modified.index(modified.startIndex, offsetBy: firstPos)
                modified.replaceSubrange(index...index, with: ligature)
                
                // Recursively replace remaining NULs
                let subCandidates = generateCandidates(remainingPositions.map { $0 + ligature.count - 1 }, ligatures, modified)
                candidates.append(contentsOf: subCandidates)
            }
            
            return candidates
        }
        
        let candidates = generateCandidates(nulPositions, orderedLigatures, word)
        
        // Pick first candidate that's a dictionary word (with suffix stripping)
        for candidate in candidates {
            if isWord(candidate) {
                return candidate
            }
        }
        
        // Fall back: replace all U+0000 with "fi"
        return word.replacingOccurrences(of: "\u{0}", with: "fi")
    }
}
