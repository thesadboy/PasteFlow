import SwiftUI

public struct Pinboard: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var iconName: String
    public var order: Int
    public var createdAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#3B82F6",
        iconName: String = "pin.fill",
        order: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.order = order
        self.createdAt = createdAt
    }
    
    public var color: Color {
        Color(hex: colorHex)
    }
    
    public static let defaultPinboards: [Pinboard] = [
        Pinboard(name: "代码片段", colorHex: "#8B5CF6", iconName: "curlybraces", order: 0),
        Pinboard(name: "常用链接", colorHex: "#10B981", iconName: "link", order: 1),
        Pinboard(name: "设计颜色", colorHex: "#EC4899", iconName: "paintpalette.fill", order: 2),
        Pinboard(name: "日常备忘", colorHex: "#F59E0B", iconName: "note.text", order: 3)
    ]
}

// Color Hex Extension
public extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 128, 128, 128)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        let r = Float(components.redComponent)
        let g = Float(components.greenComponent)
        let b = Float(components.blueComponent)
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}
