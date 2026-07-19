import SwiftUI

extension Color {
    /// Creates a color from a `#RRGGBB` (or `RRGGBB`) hex string. Falls back to gray.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red, green, blue: Double
        if cleaned.count == 6 {
            red = Double((value >> 16) & 0xFF) / 255.0
            green = Double((value >> 8) & 0xFF) / 255.0
            blue = Double(value & 0xFF) / 255.0
        } else {
            red = 0.5; green = 0.5; blue = 0.5
        }
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }
}
