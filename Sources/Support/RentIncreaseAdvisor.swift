import Foundation

/// Berechnet für ein Mietverhältnis, je nach vereinbarter Mietvertragsart, den nächstmöglichen
/// Zeitpunkt für eine Mieterhöhung sowie einen kurzen rechtlichen Hinweis dazu. Rein
/// informativ – ersetzt keine Rechtsberatung, insbesondere nicht bei der Ermittlung der
/// ortsüblichen Vergleichsmiete oder bei Modernisierungsmieterhöhungen (§ 559 BGB).
enum RentIncreaseAdvisor {
    struct Advice {
        /// `nil` bei Staffelmiete, wenn keine weitere Stufe mehr erfasst ist.
        let nextPossibleDate: Date?
        let hint: String
    }

    /// Arbeitet rein mit Werten statt mit einem `Tenancy`-Objekt, damit dieselbe Berechnung auch
    /// für eine noch nicht gespeicherte Eingabe (z.B. die Live-Vorschau in `TenancyEditView`)
    /// genutzt werden kann – siehe `advice(for:today:)` für den Aufruf mit einem bestehenden
    /// `Tenancy`.
    static func advice(
        contractType: TenancyContractType,
        startDate: Date,
        lastRentIncreaseDate: Date?,
        lastIndexAdjustmentDate: Date?,
        upcomingStaffelDates: [Date],
        today: Date = .now
    ) -> Advice {
        switch contractType {
        case .standard: return standardAdvice(startDate: startDate, lastRentIncreaseDate: lastRentIncreaseDate)
        case .index: return indexAdvice(startDate: startDate, lastIndexAdjustmentDate: lastIndexAdjustmentDate)
        case .staffel: return staffelAdvice(upcomingStaffelDates: upcomingStaffelDates, today: today)
        }
    }

    static func advice(for tenancy: Tenancy, today: Date = .now) -> Advice {
        advice(
            contractType: tenancy.contractType,
            startDate: tenancy.startDate,
            lastRentIncreaseDate: tenancy.lastRentIncreaseDate,
            lastIndexAdjustmentDate: tenancy.lastIndexAdjustmentDate,
            upcomingStaffelDates: (tenancy.rentSteps ?? []).map(\.effectiveDate),
            today: today
        )
    }

    /// § 558 BGB: Erhöhung auf die ortsübliche Vergleichsmiete frühestens 15 Monate nach
    /// Mietbeginn bzw. der letzten Erhöhung, danach höchstens alle 12 Monate erneut.
    private static func standardAdvice(startDate: Date, lastRentIncreaseDate: Date?) -> Advice {
        let referenceDate = lastRentIncreaseDate ?? startDate
        let nextDate = Calendar.current.date(byAdding: .month, value: 15, to: referenceDate)
        return Advice(
            nextPossibleDate: nextDate,
            hint: "Erhöhung auf die ortsübliche Vergleichsmiete (§ 558 BGB) frühestens 15 Monate nach Mietbeginn bzw. letzter Erhöhung, danach max. alle 12 Monate erneut. Kappungsgrenze i.d.R. max. 20 % in 3 Jahren (in angespannten Wohnungsmärkten 15 %)."
        )
    }

    /// § 557b BGB: Bei Indexmiete ist eine Anpassung frühestens 12 Monate nach der letzten
    /// Anpassung bzw. Mietbeginn möglich, anhand der Veränderung des Verbraucherpreisindex.
    private static func indexAdvice(startDate: Date, lastIndexAdjustmentDate: Date?) -> Advice {
        let referenceDate = lastIndexAdjustmentDate ?? startDate
        let nextDate = Calendar.current.date(byAdding: .month, value: 12, to: referenceDate)
        return Advice(
            nextPossibleDate: nextDate,
            hint: "Anpassung der Indexmiete (§ 557b BGB) frühestens 12 Monate nach Mietbeginn bzw. letzter Anpassung, anhand der Veränderung des Verbraucherpreisindex (VPI) des Statistischen Bundesamtes."
        )
    }

    /// Staffelmiete (§ 557a BGB): Erhöhungstermine und -beträge stehen bereits im Mietvertrag
    /// fest – hier wird nur die nächste noch nicht erreichte Stufe ausgewiesen.
    private static func staffelAdvice(upcomingStaffelDates: [Date], today: Date) -> Advice {
        let nextDate = upcomingStaffelDates.filter { $0 > today }.min()
        return Advice(
            nextPossibleDate: nextDate,
            hint: "Staffelmiete (§ 557a BGB): Erhöhungstermine und -beträge sind bereits im Mietvertrag ziffernmäßig festgelegt, eine gesonderte Mieterhöhungserklärung ist nicht nötig."
        )
    }

    /// § 559b Abs. 2 BGB: Nach einer Modernisierung ist die erhöhte Miete vom Beginn des dritten
    /// Monats nach Zugang der (Text-)Mieterhöhungserklärung an zu entrichten – unabhängig von der
    /// vereinbarten `TenancyContractType`, da eine Modernisierungserhöhung zusätzlich zur
    /// regulären Mieterhöhung möglich ist. Die Maßnahme selbst darf frühestens 3 Monate nach ihrer
    /// Ankündigung (§ 555c BGB) beginnen – das ist unabhängig von diesem Datum.
    static func modernizationIncreaseEffectiveDate(declaredAt: Date) -> Date? {
        let calendar = Calendar.current
        guard let startOfDeclarationMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: declaredAt)) else { return nil }
        return calendar.date(byAdding: .month, value: 3, to: startOfDeclarationMonth)
    }

    /// § 555c BGB: Frühester zulässiger Beginn der Modernisierungsmaßnahme, 3 Monate nach ihrer
    /// Ankündigung in Textform.
    static func modernizationEarliestStartDate(announcedAt: Date) -> Date? {
        Calendar.current.date(byAdding: .month, value: 3, to: announcedAt)
    }
}
