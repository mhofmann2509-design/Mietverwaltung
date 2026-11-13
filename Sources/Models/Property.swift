import Foundation
import SwiftData

/// Herkunft des maßgeblichen Gebäude-AfA-Satzes – für eine nachvollziehbare Rechtsgrundlage in
/// Steuer-Cockpit und Berichten, siehe `Property.afaRateSource`.
enum AfaRateSource: Equatable {
    case typisiert, appraisal, manual

    var label: String {
        switch self {
        case .typisiert: return "typisiert nach Baujahr"
        case .appraisal: return "aus Restnutzungsdauergutachten"
        case .manual: return "manuell festgelegt"
        }
    }

    var legalBasis: String {
        switch self {
        case .typisiert: return "§ 7 Abs. 4 Satz 1 EStG"
        case .appraisal: return "§ 7 Abs. 4 Satz 2 EStG"
        case .manual: return "manuell, ohne automatische Rechtsgrundlage"
        }
    }
}

@Model
final class Property {
    var name: String = ""
    var street: String = ""
    var zipCode: String = ""
    var city: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now

    // Allgemeine Daten
    var roomCount: Int?                         // Anzahl der Zimmer (gesamt)
    var totalUnitCount: Int?                     // Anzahl der Einheiten insgesamt lt. Teilungserklärung (unabhängig von den erfassten Einheiten)
    /// Eigener Anteil am erfassten Objekt in Prozent bei Miteigentum (z.B. Ehepartner,
    /// Erbengemeinschaft) – Kaufpreis, Mieten und Kosten werden für das ganze Objekt erfasst, die
    /// Anlage V weist zusätzlich den Anteil am Ergebnis aus. Nicht der Miteigentumsanteil (MEA) einer
    /// Eigentumswohnung am Gesamtgebäude: Wer eine ETW allein besitzt, lässt das Feld leer.
    /// `nil`, solange nicht erfasst.
    var ownershipSharePercent: Double?

    // Kauf & Rendite
    var purchasePrice: Double = 0              // Kaufpreis
    var purchaseAncillaryCosts: Double = 0      // Kaufnebenkosten (Grunderwerbsteuer, Notar, Makler, …) – maßgebliche Summe für alle Berechnungen
    /// Optionale Einzelposten der Kaufnebenkosten – rein zur transparenten Darstellung in der
    /// AfA-Herleitung (siehe `TaxReportPDFBuilder`). Verändern `purchaseAncillaryCosts` nicht:
    /// dieses Feld bleibt die für `totalAcquisitionCost`/`apportionedLandValue`/`buildingValue`
    /// maßgebliche Summe, damit bestehende Berechnungen unangetastet bleiben, auch wenn die
    /// Einzelposten hier noch nicht (vollständig) erfasst sind.
    var purchaseTransferTaxCosts: Double = 0    // Grunderwerbsteuer
    /// Ob die Grunderwerbsteuer bereits bezahlt wurde. Der tatsächliche Zahlungstermin ergibt
    /// sich aus dem individuellen Steuerbescheid des Finanzamts (i.d.R. 1 Monat nach dessen
    /// Zugang) und lässt sich nicht verlässlich aus dem Kaufdatum herleiten – daher nur als
    /// Status erfasst, nicht als berechnete Frist, siehe `RemindersEngine`.
    var purchaseTransferTaxPaid: Bool = false
    var purchaseBrokerCosts: Double = 0         // Maklerkosten
    var purchaseNotaryCosts: Double = 0         // Notarkosten
    var purchaseLandRegistryCosts: Double = 0   // Auflassungsvormerkung / Grundbuchkosten
    var purchaseDate: Date?                     // Kaufdatum (Beurkundung lt. Kaufvertrag)
    /// Übergang von Besitz, Nutzen und Lasten – rechtlich maßgebliches Datum sowohl für den Beginn
    /// des Dreijahreszeitraums der 15-%-Grenze (§6 Abs. 1 Nr. 1a EStG) als auch für den Beginn der
    /// Gebäude-AfA (§7 EStG, siehe `afaStartDate`), das vom Beurkundungsdatum abweichen kann.
    /// Bewusst getrennt von `purchaseDate` erfasst: Properties, bei denen nur `purchaseDate`
    /// gepflegt ist, verhalten sich dadurch unverändert wie vor Einführung dieses Felds.
    var economicTransferDate: Date?

    // Steuer / AfA
    var landValue: Double = 0                   // Bodenwert (nicht abschreibbar)
    var constructionYear: Int?                  // Baujahr (bestimmt den gesetzlichen AfA-Satz)
    var afaRatePercentOverride: Double?          // manuell gesetzter AfA-Satz, überschreibt die Automatik

    // Finanzierung (Annuitätendarlehen)
    var loanAmount: Double = 0                  // Darlehenssumme
    var interestRatePercent: Double = 0         // Sollzinssatz p.a.
    var initialRepaymentRatePercent: Double = 0 // anfänglicher Tilgungssatz p.a.
    var loanStartDate: Date?                    // Beginn der Finanzierung

    // Absender (für Anschreiben wie die Nebenkostenabrechnung)
    var landlordName: String = ""               // Name des Vermieters, z.B. für die Unterschrift

    // Bankverbindung (für Nachzahlungen aus der Nebenkostenabrechnung)
    var bankAccountHolder: String = ""
    var iban: String = ""
    var bic: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Unit.property)
    var units: [Unit]? = []

    @Relationship(deleteRule: .cascade, inverse: \Expense.property)
    var expenses: [Expense]? = []

    @Relationship(deleteRule: .cascade, inverse: \Document.property)
    var documents: [Document]? = []

    @Relationship(deleteRule: .cascade, inverse: \DocumentFolder.property)
    var documentFolders: [DocumentFolder]? = []

    @Relationship(deleteRule: .cascade, inverse: \DepreciableAsset.property)
    var depreciableAssets: [DepreciableAsset]? = []

    @Relationship(deleteRule: .cascade, inverse: \UtilityStatement.property)
    var utilityStatements: [UtilityStatement]? = []

    @Relationship(deleteRule: .cascade, inverse: \RemainingUsefulLifeAppraisal.property)
    var remainingUsefulLifeAppraisals: [RemainingUsefulLifeAppraisal]? = []

    @Relationship(deleteRule: .cascade, inverse: \WirtschaftsplanStatement.property)
    var wirtschaftsplaene: [WirtschaftsplanStatement]? = []

    @Relationship(deleteRule: .cascade, inverse: \TaxChecklistItem.property)
    var taxChecklistItems: [TaxChecklistItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \ThreeYearThresholdCase.property)
    var thresholdCases: [ThreeYearThresholdCase]? = []

    @Relationship(deleteRule: .cascade, inverse: \CapitalizationDecision.property)
    var capitalizationDecisions: [CapitalizationDecision]? = []

    @Relationship(deleteRule: .cascade, inverse: \TravelExpense.property)
    var travelExpenses: [TravelExpense]? = []

    @Relationship(deleteRule: .cascade, inverse: \HomeOfficeEntry.property)
    var homeOfficeEntries: [HomeOfficeEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \OwnersMeetingEvent.property)
    var ownersMeetings: [OwnersMeetingEvent]? = []

    // Version 2: Sonderumlagen der WEG.
    @Relationship(deleteRule: .cascade, inverse: \SpecialLevy.property)
    var specialLevies: [SpecialLevy]? = []

    init(name: String = "", street: String = "", zipCode: String = "", city: String = "", notes: String = "", purchasePrice: Double = 0, purchaseAncillaryCosts: Double = 0, purchaseDate: Date? = nil, landValue: Double = 0, constructionYear: Int? = nil) {
        self.name = name
        self.street = street
        self.zipCode = zipCode
        self.city = city
        self.notes = notes
        self.createdAt = .now
        self.purchasePrice = purchasePrice
        self.purchaseAncillaryCosts = purchaseAncillaryCosts
        self.purchaseDate = purchaseDate
        self.landValue = landValue
        self.constructionYear = constructionYear
    }

    var address: String {
        "\(street), \(zipCode) \(city)"
    }

    var unitCount: Int {
        units?.count ?? 0
    }

    var occupiedUnitCount: Int {
        units?.filter { $0.activeTenancy != nil }.count ?? 0
    }

    /// Summe der Wohnfläche aller Einheiten dieser Immobilie.
    var totalSizeSquareMeters: Double {
        (units ?? []).reduce(0) { $0 + $1.sizeSquareMeters }
    }

    /// Summe der Miteigentumsanteile (MEA) aller Einheiten dieser Immobilie.
    var totalCoOwnershipShare: Double {
        (units ?? []).reduce(0) { $0 + $1.coOwnershipShare }
    }

    /// Vereinigte, doppelfreie Ausstattungsmerkmale über alle Einheiten hinweg.
    var aggregatedFeatures: [UnitFeature] {
        let all = Set((units ?? []).flatMap { $0.features })
        return all.sorted { $0.label < $1.label }
    }

    /// Jährliche Kaltmiete aus allen aktuell laufenden Mietverhältnissen.
    var annualColdRentFromActiveTenancies: Double {
        annualColdRent(forYear: Calendar.current.component(.year, from: .now))
    }

    /// Jährliche Kaltmiete für ein bestimmtes (auch vergangenes) Kalenderjahr: je Mietverhältnis
    /// monatsgenau anteilig für die im jeweiligen Jahr tatsächlich überlappenden Monate – ein
    /// unterjährig begonnenes oder beendetes Mietverhältnis fließt also nicht mit vollen 12
    /// Monaten ein, und bei einem Mieterwechsel innerhalb eines Jahres werden beide
    /// Mietverhältnisse anteilig berücksichtigt. Vereinfachte Näherung – berücksichtigt keine
    /// unterjährigen Mieterhöhungen innerhalb desselben Mietverhältnisses.
    func annualColdRent(forYear year: Int) -> Double {
        let calendar = Calendar.current
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else { return 0 }
        return (units ?? []).reduce(0.0) { sum, unit in
            sum + (unit.tenancies ?? []).reduce(0.0) { $0 + $1.coldRentContribution(from: yearStart, to: yearEnd) }
        }
    }

    /// Ausgaben dieses Kalenderjahres, Immobilie + alle Einheiten zusammen.
    var expensesThisYear: Double {
        totalExpenses(forYear: Calendar.current.component(.year, from: .now))
    }

    /// Ausgaben für ein bestimmtes Kalenderjahr, Immobilie + alle Einheiten zusammen.
    func totalExpenses(forYear year: Int) -> Double {
        allExpenses(forYear: year).reduce(0) { $0 + $1.amount }
    }

    /// Investitionssumme inkl. Kaufnebenkosten.
    var totalInvestment: Double {
        purchasePrice + purchaseAncillaryCosts
    }

    /// Bruttomietrendite: Jahreskaltmiete ÷ Kaufpreis.
    var grossYieldPercent: Double? {
        guard purchasePrice > 0 else { return nil }
        return (annualColdRentFromActiveTenancies / purchasePrice) * 100
    }

    /// Nettomietrendite: (Jahreskaltmiete − Jahresausgaben) ÷ Kaufpreis inkl. Nebenkosten.
    var netYieldPercent: Double? {
        guard totalInvestment > 0 else { return nil }
        return ((annualColdRentFromActiveTenancies - expensesThisYear) / totalInvestment) * 100
    }

    // MARK: - Steuer / AfA

    /// Gesetzlicher linearer AfA-Satz nach §7 Abs. 4 EStG, grob anhand des Baujahrs:
    /// ab Fertigstellung 2023 → 3 %, vor 1925 → 2,5 %, sonst 2 %. Keine Steuerberatung,
    /// nur eine Orientierungshilfe – bei Bedarf über `afaRatePercentOverride` anpassen.
    var defaultAfaRatePercent: Double {
        guard let constructionYear else { return 2.0 }
        if constructionYear >= 2023 { return 3.0 }
        if constructionYear < 1925 { return 2.5 }
        return 2.0
    }

    /// Das jüngste Restnutzungsdauergutachten dieser Immobilie, sofern vorhanden.
    var latestRemainingUsefulLifeAppraisal: RemainingUsefulLifeAppraisal? {
        (remainingUsefulLifeAppraisals ?? []).sorted { $0.createdAt > $1.createdAt }.first
    }

    /// Das jüngste Gutachten, sofern es steuerlich anwendbar ist: § 7 Abs. 4 Satz 2 EStG erlaubt
    /// nur eine kürzere tatsächliche Nutzungsdauer, also einen höheren Satz als den typisierten.
    /// Ergibt das Gutachten einen niedrigeren oder gleichen Satz, bleibt es beim typisierten Satz.
    var applicableRemainingUsefulLifeAppraisal: RemainingUsefulLifeAppraisal? {
        guard let appraisal = latestRemainingUsefulLifeAppraisal,
              appraisal.suggestedAfaRatePercent > defaultAfaRatePercent else { return nil }
        return appraisal
    }

    /// Herkunft des angewandten AfA-Satzes – für die Anzeige der Rechtsgrundlage in Steuer-Cockpit
    /// und Berichten.
    var afaRateSource: AfaRateSource {
        if afaRatePercentOverride != nil { return .manual }
        if applicableRemainingUsefulLifeAppraisal != nil { return .appraisal }
        return .typisiert
    }

    /// Maßgeblicher AfA-Satz: ein manuell gesetzter Satz (`afaRatePercentOverride`) hat stets
    /// Vorrang; ohne manuellen Satz gilt ein anwendbares Restnutzungsdauergutachten (100 / RND,
    /// § 7 Abs. 4 Satz 2 EStG, siehe `applicableRemainingUsefulLifeAppraisal`), sonst der
    /// typisierte Satz nach Baujahr.
    var afaRatePercent: Double {
        if let override = afaRatePercentOverride { return override }
        if let appraisal = applicableRemainingUsefulLifeAppraisal { return appraisal.suggestedAfaRatePercent }
        return defaultAfaRatePercent
    }

    /// Das für den Beginn des Dreijahreszeitraums der 15-%-Grenze maßgebliche Datum: der
    /// wirtschaftliche Übergang, ersatzweise das Kaufdatum.
    var thresholdPeriodStartDate: Date? {
        afaStartDate
    }

    /// Das für den Beginn der Gebäude-AfA maßgebliche Datum: der wirtschaftliche Übergang von
    /// Besitz, Nutzen und Lasten (§7 EStG), ersatzweise – solange nicht erfasst – das
    /// Beurkundungsdatum laut Kaufvertrag. Properties, bei denen nur `purchaseDate` erfasst ist,
    /// verhalten sich dadurch unverändert wie bisher.
    var afaStartDate: Date? {
        economicTransferDate ?? purchaseDate
    }

    /// Die (einzige) 15-%-Dreijahresüberwachung dieser Immobilie, sofern bereits angelegt.
    var thresholdCase: ThreeYearThresholdCase? {
        thresholdCases?.first
    }

    /// Anschaffungskosten gesamt (Kaufpreis + Anschaffungsnebenkosten) – die vollständige
    /// Bemessungsgrundlage, bevor sie auf Grund und Boden / Gebäude aufgeteilt wird.
    var totalAcquisitionCost: Double {
        purchasePrice + purchaseAncillaryCosts
    }

    /// `true`, sobald mindestens einer der Einzelposten (Grunderwerbsteuer/Makler/Notar/
    /// Auflassungsvormerkung) erfasst ist – steuert, ob die AfA-Herleitung die Aufschlüsselung statt
    /// der Summenzeile zeigt.
    var hasItemizedAncillaryCosts: Bool {
        purchaseTransferTaxCosts > 0 || purchaseBrokerCosts > 0 || purchaseNotaryCosts > 0 || purchaseLandRegistryCosts > 0
    }

    /// Verbleibender, nicht einzeln erfasster Teil der Kaufnebenkosten – die Differenz aus der
    /// maßgeblichen Summe `purchaseAncillaryCosts` und den separat erfassten Einzelposten, nie
    /// negativ. So summieren sich die in der AfA-Herleitung gezeigten Einzelpositionen immer exakt
    /// auf `purchaseAncillaryCosts`, unabhängig davon, wie vollständig die Aufschlüsselung gepflegt
    /// ist.
    var purchaseOtherAncillaryCosts: Double {
        max(0, purchaseAncillaryCosts - purchaseTransferTaxCosts - purchaseBrokerCosts - purchaseNotaryCosts - purchaseLandRegistryCosts)
    }

    /// Kaufpreis erfasst, aber kein Bodenwert: Dann gilt rechnerisch der gesamte Kaufpreis als
    /// Gebäude und die AfA ist zu hoch – Berichte weisen darauf ausdrücklich hin.
    var isLandValueMissing: Bool {
        purchasePrice > 0 && landValue <= 0
    }

    /// Anteil von Grund und Boden am reinen Kaufpreis (0...1), aus der im Kaufvertrag bezifferten
    /// Aufteilung (`landValue`) ermittelt – Grundlage dafür, die Anschaffungsnebenkosten
    /// anteilig auf Grund und Gebäude aufzuteilen (sie erhöhen beide, nicht nur das Gebäude).
    var landValuePercentage: Double {
        guard purchasePrice > 0 else { return 0 }
        return min(1, max(0, landValue / purchasePrice))
    }

    /// Grund und Boden, anteilig inkl. Anschaffungsnebenkosten (nicht abschreibbar).
    var apportionedLandValue: Double {
        totalAcquisitionCost * landValuePercentage
    }

    /// Abschreibbarer Gebäudewert = Anschaffungskosten gesamt (Kaufpreis + Nebenkosten) abzüglich
    /// des anteiligen, nicht abschreibbaren Grund-und-Boden-Werts. Die Anschaffungsnebenkosten
    /// (Grunderwerbsteuer, Notar, Makler, Sonstiges) erhöhen die AfA-Bemessungsgrundlage und
    /// werden dabei im selben Verhältnis wie der reine Kaufpreis auf Grund und Gebäude verteilt.
    var buildingValue: Double {
        max(0, totalAcquisitionCost - apportionedLandValue)
    }

    var annualBuildingAfA: Double {
        buildingValue * afaRatePercent / 100
    }

    /// Gebäude-AfA für ein bestimmtes Jahr, im Jahr des wirtschaftlichen Übergangs (ersatzweise
    /// Kaufjahr) monatsgenau anteilig (§ 7 Abs. 1 Satz 4 EStG) – siehe `afaStartDate`. Endet, sobald
    /// der Gebäudewert vollständig abgeschrieben ist: das letzte Jahr enthält nur noch den Restbetrag.
    func buildingAfA(forYear year: Int) -> Double {
        guard buildingValue > 0 else { return 0 }
        guard let afaStartDate else { return annualBuildingAfA }
        let startYear = Calendar.current.component(.year, from: afaStartDate)
        guard year >= startYear else { return 0 }
        let depreciatedBefore = (startYear..<year).reduce(0.0) { $0 + uncappedBuildingAfA(forYear: $1, startDate: afaStartDate) }
        return max(0, min(uncappedBuildingAfA(forYear: year, startDate: afaStartDate), buildingValue - depreciatedBefore))
    }

    private func uncappedBuildingAfA(forYear year: Int, startDate: Date) -> Double {
        let calendar = Calendar.current
        let startYear = calendar.component(.year, from: startDate)
        guard year >= startYear else { return 0 }
        if year == startYear {
            return annualBuildingAfA * Double(13 - calendar.component(.month, from: startDate)) / 12
        }
        return annualBuildingAfA
    }

    /// Erstes Jahr, ab dem eine kumulierte AfA sinnvoll gezählt werden kann: Jahr des
    /// wirtschaftlichen Übergangs (ersatzweise Kaufdatum), sonst ersatzweise Baujahr, sonst das
    /// laufende Jahr – ohne Datum liefert `buildingAfA(forYear:)` für jedes Jahr denselben vollen
    /// Jahresbetrag (kein Anschaffungsjahr zum Anteiligrechnen), ein Anker ist hier also nur zum
    /// Abgrenzen der Summe nötig, nicht zur Monatsanteiligkeit.
    private var buildingAfaAccumulationStartYear: Int {
        if let afaStartDate { return Calendar.current.component(.year, from: afaStartDate) }
        return constructionYear ?? Calendar.current.component(.year, from: .now)
    }

    /// Kumulierte Gebäude-AfA von der Anschaffung (oder ersatzweise ab dem Baujahr) bis
    /// einschließlich des angegebenen Jahres – Richtwert für den Restbuchwert, ersetzt keine
    /// Anlagenbuchhaltung.
    func cumulativeBuildingAfA(uptoYear year: Int) -> Double {
        let startYear = buildingAfaAccumulationStartYear
        guard year >= startYear else { return 0 }
        var sum = 0.0
        for y in startYear...year { sum += buildingAfA(forYear: y) }
        return min(buildingValue, sum)
    }

    /// Restbuchwert Gebäude nach der kumulierten AfA bis einschließlich des angegebenen Jahres.
    func remainingBuildingBookValue(afterYear year: Int) -> Double {
        max(0, buildingValue - cumulativeBuildingAfA(uptoYear: year))
    }

    /// Abschreibung aller zusätzlichen Wirtschaftsgüter (Möblierung, Herstellungskosten) im laufenden Jahr.
    var assetDepreciationThisYear: Double {
        assetDepreciation(forYear: Calendar.current.component(.year, from: .now))
    }

    /// Abschreibung aller zusätzlichen Wirtschaftsgüter für ein bestimmtes Kalenderjahr.
    func assetDepreciation(forYear year: Int) -> Double {
        (depreciableAssets ?? []).reduce(0) { $0 + $1.depreciation(forYear: year) }
    }

    /// Gesamte AfA (Gebäude + Wirtschaftsgüter) im laufenden Jahr.
    var totalAfaThisYear: Double {
        totalAfa(forYear: Calendar.current.component(.year, from: .now))
    }

    /// Gesamte AfA (Gebäude + Wirtschaftsgüter) für ein bestimmtes Kalenderjahr.
    func totalAfa(forYear year: Int) -> Double {
        buildingAfA(forYear: year) + assetDepreciation(forYear: year)
    }

    /// Alle Ausgaben (Immobilie + alle Einheiten) für ein bestimmtes Kalenderjahr, unsortiert.
    /// Eine Ausgabe, die sowohl `property` als auch `unit` gesetzt hat (z.B. jede über die
    /// normale Bearbeitungsmaske einer Einheit zugeordnete Ausgabe – dort wird `property` stets
    /// miterfasst), erscheint sonst sowohl in `expenses` der Immobilie als auch in `expenses` der
    /// Einheit und würde doppelt gezählt; die Entdopplung über die eindeutige Objekt-ID verhindert das.
    func allExpenses(forYear year: Int) -> [Expense] {
        let own = (expenses ?? []).filter { Calendar.current.component(.year, from: $0.date) == year }
        let unitOnes = (units ?? []).flatMap { $0.expenses ?? [] }.filter { Calendar.current.component(.year, from: $0.date) == year }
        var seen = Set<PersistentIdentifier>()
        return (own + unitOnes).filter { seen.insert($0.persistentModelID).inserted }
    }

    /// Erhaltungsaufwand (Reparatur/Instandhaltung) für ein bestimmtes Kalenderjahr.
    func maintenanceExpenses(forYear year: Int) -> Double {
        allExpenses(forYear: year).filter { $0.taxTreatment == .maintenanceExpense }.reduce(0) { $0 + $1.amount }
    }

    /// Sonstige sofort abziehbare Werbungskosten (Versicherung, Steuern, Zinsen, …) für ein bestimmtes Kalenderjahr.
    func otherDeductibleExpenses(forYear year: Int) -> Double {
        allExpenses(forYear: year).filter { $0.taxTreatment == .otherDeductible }.reduce(0) { $0 + $1.amount }
    }

    /// Herstellungskosten (werden nicht sofort abgezogen, sondern über die Nutzungsdauer abgeschrieben) für ein bestimmtes Kalenderjahr.
    func capitalizedExpenses(forYear year: Int) -> Double {
        allExpenses(forYear: year).filter { $0.taxTreatment == .capitalized }.reduce(0) { $0 + $1.amount }
    }

    /// Fahrtkosten zum Objekt (Kilometerpauschale, tatsächlich gefahrene Strecke) für ein
    /// bestimmtes Kalenderjahr, siehe `TravelExpense`.
    func travelExpenseTotal(forYear year: Int) -> Double {
        (travelExpenses ?? [])
            .filter { Calendar.current.component(.year, from: $0.date) == year }
            .reduce(0) { $0 + $1.amount }
    }

    /// Anteilige, bereits auf den Jahreshöchstbetrag (über alle Immobilien hinweg) gedeckelte
    /// Homeoffice-Pauschale dieser Immobilie für ein bestimmtes Kalenderjahr, siehe
    /// `HomeOfficeAllocation`.
    func homeOfficeAllowance(forYear year: Int) -> Double {
        HomeOfficeAllocation.apportionedAmount(for: self, taxYear: year)
    }

    /// Sofort abziehbare Werbungskosten (Erhaltungsaufwand etc., keine Herstellungskosten) im laufenden Jahr.
    var werbungskostenThisYear: Double {
        werbungskosten(forYear: Calendar.current.component(.year, from: .now))
    }

    /// Sofort abziehbare Werbungskosten ohne AfA (Erhaltungsaufwand, sonstige Werbungskosten,
    /// Betriebskosten lt. Abrechnung, Fahrtkosten, Homeoffice-Pauschale, Schuldzinsen) – dieselbe
    /// Berechnung wie die Anlage V, siehe `AnlageVCalculation`.
    func werbungskosten(forYear year: Int) -> Double {
        AnlageVCalculation(property: self, year: year).werbungskostenWithoutAfa
    }

    /// Grob geschätzter steuerlicher Überschuss/Verlust: Kaltmiete − Werbungskosten − AfA.
    /// Vereinfachte Näherung, ersetzt keine Steuerberatung.
    var estimatedTaxableResultThisYear: Double {
        estimatedTaxableResult(forYear: Calendar.current.component(.year, from: .now))
    }

    /// Geschätzter steuerlicher Überschuss/Verlust für ein bestimmtes Kalenderjahr – identisch mit
    /// dem Ergebnis der Anlage V im Steuerreport.
    func estimatedTaxableResult(forYear year: Int) -> Double {
        AnlageVCalculation(property: self, year: year).result
    }

    /// Jahre, für die diese Immobilie bereits Daten hat (Ausgaben, Mietverhältnisse, Wirtschaftsgüter,
    /// Nebenkostenabrechnungen) – als Auswahl für eine Jahresansicht, stets inkl. des laufenden Jahres.
    var availableTaxYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: .now)
        var years: Set<Int> = [currentYear]
        for expense in expenses ?? [] { years.insert(Calendar.current.component(.year, from: expense.date)) }
        for unit in units ?? [] {
            for expense in unit.expenses ?? [] { years.insert(Calendar.current.component(.year, from: expense.date)) }
            for tenancy in unit.tenancies ?? [] {
                years.insert(Calendar.current.component(.year, from: tenancy.startDate))
                if let end = tenancy.endDate { years.insert(Calendar.current.component(.year, from: end)) }
            }
        }
        for asset in depreciableAssets ?? [] { years.insert(Calendar.current.component(.year, from: asset.placedInServiceDate)) }
        for statement in utilityStatements ?? [] { years.insert(statement.year) }
        return years.sorted(by: >)
    }

    // MARK: - Finanzierung (Annuitätendarlehen)

    /// Jährliche Annuität (Zins + Tilgung), über die Laufzeit konstant – vereinfachtes
    /// Annuitätendarlehen ohne Sondertilgungen oder Zinsanpassung.
    var annualAnnuity: Double {
        loanAmount * (interestRatePercent + initialRepaymentRatePercent) / 100
    }

    /// Zins- und Tilgungsanteil sowie Restschuld für ein bestimmtes Jahr, ermittelt durch
    /// jahresweise Simulation ab `loanStartDate`. `nil`, wenn keine Finanzierung hinterlegt ist
    /// oder das Jahr vor Finanzierungsbeginn liegt.
    func loanBreakdown(forYear year: Int) -> (interest: Double, principal: Double, remainingBalance: Double)? {
        guard loanAmount > 0, annualAnnuity > 0, let loanStartDate else { return nil }
        let startYear = Calendar.current.component(.year, from: loanStartDate)
        guard year >= startYear else { return nil }

        // Im Startjahr nur die tatsächlich laufenden Monate (Darlehensbeginn im Dezember = 1/12).
        let monthsInStartYear = Double(13 - Calendar.current.component(.month, from: loanStartDate))
        var balance = loanAmount
        var interestForYear = 0.0
        var principalForYear = 0.0
        var currentYear = startYear
        while currentYear <= year && balance > 0 {
            let fraction = currentYear == startYear ? monthsInStartYear / 12 : 1
            let interest = balance * interestRatePercent / 100 * fraction
            let principal = min(annualAnnuity * fraction - interest, balance)
            if currentYear == year {
                interestForYear = interest
                principalForYear = principal
            }
            balance -= principal
            currentYear += 1
        }
        return (interestForYear, principalForYear, max(0, balance))
    }

    /// Summe aus Zins und Tilgung (= Annuität) für ein bestimmtes Jahr, 0 wenn keine Finanzierung
    /// hinterlegt ist oder das Darlehen in diesem Jahr bereits getilgt war.
    func annuity(forYear year: Int) -> Double {
        guard let breakdown = loanBreakdown(forYear: year) else { return 0 }
        return breakdown.interest + breakdown.principal
    }

    // MARK: - Cashflow

    /// Nicht umlagefähige Betriebskosten aus den Nebenkostenabrechnungen eines Jahres – gehen zu
    /// Lasten des Vermieters und mindern den freien Cashflow (im Gegensatz zu den umlagefähigen
    /// Kosten, die über die Vorauszahlungen von den Mietern getragen werden).
    func nonApportionableUtilityCosts(forYear year: Int) -> Double {
        (utilityStatements ?? [])
            .filter { $0.year == year }
            .reduce(0) { $0 + $1.nonApportionableLineItemsTotal }
    }

    /// Umlagefähige Betriebskosten (inkl. Grundsteuer) aus den Nebenkostenabrechnungen eines
    /// Jahres. Werden normalerweise über die Vorauszahlungen der Mieter gedeckt; der operative
    /// Cashflow zieht sie trotzdem ab, um den tatsächlichen Zahlungsmittelabfluss für den Betrieb
    /// der Immobilie zu zeigen, unabhängig von der Vorauszahlung.
    func apportionableUtilityCosts(forYear year: Int) -> Double {
        (utilityStatements ?? [])
            .filter { $0.year == year }
            .reduce(0) { $0 + $1.totalApportionableCosts }
    }

    /// Operativer Cashflow: wie `freeCashFlow`, zusätzlich auch die umlagefähigen Betriebskosten
    /// abgezogen – zeigt den tatsächlichen Zahlungsmittelabfluss für den laufenden Betrieb der
    /// Immobilie, unabhängig von den Vorauszahlungen der Mieter. Der freie Cashflow geht davon aus,
    /// dass sich Vorauszahlung und umlagefähige Kosten in etwa ausgleichen.
    func operativeCashFlow(forYear year: Int) -> Double {
        freeCashFlow(forYear: year) - apportionableUtilityCosts(forYear: year)
    }

    /// Grob geschätzter freier Cashflow für ein bestimmtes Jahr: Kaltmiete abzüglich aller
    /// Barausgaben (Erhaltungsaufwand, sonstige Werbungskosten, Herstellungskosten – AfA ist nicht
    /// cash-wirksam und daher ausgenommen), nicht umlagefähiger Nebenkosten und der Annuität
    /// (Zins + Tilgung). Ausgaben der Kategorie „Finanzierung" werden hier bewusst nicht
    /// berücksichtigt, da die Annuität diese bereits genauer abbildet – entweder die Finanzierung
    /// hier hinterlegen oder die Zinsen manuell als Ausgabe erfassen, nicht beides zugleich.
    /// Vereinfachte Näherung, ersetzt keine betriebswirtschaftliche Beratung.
    func freeCashFlow(forYear year: Int) -> Double {
        let cashExpenses = allExpenses(forYear: year)
            .filter { $0.category != .financing }
            .reduce(0) { $0 + $1.amount }
        return annualColdRent(forYear: year)
            - cashExpenses
            - nonApportionableUtilityCosts(forYear: year)
            - annuity(forYear: year)
    }

    /// Grob geschätzter freier Cashflow für einen bestimmten Monat: Kaltmiete der in diesem Monat
    /// laufenden Mietverhältnisse abzüglich der in diesem Monat gebuchten Barausgaben sowie
    /// anteiliger (durch 12 geteilter) nicht umlagefähiger Nebenkosten und Annuität des Jahres –
    /// beide liegen nur als Jahreswert vor und werden daher gleichmäßig auf die Monate verteilt.
    /// Vereinfachte Näherung, ersetzt keine betriebswirtschaftliche Beratung.
    func freeCashFlow(forMonth date: Date) -> Double {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let monthlyColdRent = (units ?? []).reduce(0.0) { sum, unit in
            sum + (unit.tenancies ?? []).filter { $0.isRunning(on: date) }.reduce(0.0) { $0 + $1.coldRent(forMonthContaining: date) }
        }
        let monthlyCashExpenses = allExpenses(forYear: year)
            .filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
            .filter { $0.category != .financing }
            .reduce(0.0) { $0 + $1.amount }
        return monthlyColdRent
            - monthlyCashExpenses
            - nonApportionableUtilityCosts(forYear: year) / 12
            - annuity(forYear: year) / 12
    }
}
