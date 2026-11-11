import Foundation
import SwiftData

/// Dokumentiert die bewusste, manuelle Entscheidung, eine oder mehrere Erhaltungsaufwand-Positionen
/// nachträglich als Herstellungskosten zu behandeln (typischerweise nach Überschreiten der
/// 15-%-Grenze, siehe `ThreeYearThresholdCase`) – mit Datum, Begründung, Verweis auf die
/// auslösenden Ausgaben und das daraus entstandene Wirtschaftsgut. Dies ist die einzige Brücke
/// zwischen der 15-%-Prüfung und der AfA-Berechnung: beide Module bleiben ansonsten getrennt, es
/// gibt keine automatische/stillschweigende Übernahme – die Entscheidung wird immer explizit durch
/// eine Nutzeraktion ausgelöst (siehe `ThresholdCaseDetailView`).
///
/// Die eigentliche AfA-Wirkung entsteht dabei nicht durch eine Änderung von
/// `Property.buildingValue` (das bleibt unverändert, siehe `Property.swift`), sondern dadurch,
/// dass `resultingAsset` ein `DepreciableAsset` der Kategorie `.improvement` ist – diese Kategorie
/// wird bereits heute mit dem Gebäude-AfA-Satz abgeschrieben und fließt über
/// `Property.assetDepreciation(forYear:)` in `Property.totalAfa(forYear:)` ein (siehe
/// `DepreciableAsset.usesBuildingAfaRate`). Jahre vor `effectiveYear` bleiben dadurch unberührt.
@Model
final class CapitalizationDecision {
    var decidedAt: Date = Date.now
    /// Steuerjahr, ab dem die Maßnahme in der AfA berücksichtigt wird (entspricht dem Jahr von
    /// `resultingAsset.placedInServiceDate`).
    var effectiveYear: Int = Calendar.current.component(.year, from: .now)
    var reason: String = ""

    var property: Property?
    /// Die 15-%-Prüfung, aus der diese Entscheidung hervorging, falls vorhanden – eine Aktivierung
    /// kann grundsätzlich auch ohne laufende Dreijahresüberwachung erfolgen.
    var thresholdCase: ThreeYearThresholdCase?
    /// Das neu angelegte Wirtschaftsgut, das die zusätzliche AfA trägt.
    var resultingAsset: DepreciableAsset?

    @Relationship(inverse: \Expense.capitalizationDecision)
    var sourceExpenses: [Expense]? = []

    init(decidedAt: Date = .now, effectiveYear: Int? = nil, reason: String = "") {
        self.decidedAt = decidedAt
        self.effectiveYear = effectiveYear ?? Calendar.current.component(.year, from: decidedAt)
        self.reason = reason
    }

    /// Summe der Bruttobeträge aller zugrunde liegenden Ausgaben – wie `DepreciableAsset.cost`
    /// sonst auch (siehe dortigen Kommentar), bewusst brutto, da private Vermieter die
    /// Vorsteuer in aller Regel nicht geltend machen können.
    var totalAmount: Double {
        (sourceExpenses ?? []).reduce(0) { $0 + $1.amount }
    }

    /// Legt aus den übergebenen, bereits fachlich geprüften Ausgaben eine neue
    /// `CapitalizationDecision` samt zugehörigem `DepreciableAsset(.improvement)` an und markiert
    /// jede Quell-Ausgabe als `.capitalized` (damit sie aus künftigen 15-%-Kandidatenlisten
    /// ausscheidet und nicht doppelt als Werbungskosten abgezogen wird). Reine Nutzeraktion – wird
    /// nie automatisch aufgerufen. Jede Ausgabe darf nur einmal verknüpft werden; bereits
    /// verknüpfte Ausgaben werden ignoriert, um einen doppelten Ansatz auszuschließen.
    @discardableResult
    static func create(
        from expenses: [Expense],
        property: Property,
        thresholdCase: ThreeYearThresholdCase?,
        reason: String,
        context: ModelContext
    ) -> CapitalizationDecision? {
        let unlinked = expenses.filter { $0.capitalizationDecision == nil }
        guard !unlinked.isEmpty else { return nil }

        let effectiveDate = unlinked.map { $0.completionDate ?? $0.date }.max() ?? .now
        let effectiveYear = Calendar.current.component(.year, from: effectiveDate)
        let totalCost = unlinked.reduce(0) { $0 + $1.amount }
        let assetName = reason.isEmpty
            ? "Aktivierte Erhaltungsaufwendungen (\(unlinked.count) Position(en), \(String(effectiveYear)))"
            : reason

        let asset = DepreciableAsset(
            name: assetName,
            category: .improvement,
            cost: totalCost,
            placedInServiceDate: effectiveDate
        )
        asset.property = property
        context.insert(asset)

        let decision = CapitalizationDecision(effectiveYear: effectiveYear, reason: reason)
        decision.property = property
        decision.thresholdCase = thresholdCase
        decision.resultingAsset = asset
        context.insert(decision)

        for expense in unlinked {
            expense.taxTreatment = .capitalized
            expense.capitalizationDecision = decision
        }
        decision.sourceExpenses = unlinked

        return decision
    }

    /// Nimmt eine Aktivierung zurück, bevor ihr Wirtschaftsgut gelöscht wird: Die Quell-Ausgaben
    /// werden wieder als Erhaltungsaufwand geführt – sonst blieben sie als `.capitalized` markiert
    /// und würden weder als Werbungskosten abgezogen noch über die AfA berücksichtigt.
    static func revert(_ decision: CapitalizationDecision, context: ModelContext) {
        for expense in decision.sourceExpenses ?? [] {
            expense.taxTreatment = .maintenanceExpense
            expense.capitalizationDecision = nil
        }
        context.delete(decision)
    }
}
