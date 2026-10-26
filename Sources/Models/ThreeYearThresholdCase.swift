import Foundation
import SwiftData

/// Einordnung einer einzelnen Erhaltungsaufwand-Position hinsichtlich der 15-%-Grenze
/// (§6 Abs. 1 Nr. 1a EStG). Neu erkannte Positionen starten immer als `unclassified` – die App
/// entscheidet nie anhand der Rechnungsbezeichnung allein, ob eine Position einzubeziehen ist.
enum ThresholdExpenseStatus: String, Codable, CaseIterable, Identifiable {
    /// Sicher zu berücksichtigende Position.
    case certain
    /// Nach fachlicher Prüfung als einzubeziehen eingestuft.
    case includedAfterReview
    /// Nach dokumentierter Rechtsgrundlage ausgeschlossen (siehe `reason`).
    case excluded
    /// Noch nicht klassifiziert – Standardwert für neu erkannte Positionen.
    case unclassified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .certain: return "Sicher zu berücksichtigen"
        case .includedAfterReview: return "Nach Prüfung einzubeziehen"
        case .excluded: return "Ausgeschlossen"
        case .unclassified: return "Nicht klassifiziert"
        }
    }

    /// Ob diese Position in die Summe der berücksichtigten Aufwendungen einfließt.
    var countsTowardThreshold: Bool {
        self == .certain || self == .includedAfterReview
    }
}

/// Gesamtstatus der 15-%-Prüfung für eine Immobilie.
enum ThresholdCaseStatus: String, Identifiable {
    case belowThreshold         // Unterhalb der Grenze
    case thresholdReached       // Schwelle erreicht – Prüfung erforderlich
    case exceeded               // Überschritten – steuerliche Einordnung erforderlich
    case notConclusivelyCheckable // Nicht abschließend prüfbar (fehlende Netto-Beträge/Klassifizierungen)
    case completed              // Prüfung abgeschlossen (Dreijahreszeitraum vorbei, keine offenen Punkte)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .belowThreshold: return "Unterhalb der Grenze"
        case .thresholdReached: return "Schwelle erreicht – Prüfung erforderlich"
        case .exceeded: return "Überschritten – steuerliche Einordnung erforderlich"
        case .notConclusivelyCheckable: return "Nicht abschließend prüfbar"
        case .completed: return "Prüfung abgeschlossen"
        }
    }
}

/// Die Dreijahresüberwachung der 15-%-Grenze für eine Immobilie: ein Fall pro Immobilie, mit je
/// einer Einordnung (`ThresholdExpenseAssessment`) für jede in den Zeitraum fallende
/// Erhaltungsaufwand-Position. Status und Begründung bleiben als Hinweise erhalten, auch wenn der
/// Dreijahreszeitraum längst abgelaufen ist – die App löscht die Historie nicht.
@Model
final class ThreeYearThresholdCase {
    var periodStart: Date = Date.now
    var periodEnd: Date = Date.now
    var notes: String = ""
    var createdAt: Date = Date.now
    /// Manuell gesetzt, wenn keine offenen Punkte mehr bestehen – unterscheidet „abgelaufen, aber
    /// noch ungeprüft" von „abgeschlossen geprüft".
    var manuallyClosed: Bool = false

    var property: Property?

    @Relationship(deleteRule: .cascade, inverse: \ThresholdExpenseAssessment.thresholdCase)
    var assessments: [ThresholdExpenseAssessment]? = []

    init(periodStart: Date = .now, periodEnd: Date = .now) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.createdAt = .now
    }

    /// Alle Erhaltungsaufwand-Positionen der Immobilie, deren maßgebliches Datum in den
    /// Dreijahreszeitraum fällt – die Kandidatenliste für die 15-%-Prüfung. Sonstige
    /// Werbungskosten, GWG und bereits als Herstellungskosten erfasste Positionen sind bewusst
    /// ausgeschlossen (siehe Auftrag). Maßgeblich ist `completionDate` (Fertigstellung/
    /// Leistungszeitraum), falls erfasst, sonst `date` (Rechnungsdatum) als Fallback – weder
    /// Rechnungs- noch Zahlungsdatum gelten ungeprüft als alleinige Grundlage.
    var candidateExpenses: [Expense] {
        guard let property else { return [] }
        let own = property.expenses ?? []
        let unitOnes = (property.units ?? []).flatMap { $0.expenses ?? [] }
        var seen = Set<PersistentIdentifier>()
        return (own + unitOnes)
            .filter { seen.insert($0.persistentModelID).inserted }
            .filter { $0.taxTreatment == .maintenanceExpense }
            .filter { let d = $0.completionDate ?? $0.date; return d >= periodStart && d <= periodEnd }
            .sorted { ($0.completionDate ?? $0.date) < ($1.completionDate ?? $1.date) }
    }

    /// Stellt sicher, dass für jede Kandidaten-Position eine Einordnung existiert (Standard:
    /// `unclassified`), ohne vorhandene Einordnungen zu verändern. Muss vor dem Lesen von
    /// `assessments` in der UI aufgerufen werden (z.B. in `.onAppear`), damit neu hinzugekommene
    /// Positionen sichtbar werden.
    func ensureAssessments(context: ModelContext) {
        let existing = Set((assessments ?? []).compactMap { $0.expense?.persistentModelID })
        for expense in candidateExpenses where !existing.contains(expense.persistentModelID) {
            let assessment = ThresholdExpenseAssessment()
            assessment.expense = expense
            assessment.thresholdCase = self
            context.insert(assessment)
        }
    }

    func assessment(for expense: Expense) -> ThresholdExpenseAssessment? {
        (assessments ?? []).first { $0.expense?.persistentModelID == expense.persistentModelID }
    }

    /// Gebäudebezogene Anschaffungskosten ohne Grund und Boden – Basis der 15-%-Grenze.
    var basisAmount: Double {
        property?.buildingValue ?? 0
    }

    var thresholdAmount: Double {
        basisAmount * 0.15
    }

    /// Positionen ohne hinterlegten Umsatzsteuersatz – ihr Netto-Betrag ist nicht ermittelbar.
    var missingNetAmountExpenses: [Expense] {
        candidateExpenses.filter { $0.netAmount == nil }
    }

    /// Noch nicht klassifizierte Positionen (weder einbezogen noch ausgeschlossen).
    var unclassifiedCount: Int {
        candidateExpenses.filter { assessment(for: $0)?.status ?? .unclassified == .unclassified }.count
    }

    /// Summe der Netto-Beträge aller einbezogenen Positionen (sicher + nach Prüfung). Positionen
    /// ohne ermittelbaren Netto-Betrag fließen mit 0 ein und erscheinen stattdessen in
    /// `missingNetAmountExpenses` – die Summe ist in dem Fall als vorläufig zu kennzeichnen.
    var includedNetTotal: Double {
        candidateExpenses.reduce(0) { sum, expense in
            guard let assessment = assessment(for: expense), assessment.status.countsTowardThreshold else { return sum }
            return sum + (expense.netAmount ?? 0)
        }
    }

    var utilizationPercent: Double? {
        guard thresholdAmount > 0 else { return nil }
        return (includedNetTotal / thresholdAmount) * 100
    }

    var remainingToThreshold: Double? {
        guard thresholdAmount > 0 else { return nil }
        return thresholdAmount - includedNetTotal
    }

    /// Gesamtstatus der Prüfung, siehe `ThresholdCaseStatus`.
    var status: ThresholdCaseStatus {
        guard basisAmount > 0 else { return .notConclusivelyCheckable }
        if unclassifiedCount > 0 || !missingNetAmountExpenses.isEmpty {
            if manuallyClosed { return .completed }
            return .notConclusivelyCheckable
        }
        if manuallyClosed { return .completed }
        let percent = utilizationPercent ?? 0
        if percent >= 100 { return .exceeded }
        if percent >= 85 { return .thresholdReached }
        return .belowThreshold
    }

    /// Ob der Dreijahreszeitraum bereits abgelaufen ist (heutiges Datum nach `periodEnd`).
    var isPeriodOver: Bool {
        Date.now > periodEnd
    }

    /// Summe der Netto-Beträge noch ungeklärter Positionen (weder einbezogen noch ausgeschlossen) –
    /// der mögliche zusätzliche Betrag, falls diese Positionen später als einzubeziehen eingestuft
    /// werden. Getrennt von `includedNetTotal` ausgewiesen, damit die Darstellung nicht fälschlich
    /// Sicherheit über ein Ergebnis vermittelt, das noch von offenen Positionen abhängt.
    var possibleAdditionalAmount: Double {
        candidateExpenses
            .filter { (assessment(for: $0)?.status ?? .unclassified) == .unclassified }
            .reduce(0) { $0 + ($1.netAmount ?? 0) }
    }

    /// Alle Aktivierungs-Entscheidungen (siehe `CapitalizationDecision`), die aus dieser Prüfung
    /// hervorgegangen sind, chronologisch – Grundlage für die „Überleitung zur AfA" im Report.
    var capitalizationDecisions: [CapitalizationDecision] {
        (property?.capitalizationDecisions ?? [])
            .filter { $0.thresholdCase?.persistentModelID == persistentModelID }
            .sorted { $0.decidedAt < $1.decidedAt }
    }
}

/// Die Einordnung einer einzelnen `Expense`-Position im Rahmen einer `ThreeYearThresholdCase` –
/// referenziert die bestehende Ausgabe, kopiert sie nicht.
@Model
final class ThresholdExpenseAssessment {
    var statusRaw: String = ThresholdExpenseStatus.unclassified.rawValue
    /// Begründung, Pflichtangabe bei Status `excluded` (dokumentierte Rechtsgrundlage).
    var reason: String = ""
    var updatedAt: Date = Date.now

    var expense: Expense?
    var thresholdCase: ThreeYearThresholdCase?

    init() {
        self.updatedAt = .now
    }

    var status: ThresholdExpenseStatus {
        get { ThresholdExpenseStatus(rawValue: statusRaw) ?? .unclassified }
        set {
            statusRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}
