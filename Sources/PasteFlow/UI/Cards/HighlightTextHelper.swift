import SwiftUI

public enum HighlightTextHelper {
    /// Applies search term highlighting to a plain string, returning an AttributedString
    public static func highlight(text: String, query: String) -> AttributedString {
        let attr = AttributedString(text)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return attr
        }
        
        return highlight(attributedString: attr, query: trimmedQuery)
    }
    
    /// Applies search term highlighting to an existing AttributedString
    public static func highlight(attributedString: AttributedString, query: String) -> AttributedString {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return attributedString
        }
        
        var result = attributedString
        let plain = String(result.characters)
        guard !plain.isEmpty else { return result }
        
        // Split query into distinct keywords (ignore single punctuation or empty)
        let tokens = trimmedQuery.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        for token in tokens {
            var searchStart = plain.startIndex
            while searchStart < plain.endIndex,
                  let foundRange = plain.range(of: token, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<plain.endIndex) {
                
                if let attrStart = AttributedString.Index(foundRange.lowerBound, within: result),
                   let attrEnd = AttributedString.Index(foundRange.upperBound, within: result) {
                    // Distinct, modern highlight styling: subtle amber/yellow background with slight border radius
                    result[attrStart..<attrEnd].backgroundColor = Color.yellow.opacity(0.38)
                    result[attrStart..<attrEnd].inlinePresentationIntent = .stronglyEmphasized
                }
                
                searchStart = foundRange.upperBound
            }
        }
        
        return result
    }
}
