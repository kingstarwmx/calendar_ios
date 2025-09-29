import UIKit

extension UIColor {
    convenience init?(hexString: String) {
        var formatted = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if formatted.hasPrefix("#") {
            formatted.removeFirst()
        }

        guard formatted.count == 6 || formatted.count == 8,
              let hexValue = UInt32(formatted, radix: 16) else {
            return nil
        }

        let hasAlpha = formatted.count == 8
        let alpha: CGFloat
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        if hasAlpha {
            alpha = CGFloat((hexValue & 0xFF000000) >> 24) / 255.0
            red = CGFloat((hexValue & 0x00FF0000) >> 16) / 255.0
            green = CGFloat((hexValue & 0x0000FF00) >> 8) / 255.0
            blue = CGFloat(hexValue & 0x000000FF) / 255.0
        } else {
            alpha = 1.0
            red = CGFloat((hexValue & 0xFF0000) >> 16) / 255.0
            green = CGFloat((hexValue & 0x00FF00) >> 8) / 255.0
            blue = CGFloat(hexValue & 0x0000FF) / 255.0
        }

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    func toHexString(includeAlpha: Bool = false) -> String {
        guard let components = cgColor.components else {
            return "#000000"
        }

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat

        if components.count >= 3 {
            red = components[0]
            green = components[1]
            blue = components[2]
            alpha = components.count >= 4 ? components[3] : 1.0
        } else {
            // Grayscale color space
            let value = components[0]
            red = value
            green = value
            blue = value
            alpha = components.count >= 2 ? components[1] : 1.0
        }

        if includeAlpha {
            return String(
                format: "#%02lX%02lX%02lX%02lX",
                lroundf(Float(alpha * 255)),
                lroundf(Float(red * 255)),
                lroundf(Float(green * 255)),
                lroundf(Float(blue * 255))
            )
        }

        return String(
            format: "#%02lX%02lX%02lX",
            lroundf(Float(red * 255)),
            lroundf(Float(green * 255)),
            lroundf(Float(blue * 255))
        )
    }
}
