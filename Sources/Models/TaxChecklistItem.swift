import Foundation
import SwiftData

enum TaxChecklistStatus: String, Codable, CaseIterable, Identifiable {
    case open, inProgress, done, notApplicable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: return "Offen"
        case .inProgress: return "In Bearbeitung"
        case .done: return "Erledigt"
        case .notApplicable: return "Nicht zutreffend"
        }
    }

    var systemImage: String {
        switch self {
        case .open: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        case .notApplicable: return "minus.circle"
        }
    }
}

/// In welchem Arbeitsmodus eine Checklisten-Aufgabe anfällt.
enum TaxChecklistMode: String, Codable, CaseIterable, Identifiable {
    /// Einmalige Aufgaben bei der steuerlichen Erstanlage einer Immobilie (Kaufvertrag,
    /// Kaufpreisaufteilung, AfA-Grundlagen, …) – nicht an ein Steuerjahr gebunden.
    case initialSetup
    /// Jährlich wiederkehrende Aufgaben im laufenden Betrieb (Einnahmen vollständig, Belege
    /// zugeordnet, PDF erstellt, …) – an `taxYear` gebunden.
    case ongoing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .initialSetup: return "Erstanlage"
        case .ongoing: return "Laufender Betrieb"
        }
    }
}

/// Ein dauerhaft gespeicherter Checklisten-Eintrag für die steuerliche Vorbereitung einer
/// Immobilie. Der Status wird ausschließlich manuell gesetzt – ein vorhandener Datensatz
/// (z.B. ein erfasster Kaufvertrag) markiert eine Aufgabe nie automatisch als erledigt.
@Model
final class TaxChecklistItem {
    var title: String = ""
    var itemDescription: String = ""
    var statusRaw: String = TaxChecklistStatus.open.rawValue
    var modeRaw: String = TaxChecklistMode.initialSetup.rawValue
    /// `nil` bei Erstanlage-Aufgaben (einmalig je Immobilie); bei laufenden Aufgaben das
    /// betroffene Steuerjahr.
    var taxYear: Int?
    var dueDate: Date?
    var completedAt: Date?
    var comment: String = ""
    var openQuestion: String = ""
    var createdAt: Date = Date.now
    /// Feste Kennung des Vorlagen-Eintrags (siehe `TaxChecklistTemplate`), um bei erneutem Öffnen
    /// zu erkennen, welche Vorlagen für diese Immobilie/dieses Jahr schon angelegt wurden, ohne
    /// Duplikate zu erzeugen.
    var templateKey: String = ""

    var property: Property?
    var linkedDocument: Document?

    init(title: String = "", itemDescription: String = "", mode: TaxChecklistMode = .initialSetup, taxYear: Int? = nil, templateKey: String = "") {
        self.title = title
        self.itemDescription = itemDescription
        self.modeRaw = mode.rawValue
        self.taxYear = taxYear
        self.templateKey = templateKey
        self.createdAt = .now
    }

    var status: TaxChecklistStatus {
        get { TaxChecklistStatus(rawValue: statusRaw) ?? .open }
        set {
            statusRaw = newValue.rawValue
            completedAt = newValue == .done ? (completedAt ?? .now) : nil
        }
    }

    var mode: TaxChecklistMode {
        get { TaxChecklistMode(rawValue: modeRaw) ?? .initialSetup }
        set { modeRaw = newValue.rawValue }
    }
}

/// Die festen Vorlagen-Einträge, mit denen die Checkliste einer Immobilie beim ersten Öffnen
/// vorbelegt wird (siehe Auftrag Abschnitt 8) – bewusst als statische Liste im Code, nicht als
/// eigenes Datenmodell, da sie sich nicht pro Immobilie unterscheiden.
enum TaxChecklistTemplate {
    struct Entry {
        let key: String
        let title: String
        let description: String
        let mode: TaxChecklistMode
    }

    static let initialSetupEntries: [Entry] = [
        Entry(key: "purchaseContract", title: "Kaufvertrag und Anschaffungsdaten vorhanden", description: "Kaufpreis, Kaufdatum und wirtschaftlicher Übergang erfasst.", mode: .initialSetup),
        Entry(key: "purchasePriceSplit", title: "Kaufpreisaufteilung dokumentiert", description: "Aufteilung auf Gebäude und Grund und Boden nachvollziehbar.", mode: .initialSetup),
        Entry(key: "afaBasis", title: "AfA-Bemessungsgrundlage geprüft", description: "Abschreibbarer Gebäudewert plausibilisiert.", mode: .initialSetup),
        Entry(key: "afaMethod", title: "AfA-Methode und Beginn geprüft", description: "Gesetzlicher oder manueller AfA-Satz sowie Beginn der Abschreibung kontrolliert.", mode: .initialSetup),
        Entry(key: "furnitureList", title: "Möbelverzeichnis vollständig", description: "Alle Möbel/Ausstattungsgegenstände mit Anschaffungskosten erfasst.", mode: .initialSetup),
        Entry(key: "renovationInvoices", title: "Renovierungsrechnungen erfasst", description: "Sanierungs-/Modernisierungsrechnungen der ersten drei Jahre erfasst.", mode: .initialSetup),
        Entry(key: "thresholdCheck", title: "15-%-Prüfung abgeschlossen oder begründet offen", description: "Dreijahresüberwachung durchgeführt oder offene Punkte dokumentiert.", mode: .initialSetup),
    ]

    static let ongoingEntries: [Entry] = [
        Entry(key: "debtInterestSeparated", title: "Schuldzinsen von Tilgung getrennt", description: "Zinsen und Tilgung sind nicht vermischt erfasst.", mode: .ongoing),
        Entry(key: "wegStatement", title: "WEG-Abrechnung und Rücklagen geprüft", description: "Hausgeld und Erhaltungsrücklage kontrolliert.", mode: .ongoing),
        Entry(key: "otherExpenses", title: "Sonstige Werbungskosten geprüft", description: "Vollständigkeit der sonstigen Werbungskosten kontrolliert.", mode: .ongoing),
        Entry(key: "incomeComplete", title: "Einnahmen vollständig", description: "Mieteinnahmen des Steuerjahres vollständig erfasst.", mode: .ongoing),
        Entry(key: "documentsLinked", title: "Belege zugeordnet", description: "Alle relevanten Belege sind verknüpft.", mode: .ongoing),
        Entry(key: "yearOverviewPlausible", title: "Steuerjahresübersicht plausibilisiert", description: "Jahresübersicht auf Plausibilität geprüft.", mode: .ongoing),
        Entry(key: "pdfCreated", title: "PDF erstellt und kontrolliert", description: "Gesamtdokument erzeugt und durchgesehen.", mode: .ongoing),
    ]
}
