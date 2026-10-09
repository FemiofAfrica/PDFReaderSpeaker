import Foundation

/// Repairs common PDF text extraction issues: missing ligatures and broken apostrophes/quotes.
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
    
    /// Check if a word is in the dictionary
    private static func isWord(_ candidate: String) -> Bool {
        let dictionary = loadDictionary()
        return dictionary.contains(candidate.lowercased())
    }
    
    /// Repair common PDF extraction issues
    static func repair(_ text: String) -> String {
        var result = text
        
        // 1. Fix apostrophes and quotes
        result = fixQuotesAndApostrophes(result)
        
        // 2. Fix missing ligatures
        result = fixLigatures(result)
        
        return result
    }
    
    /// Remove whitespace around apostrophes and quotes
    private static func fixQuotesAndApostrophes(_ text: String) -> String {
        var result = text
        
        // Remove whitespace before closing " and after opening "
        result = result.replacingOccurrences(of: #"\s+""#, with: "\"", options: .regularExpression)
        result = result.replacingOccurrences(of: #""\s+"#, with: "\"", options: .regularExpression)
        
        // Fix apostrophes: remove space/newline around ' and ' when between letters or before common contractions
        // Patterns: it' s, you 're, there ' s, we 're, he ' s, etc.
        let apostrophePatterns = [
            (#"(\w)\s+['\']\s*s\b"#, "$1's"),           // it' s → it's
            (#"(\w)\s+['\']\s*re\b"#, "$1're"),         // you 're → you're
            (#"(\w)\s+['\']\s*ve\b"#, "$1've"),         // we 've → we've
            (#"(\w)\s+['\']\s*ll\b"#, "$1'll"),         // they 'll → they'll
            (#"(\w)\s+['\']\s*d\b"#, "$1'd"),           // he 'd → he'd
            (#"(\w)\s+['\']\s*t\b"#, "$1't"),           // don 't → don't
            (#"(\w)\s+['\']\s*m\b"#, "$1'm"),           // I 'm → I'm
            (#"(\w)['\']\s+(\w)"#, "$1'$2"),            // word' s → word's
            (#"(\w)\s+['\']\s+(\w)"#, "$1'$2")          // word ' s → word's
        ]
        
        for (pattern, replacement) in apostrophePatterns {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        
        return result
    }
    
    /// Fix missing ligatures (fi, ff, fl, ffi, ffl)
    private static func fixLigatures(_ text: String) -> String {
        let ligatures = ["fi", "ff", "fl", "ffi", "ffl"]
        var tokens = text.components(separatedBy: .whitespacesAndNewlines)
        
        for i in 0..<tokens.count {
            let token = tokens[i]
            guard !token.isEmpty else { continue }
            
            // Only process tokens with suspicious gaps (double space placeholder or non-word)
            let hasDoubleSpace = token.contains("  ")
            let isNonWord = !isWord(token.replacingOccurrences(of: #"[^\w]"#, with: "", options: .regularExpression))
            
            guard hasDoubleSpace || isNonWord else { continue }
            
            // Check cache first
            if let cached = cacheQueue.sync(execute: { repairCache[token] }) {
                tokens[i] = cached
                continue
            }
            
            var repaired = token
            
            // Try inserting ligatures at gaps
            // Gaps: runs of 1-2 spaces, or between letters where a ligature would make sense
            let gapPattern = #"(\w?)(\s{1,2}|\b)(\w?)"#
            if let regex = try? NSRegularExpression(pattern: gapPattern, options: []) {
                let nsString = token as NSString
                let matches = regex.matches(in: token, options: [], range: NSRange(location: 0, length: nsString.length))
                
                for match in matches.reversed() {
                    let fullRange = match.range
                    let before = match.range(at: 1)
                    let gap = match.range(at: 2)
                    let after = match.range(at: 3)
                    
                    guard gap.length > 0 else { continue }
                    
                    let beforeChar = before.length > 0 ? nsString.substring(with: before) : ""
                    let afterChar = after.length > 0 ? nsString.substring(with: after) : ""
                    
                    // Try each ligature
                    for ligature in ligatures {
                        let candidates = [
                            beforeChar + ligature + afterChar,  // with space removed
                            beforeChar + ligature + " " + afterChar  // keeping space
                        ]
                        
                        for candidate in candidates {
                            let testToken = nsString.replacingCharacters(in: fullRange, with: candidate)
                            let cleanTest = testToken.replacingOccurrences(of: #"[^\w]"#, with: "", options: .regularExpression)
                            
                            if isWord(cleanTest) && !isWord(token.replacingOccurrences(of: #"[^\w]"#, with: "", options: .regularExpression)) {
                                repaired = testToken
                                break
                            }
                        }
                        
                        if repaired != token {
                            break
                        }
                    }
                }
            }
            
            // Cache result
            cacheQueue.sync {
                repairCache[token] = repaired
            }
            tokens[i] = repaired
        }
        
        return tokens.joined(separator: " ")
    }
}
