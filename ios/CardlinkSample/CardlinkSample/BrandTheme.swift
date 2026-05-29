import SwiftUI
import UIKit

/// Predefined brand themes matching real pharmacy apps.
/// Mirror of the Android demo's BrandTheme enum.
enum BrandTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case scoop = "SCOOP"
    case apoCom = "apo.com"
    case docmorris = "DocMorris"
    case mea = "mea"
    case redcare = "Redcare"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// Primary/accent color shown in the theme picker chip.
    var previewColor: Color {
        switch self {
        case .system: return Color(red: 0.404, green: 0.314, blue: 0.643) // 6750A4
        case .scoop: return Color(red: 0.0, green: 0.345, blue: 0.580)    // 005894
        case .apoCom: return Color(red: 0.102, green: 0.451, blue: 0.910) // 1A73E8
        case .docmorris: return Color(red: 0.102, green: 0.349, blue: 0.314) // 1A5950
        case .mea: return Color(red: 0.020, green: 0.522, blue: 0.314)    // 058550
        case .redcare: return Color(red: 0.929, green: 0.016, blue: 0.204) // ED0434
        }
    }

    /// Accent/primary color applied via `.tint(...)` at the app root.
    var tint: Color { previewColor }

    /// UIColor equivalent for passing into UIKit components (e.g. PoppUiContext).
    var uiColor: UIColor {
        switch self {
        case .system: return UIColor(red: 0.404, green: 0.314, blue: 0.643, alpha: 1)
        case .scoop: return UIColor(red: 0.0, green: 0.345, blue: 0.580, alpha: 1)
        case .apoCom: return UIColor(red: 0.102, green: 0.451, blue: 0.910, alpha: 1)
        case .docmorris: return UIColor(red: 0.102, green: 0.349, blue: 0.314, alpha: 1)
        case .mea: return UIColor(red: 0.020, green: 0.522, blue: 0.314, alpha: 1)
        case .redcare: return UIColor(red: 0.929, green: 0.016, blue: 0.204, alpha: 1)
        }
    }

    /// Base PostScript font name used by this theme, or nil for system.
    var fontBase: String? {
        switch self {
        case .system: return nil
        case .scoop: return "Raleway"
        case .apoCom: return "Roboto-Medium"   // apo.com uses Roboto Medium as its base weight
        case .docmorris: return "Poppins"
        case .mea: return "OpenSans"
        case .redcare: return "RedcareAccessible"
        }
    }

    /// PostScript font name for a given weight.
    func fontName(weight: Font.Weight) -> String? {
        guard let base = fontBase else { return nil }
        // apo.com uses Roboto-Medium for every weight
        if self == .apoCom { return base }
        let suffix: String
        switch weight {
        case .bold, .heavy, .black: suffix = "-Bold"
        case .semibold: suffix = "-SemiBold"
        case .medium: suffix = "-Medium"
        default: suffix = "-Regular"
        }
        // Redcare only has Regular/Medium/Bold — SemiBold falls back to Medium
        if self == .redcare && suffix == "-SemiBold" { return "\(base)-Medium" }
        return "\(base)\(suffix)"
    }
}

/// Applies the brand font to all text in the hierarchy.
/// Uses scaled metrics so Dynamic Type still works.
struct BrandFontModifier: ViewModifier {
    let theme: BrandTheme

    func body(content: Content) -> some View {
        if let regular = theme.fontName(weight: .regular) {
            content
                .font(.custom(regular, size: UIFont.preferredFont(forTextStyle: .body).pointSize, relativeTo: .body))
        } else {
            content
        }
    }
}

extension View {
    func brandFont(_ theme: BrandTheme) -> some View {
        modifier(BrandFontModifier(theme: theme))
    }
}

/// Observable holder for the active brand theme. Persists to UserDefaults.
@MainActor
final class BrandThemeStore: ObservableObject {
    @Published var current: BrandTheme {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: "brandTheme")
        }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: "brandTheme") ?? BrandTheme.system.rawValue
        self.current = BrandTheme(rawValue: stored) ?? .system
    }
}
