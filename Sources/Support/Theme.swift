import SwiftUI

extension Color {
    /// Eine Farbe, die zwischen hellem und dunklem Erscheinungsbild unterscheidet – für Töne, die
    /// sich nicht einfach über `.primary`/`.secondary` abbilden lassen (z.B. die zurückhaltenden
    /// Statusfarben in `Theme`).
    init(light: Color, dark: Color) {
        #if os(iOS)
        self.init(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif os(macOS)
        self.init(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #endif
    }
}

/// Zentrale Gestaltungs-Tokens für eine ruhige, einheitliche Business-Optik – an einer Stelle
/// definiert, damit jedes Modul dieselben Farben, Abstände und Radien verwendet, statt sie lokal
/// neu zu erfinden. Die Akzentfarbe selbst kommt aus `AccentColor` im Asset-Katalog (dunkelblau),
/// Systemsteuerelemente übernehmen sie automatisch.
enum Theme {
    // MARK: - Statusfarben (zurückhaltend statt satter Systemfarben)

    static let statusGood = Color(light: Color(red: 0.18, green: 0.49, blue: 0.36), dark: Color(red: 0.30, green: 0.69, blue: 0.51))
    static let statusWarning = Color(light: Color(red: 0.72, green: 0.52, blue: 0.11), dark: Color(red: 0.88, green: 0.65, blue: 0.26))
    static let statusCritical = Color(light: Color(red: 0.69, green: 0.25, blue: 0.24), dark: Color(red: 0.88, green: 0.48, blue: 0.47))

    /// Generischer Ton für Statusanzeigen (Badges, Fortschrittsbalken, Kennzahlen-Vorzeichen) –
    /// jedes modul-eigene Status-Enum (`TaxChecklistStatus`, `ThresholdCaseStatus`, …) bildet sich
    /// darauf ab, damit dieselbe Bedeutung app-weit immer dieselbe Farbe/Ikone bekommt.
    enum StatusTone {
        case good, warning, critical, neutral

        var color: Color {
            switch self {
            case .good: return Theme.statusGood
            case .warning: return Theme.statusWarning
            case .critical: return Theme.statusCritical
            case .neutral: return .secondary
            }
        }

        var systemImage: String {
            switch self {
            case .good: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .critical: return "xmark.octagon.fill"
            case .neutral: return "circle"
            }
        }
    }

    // MARK: - Karten

    static let cardBackground = Color(light: Color(red: 0.96, green: 0.96, blue: 0.97), dark: Color(red: 0.16, green: 0.16, blue: 0.18))
    static let cardBorder = Color(light: Color(red: 0.88, green: 0.88, blue: 0.90), dark: Color(red: 0.26, green: 0.26, blue: 0.29))
    static let cardCornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 14

    // MARK: - Abstände

    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 14
    static let spacingL: CGFloat = 20
    static let spacingXL: CGFloat = 32

    static let sectionSpacing: CGFloat = 20
    static let rowSpacing: CGFloat = 10

    // MARK: - Typografie

    /// Für die große Ergebniskennzahl einer Kachel (z.B. das steuerliche Jahresergebnis).
    static let heroValueFont: Font = .system(size: 30, weight: .bold, design: .rounded)
    /// Für den Wert einer Kennzahlenkarte (z.B. „12.400 €").
    static let metricValueFont: Font = .title3.weight(.semibold)
    /// Für die Bezeichnung unter/über dem Wert.
    static let metricLabelFont: Font = .caption
    static let sectionTitleFont: Font = .headline
    static let pageTitleFont: Font = .largeTitle.weight(.bold)

    @ViewBuilder
    static func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(cardPadding)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: cardCornerRadius))
    }

    /// Karte mit Rahmen statt Füllung – für Karten, die bereits auf einer gefüllten Karte oder
    /// einem Listenhintergrund liegen, damit sich Flächen nicht gegenseitig erschlagen.
    @ViewBuilder
    static func outlinedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(cardPadding)
            .background(RoundedRectangle(cornerRadius: cardCornerRadius).stroke(cardBorder, lineWidth: 1))
    }
}
