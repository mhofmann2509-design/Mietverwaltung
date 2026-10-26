import SwiftUI
import Combine

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

/// Die beiden wählbaren App-weiten Erscheinungsbilder (siehe Design-Vorschläge). `colorScheme`
/// wird app-weit über `.preferredColorScheme(...)` erzwungen – dadurch übernehmen auch native
/// `List`/`Form`-Zeilen, Trennlinien und Systemtexte automatisch den passenden Ton, ohne dass jede
/// einzelne Ansicht manuell angepasst werden muss. `Theme` selbst liefert nur noch die Akzent-,
/// Flächen- und Schrift-Tokens on top, über den bestehenden `Color(light:dark:)`-Mechanismus.
enum AppearanceStyle: String, CaseIterable, Identifiable {
    case dashboardPro
    case warmPersonal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboardPro: return "Dashboard Pro"
        case .warmPersonal: return "Warm & Persönlich"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboardPro: return "Dunkel, datendicht – für den Überblick über mehrere Objekte."
        case .warmPersonal: return "Warm, freundlich – für den privaten Einzelvermieter."
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dashboardPro: return .dark
        case .warmPersonal: return .light
        }
    }

    /// Feste Vorschau-Akzentfarbe für die Auswahl in den Einstellungen – unabhängig vom aktuell
    /// aktiven Theme, damit beide Optionen dort gleichzeitig richtig aussehen.
    var previewAccent: Color {
        switch self {
        case .dashboardPro: return Color(red: 0.204, green: 0.820, blue: 0.722)
        case .warmPersonal: return Color(red: 0.784, green: 0.443, blue: 0.294)
        }
    }

    var previewBackground: Color {
        switch self {
        case .dashboardPro: return Color(red: 0.059, green: 0.071, blue: 0.094)
        case .warmPersonal: return Color(red: 0.984, green: 0.957, blue: 0.918)
        }
    }
}

/// Hält die aktuell gewählte Darstellung persistent (UserDefaults) und als `@Published`, damit
/// Ansichten, die sie beobachten, bei einer Änderung neu zeichnen. Singleton, weil `Theme` als
/// statischer Namensraum app-weit synchron denselben Stand lesen muss – `ContentView` beobachtet
/// `AppearanceStore.shared` zusätzlich aktiv, um bei einem Wechsel per `.id(...)` einen kompletten
/// Neuaufbau zu erzwingen (sonst würden bereits gezeichnete statische `Theme.*`-Werte nicht neu
/// ausgewertet).
@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    @Published var style: AppearanceStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Self.key) }
    }

    private static let key = "appearanceStyle"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.key), let saved = AppearanceStyle(rawValue: raw) {
            style = saved
        } else {
            style = .dashboardPro
        }
    }
}

/// Zentrale Gestaltungs-Tokens – an einer Stelle definiert, damit jedes Modul dieselben Farben,
/// Abstände und Radien verwendet, statt sie lokal neu zu erfinden. Die Farb- und Schrift-Tokens
/// sind jetzt von `AppearanceStore.shared.style` abhängig (siehe `AppearanceStyle`): „light“ im
/// zugrunde liegenden `Color(light:dark:)` steht für „Warm & Persönlich“, „dark“ für „Dashboard
/// Pro“ – über `.preferredColorScheme` an der App-Wurzel erzwungen.
@MainActor
enum Theme {
    private static var style: AppearanceStyle { AppearanceStore.shared.style }

    // MARK: - Statusfarben (zurückhaltend statt satter Systemfarben)

    static let statusGood = Color(light: Color(red: 0.431, green: 0.561, blue: 0.443), dark: Color(red: 0.204, green: 0.820, blue: 0.722))
    static let statusWarning = Color(light: Color(red: 0.784, green: 0.443, blue: 0.294), dark: Color(red: 0.949, green: 0.694, blue: 0.333))
    static let statusCritical = Color(light: Color(red: 0.737, green: 0.255, blue: 0.188), dark: Color(red: 0.898, green: 0.408, blue: 0.345))

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

    // MARK: - Akzent- und Flächenfarben

    /// Haupt-Akzentfarbe (Buttons, Links, Tab-Auswahl, Toggle) – wird app-weit per `.tint(...)` an
    /// der Wurzel gesetzt, sodass Systemsteuerelemente sie automatisch übernehmen.
    static let accent = Color(light: Color(red: 0.784, green: 0.443, blue: 0.294), dark: Color(red: 0.204, green: 0.820, blue: 0.722))

    /// Hintergrund der Seite selbst, hinter Karten/Listen-Inhalten – ersetzt den System-Standard
    /// (`.scrollContentBackground(.hidden)` + `.background(Theme.pageBackground)` an jeder
    /// `List`/`ScrollView`-Wurzel).
    static let pageBackground = Color(light: Color(red: 0.984, green: 0.957, blue: 0.918), dark: Color(red: 0.059, green: 0.071, blue: 0.094))

    static let cardBackground = Color(light: Color(red: 1.0, green: 0.988, blue: 0.965), dark: Color(red: 0.090, green: 0.106, blue: 0.137))
    static let cardBorder = Color(light: Color(red: 0.941, green: 0.886, blue: 0.800), dark: Color(red: 0.149, green: 0.173, blue: 0.220))
    static var cardCornerRadius: CGFloat { style == .warmPersonal ? 20 : 14 }
    static let cardPadding: CGFloat = 16

    // MARK: - Abstände

    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 14
    static let spacingL: CGFloat = 20
    static let spacingXL: CGFloat = 32

    static let sectionSpacing: CGFloat = 20
    static let rowSpacing: CGFloat = 10

    // MARK: - Typografie

    /// Design-Variante für Fließtext-Zahlen: Monospace unterstreicht bei „Dashboard Pro“ den
    /// datendichten, technischen Charakter; „Warm & Persönlich“ bleibt beim freundlicheren
    /// abgerundeten Schnitt.
    private static var numericDesign: Font.Design { style == .dashboardPro ? .monospaced : .rounded }

    /// Für die große Ergebniskennzahl einer Kachel (z.B. das steuerliche Jahresergebnis).
    static var heroValueFont: Font { .system(size: 30, weight: .bold, design: numericDesign) }
    /// Für den Wert einer Kennzahlenkarte (z.B. „12.400 €").
    static var metricValueFont: Font { .title3.weight(.semibold).monospacedDigit() }
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

/// Gemeinsamer Modifier für jede `List`/`ScrollView`-Wurzel: blendet den System-Listenhintergrund
/// aus und setzt stattdessen `Theme.pageBackground`, damit beide Darstellungen (dunkles Navy /
/// warmes Creme) konsistent bis an den Bildschirmrand durchgezogen werden.
struct ThemedScrollBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.pageBackground)
    }
}

extension View {
    func themedScrollBackground() -> some View {
        modifier(ThemedScrollBackground())
    }
}
