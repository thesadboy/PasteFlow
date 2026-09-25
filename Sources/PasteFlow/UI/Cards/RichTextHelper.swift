import AppKit
import SwiftUI

private final class AttributedStringBox {
    let value: AttributedString
    init(_ value: AttributedString) { self.value = value }
}

public enum RichTextHelper {
    private static let cache: NSCache<NSString, AttributedStringBox> = {
        let c = NSCache<NSString, AttributedStringBox>()
        c.countLimit = 300
        return c
    }()
    
    /// Parses raw RTF or HTML data into a SwiftUI AttributedString, adapted for card previews.
    public static func renderRichText(data: Data?, itemId: UUID? = nil) -> AttributedString? {
        guard let data = data, !data.isEmpty else { return nil }
        
        let cacheKey = itemId?.uuidString ?? "\(data.count)_\(data.prefix(16).hashValue)"
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached.value
        }
        
        var nsAttr: NSAttributedString?
        
        // Fast signature check for RTF: starts with "{\rtf"
        let isRTF = data.prefix(5).elementsEqual([0x7B, 0x5C, 0x72, 0x74, 0x66])
        
        if isRTF {
            nsAttr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        } else {
            // Try HTML or fallback to RTF
            nsAttr = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
            
            if nsAttr == nil {
                nsAttr = try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
            }
        }
        
        guard let rawAttr = nsAttr, rawAttr.length > 0 else {
            return nil
        }
        
        // Normalize fonts and adjust contrast for dark/light themes
        let mutable = NSMutableAttributedString(attributedString: rawAttr)
        let fullRange = NSRange(location: 0, length: mutable.length)
        
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        
        // Normalize font sizes (11 ~ 14pt)
        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            if let font = value as? NSFont {
                let scaledSize = min(max(font.pointSize, 11), 14)
                let descriptor = font.fontDescriptor
                if let newFont = NSFont(descriptor: descriptor, size: scaledSize) {
                    mutable.addAttribute(.font, value: newFont, range: range)
                }
            } else {
                mutable.addAttribute(.font, value: NSFont.systemFont(ofSize: 13), range: range)
            }
        }
        
        // Adapt foreground colors for contrast against card background
        mutable.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { (value: Any?, range: NSRange, _: UnsafeMutablePointer<ObjCBool>) in
            guard let color = value as? NSColor,
                  let rgbColor = color.usingColorSpace(.sRGB) else {
                mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
                return
            }
            let r: CGFloat = rgbColor.redComponent
            let g: CGFloat = rgbColor.greenComponent
            let b: CGFloat = rgbColor.blueComponent
            let brightness: CGFloat = (r * 0.299) + (g * 0.587) + (b * 0.114)
            if isDarkMode && brightness < 0.28 {
                mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            } else if !isDarkMode && brightness > 0.82 {
                mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            }
        }
        
        let swiftUIAttr = AttributedString(mutable)
        cache.setObject(AttributedStringBox(swiftUIAttr), forKey: cacheKey as NSString)
        return swiftUIAttr
    }
}
