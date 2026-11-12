import Foundation
import SwiftData

/// Kategorie eines abschreibbaren Wirtschaftsguts (für die AfA).
/// - Note: `rawValue` ist ein stabiler, persistierter Schlüssel, siehe `label`.
enum AssetCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case furniture
    case improvement
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .furniture: return "Möblierung/Einrichtung"
        case .improvement: return "Herstellungskosten (Modernisierung/Umbau)"
        case .other: return "Sonstiges Wirtschaftsgut"
        }
    }

    var systemImage: String {
        switch self {
        case .furniture: return "sofa"
        case .improvement: return "hammer"
        case .other: return "cube.box"
        }
    }

    /// Übliche Nutzungsdauer laut AfA-Tabelle, als Startwert für neue Einträge
    /// (Einbauküche/Möbel: 10 Jahre; Modernisierung: wie Gebäude-AfA; Sonstiges: 10 Jahre).
    var defaultUsefulLifeYears: Int {
        switch self {
        case .furniture: return 10
        case .improvement: return 50
        case .other: return 10
        }
    }
}

/// Ein einzelnes abschreibbares Wirtschaftsgut (Möbel, Modernisierung, Sonstiges) –
/// unabhängig von der automatisch aus Kaufpreis/Baujahr berechneten Gebäude-AfA (siehe `Property`).
@Model
final class DepreciableAsset {
    var name: String = ""
    var categoryRaw: String = AssetCategory.other.rawValue
    var cost: Double = 0                    // Anschaffungs-/Herstellungskosten (Neupreis bzw. tatsächlicher Kaufpreis)
    var usefulLifeYears: Int = 10           // Nutzungsdauer in Jahren
    var placedInServiceDate: Date = Date.now // Beginn der Abschreibung
    var notes: String = ""

    /// Gebraucht erworbene Wirtschaftsgüter werden mit ihrem geschätzten Zeitwert bei Anschaffung
    /// abgeschrieben, nicht mit einem (ggf. unbekannten) ursprünglichen Neupreis.
    var isUsed: Bool = false
    var estimatedValueAtAcquisition: Double = 0 // Zeitwert bei Anschaffung (nur relevant, wenn isUsed)

    /// Ob dieses Wirtschaftsgut zusammen mit der Einheit vermietet wird (Möblierungszuschlag) –
    /// unabhängig davon, ob es überhaupt einer Einheit zugeordnet ist.
    var isCoRented: Bool = false

    /// Umsatzsteuersatz der Anschaffung, nur für die GWG-Prüfung (Grenze netto). `nil` = nicht
    /// erfasst; dann werden 19 % angenommen, bei gebraucht erworbenen Gütern 0 % (privater Kauf).
    var vatRatePercent: Double?

    var property: Property?
    var unit: Unit?

    @Relationship(deleteRule: .cascade, inverse: \Document.depreciableAsset)
    var documents: [Document]? = []

    /// Aktivierungsentscheidung, aus der dieses Wirtschaftsgut entstanden ist (siehe
    /// `CapitalizationDecision.revert`, bevor es gelöscht wird).
    @Relationship(deleteRule: .nullify, inverse: \CapitalizationDecision.resultingAsset)
    var capitalizationDecisions: [CapitalizationDecision]? = []

    /// Löscht das Wirtschaftsgut und nimmt eine zugehörige Aktivierungsentscheidung zurück.
    static func delete(_ asset: DepreciableAsset, context: ModelContext) {
        for decision in asset.capitalizationDecisions ?? [] {
            CapitalizationDecision.revert(decision, context: context)
        }
        context.delete(asset)
    }

    /// Hinweistext für die Lösch-Bestätigung.
    var deletionWarning: String {
        let expenseCount = (capitalizationDecisions ?? []).reduce(0) { $0 + ($1.sourceExpenses?.count ?? 0) }
        guard expenseCount > 0 else { return "Dieser Schritt kann nicht rückgängig gemacht werden." }
        return "Dieses Wirtschaftsgut stammt aus der Aktivierung von \(expenseCount) Ausgabe(n). Beim Löschen wird die Aktivierung zurückgenommen – die Ausgaben werden wieder als Erhaltungsaufwand geführt."
    }

    init(name: String = "", category: AssetCategory = .other, cost: Double = 0, usefulLifeYears: Int = 10, placedInServiceDate: Date = .now, notes: String = "", isUsed: Bool = false, estimatedValueAtAcquisition: Double = 0, isCoRented: Bool = false) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.cost = cost
        self.usefulLifeYears = usefulLifeYears
        self.placedInServiceDate = placedInServiceDate
        self.notes = notes
        self.isUsed = isUsed
        self.estimatedValueAtAcquisition = estimatedValueAtAcquisition
        self.isCoRented = isCoRented
    }

    var category: AssetCategory {
        get { AssetCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// Die für die AfA (und die GWG-Prüfung) maßgebliche Bemessungsgrundlage: bei gebraucht
    /// erworbenen Wirtschaftsgütern der angesetzte Zeitwert bei Anschaffung, sonst die
    /// tatsächlichen Anschaffungs-/Herstellungskosten.
    var depreciationBasis: Double {
        isUsed && estimatedValueAtAcquisition > 0 ? estimatedValueAtAcquisition : cost
    }

    /// Grenze für geringwertige Wirtschaftsgüter (GWG) nach §6 Abs. 2 EStG: bewegliche,
    /// selbständig nutzbare Wirtschaftsgüter, deren Anschaffungskosten „vermindert um einen darin
    /// enthaltenen Vorsteuerbetrag“ 800 € nicht übersteigen, dürfen im Anschaffungsjahr sofort
    /// abgezogen werden – geprüft wird also netto, abgezogen wird (ohne Vorsteuerabzug) brutto.
    /// Herstellungskosten am Gebäude (Kategorie `.improvement`) fallen nicht unter die GWG-Regelung.
    static let gwgThreshold: Double = 800

    /// Für die GWG-Grenze maßgeblicher Nettobetrag, siehe `vatRatePercent`.
    var gwgNetBasis: Double {
        let rate = vatRatePercent ?? (isUsed ? 0 : 19)
        guard rate > -100 else { return depreciationBasis }
        return depreciationBasis / (1 + rate / 100)
    }

    var isImmediatelyDeductible: Bool {
        category != .improvement && depreciationBasis > 0 && (gwgNetBasis * 100).rounded() <= Self.gwgThreshold * 100
    }

    /// Kalenderjahr des Sofortabzugs (GWG), sofern zutreffend.
    var immediateDeductionYear: Int? {
        guard isImmediatelyDeductible else { return nil }
        return Calendar.current.component(.year, from: placedInServiceDate)
    }

    /// Bei Herstellungskosten (Kategorie `.improvement`) richtet sich die AfA nicht nach einer
    /// frei gewählten Nutzungsdauer, sondern nach dem AfA-Satz des Gebäudes selbst – nachträgliche
    /// Herstellungskosten erhöhen die Bemessungsgrundlage der Gebäude-AfA und werden mit demselben
    /// Satz abgeschrieben (ggf. verkürzt durch ein Restnutzungsdauergutachten, siehe
    /// `Property.afaRatePercentOverride`). Eine eigene Nutzungsdauer ist für diese Kategorie daher
    /// irrelevant.
    var usesBuildingAfaRate: Bool { category == .improvement }

    /// Lineare jährliche Abschreibung (ohne Berücksichtigung des Anschaffungsjahres).
    /// Bei GWG (Sofortabzug) 0, da die gesamten Kosten einmalig im Anschaffungsjahr greifen
    /// (siehe `depreciation(forYear:)`).
    var annualDepreciation: Double {
        guard !isImmediatelyDeductible else { return 0 }
        if usesBuildingAfaRate {
            guard let property else { return 0 }
            return depreciationBasis * property.afaRatePercent / 100
        }
        guard usefulLifeYears > 0 else { return 0 }
        return depreciationBasis / Double(usefulLifeYears)
    }

    /// Abschreibung für ein bestimmtes Kalenderjahr:
    /// - GWG: die vollen Kosten einmalig im Anschaffungsjahr.
    /// - Bewegliche Wirtschaftsgüter: linear, im Anschaffungsjahr monatsgenau (§ 7 Abs. 1 Satz 4
    ///   EStG); der im ersten Jahr nicht abgeschriebene Rest fällt in das Jahr nach Ablauf der
    ///   Nutzungsdauer (6.000 € / 10 Jahre ab Juli 2020: 300 € in 2020 und 2030).
    /// - Herstellungskosten am Gebäude (`usesBuildingAfaRate`): mit dem Gebäude-AfA-Satz; im Jahr
    ///   ihrer Entstehung so, als wären sie zu Jahresbeginn angefallen (R 7.4 Abs. 9 Satz 3 EStR) –
    ///   im Anschaffungsjahr des Gebäudes aber erst ab dessen AfA-Beginn. Endet, sobald die
    ///   Kosten vollständig abgeschrieben sind.
    func depreciation(forYear year: Int) -> Double {
        if isImmediatelyDeductible {
            return year == immediateDeductionYear ? depreciationBasis : 0
        }
        let startYear = Calendar.current.component(.year, from: placedInServiceDate)
        guard year >= startYear else { return 0 }
        if usesBuildingAfaRate {
            let depreciatedBefore = (startYear..<year).reduce(0.0) { $0 + uncappedBuildingRateDepreciation(forYear: $1) }
            return max(0, min(uncappedBuildingRateDepreciation(forYear: year), depreciationBasis - depreciatedBefore))
        }
        guard usefulLifeYears > 0 else { return 0 }
        let startMonth = Calendar.current.component(.month, from: placedInServiceDate)
        let firstMonthIndex = startYear * 12 + startMonth - 1
        let lastMonthIndex = firstMonthIndex + usefulLifeYears * 12 - 1
        let months = min(lastMonthIndex, year * 12 + 11) - max(firstMonthIndex, year * 12) + 1
        return months > 0 ? annualDepreciation * Double(months) / 12 : 0
    }

    private func uncappedBuildingRateDepreciation(forYear year: Int) -> Double {
        let calendar = Calendar.current
        let startYear = calendar.component(.year, from: placedInServiceDate)
        guard year >= startYear else { return 0 }
        if year == startYear, let buildingStart = property?.afaStartDate, calendar.component(.year, from: buildingStart) == startYear {
            return annualDepreciation * Double(13 - calendar.component(.month, from: buildingStart)) / 12
        }
        return annualDepreciation
    }

    /// Kumulierte Abschreibung bis einschließlich des angegebenen Jahres, gedeckelt auf
    /// `depreciationBasis`. Für Wirtschaftsgüter mit fester Nutzungsdauer begrenzt bereits
    /// `depreciation(forYear:)` selbst auf das Laufzeitende; bei Herstellungskosten
    /// (`usesBuildingAfaRate`, ohne eigenes Enddatum – siehe `depreciation(forYear:)`) greift erst
    /// diese Deckelung, analog zu `Property.cumulativeBuildingAfA`.
    func cumulativeDepreciation(uptoYear year: Int) -> Double {
        let startYear = Calendar.current.component(.year, from: placedInServiceDate)
        guard year >= startYear else { return 0 }
        var sum = 0.0
        for y in startYear...year { sum += depreciation(forYear: y) }
        return min(depreciationBasis, sum)
    }

    /// Restbuchwert nach der kumulierten Abschreibung bis einschließlich des angegebenen Jahres.
    func remainingDepreciationBookValue(afterYear year: Int) -> Double {
        max(0, depreciationBasis - cumulativeDepreciation(uptoYear: year))
    }
}
