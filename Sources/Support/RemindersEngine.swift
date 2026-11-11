import Foundation
import SwiftUI

/// Wie dringend ein Hinweis ist.
enum ReminderSeverity: Int, Comparable {
    case overdue = 0
    case warning = 1
    case info = 2

    static func < (lhs: ReminderSeverity, rhs: ReminderSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var color: Color {
        switch self {
        case .overdue: return Theme.statusCritical
        case .warning: return Theme.statusWarning
        case .info: return .accentColor
        }
    }
}

/// Ein einzelner Hinweis/eine Frist auf dem Dashboard, z.B. eine überfällige Zahlung
/// oder eine bald fällige Nebenkostenabrechnung. `id` ist bewusst stabil (statt einer frischen
/// `UUID()` je Aufruf) und aus den beteiligten Objekten abgeleitet, damit `NotificationScheduler`
/// beim Abgleich dieselbe Erinnerung wiedererkennt. `dueDate`, falls gesetzt, ist der Tag, auf den
/// sich die Erinnerung bezieht – Grundlage für den Zeitpunkt der Push-Mitteilung.
struct ReminderItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let severity: ReminderSeverity
    let systemImage: String
    let dueDate: Date?
}

/// Leitet aus den vorhandenen Daten (ohne eigenes Speichermodell) anstehende Aufgaben und
/// Fristen ab: überfällige Mieten, bald endende Mietverträge, die gesetzliche
/// Nebenkostenabrechnungs-Frist (12 Monate nach Ablauf des Abrechnungsjahres), die
/// Steuererklärungs-Frist (§ 149 AO), anstehende Mieterhöhungsmöglichkeiten/-stufen und
/// bevorstehende Eigentümerversammlungen.
enum RemindersEngine {
    static func reminders(
        properties: [Property],
        tenancies: [Tenancy],
        landlord: Landlord?,
        taxFilingStatuses: [TaxFilingStatus] = [],
        ownersMeetings: [OwnersMeetingEvent] = [],
        now: Date = .now
    ) -> [ReminderItem] {
        var items: [ReminderItem] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        func daysUntil(_ date: Date) -> Int {
            calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? Int.max
        }

        for tenancy in tenancies where tenancy.isRunning(on: today) {
            let tenancyKey = tenancy.persistentModelID

            if let payment = tenancy.payment(forMonthContaining: today), payment.isOverdue {
                items.append(ReminderItem(
                    id: "rent-overdue-\(tenancyKey)",
                    title: "Miete überfällig",
                    subtitle: "\(tenancy.tenant?.fullName ?? "Unbekannter Mieter") · \(tenancy.unit?.name ?? "") · offen seit \(payment.dueDate.asShortDate)",
                    severity: .overdue,
                    systemImage: "exclamationmark.circle.fill",
                    dueDate: payment.dueDate
                ))
            }

            if let endDate = tenancy.endDate {
                let days = daysUntil(endDate)
                if days >= 0 && days <= 90 {
                    items.append(ReminderItem(
                        id: "tenancy-ending-\(tenancyKey)",
                        title: "Mietvertrag endet bald",
                        subtitle: "\(tenancy.tenant?.fullName ?? "") · \(tenancy.unit?.name ?? "") · endet am \(endDate.asShortDate)",
                        severity: days <= 30 ? .warning : .info,
                        systemImage: "calendar.badge.exclamationmark",
                        dueDate: endDate
                    ))
                }
            }

            let advice = RentIncreaseAdvisor.advice(for: tenancy, today: today)
            if let nextDate = advice.nextPossibleDate {
                let days = daysUntil(nextDate)
                if days <= 60 {
                    let title: String
                    switch tenancy.contractType {
                    case .standard: title = days <= 0 ? "Mieterhöhung möglich" : "Mieterhöhung bald möglich"
                    case .index: title = days <= 0 ? "Indexmietanpassung möglich" : "Indexmietanpassung bald möglich"
                    case .staffel: title = "Staffelmietstufe steht an"
                    }
                    items.append(ReminderItem(
                        id: "rent-increase-\(tenancyKey)",
                        title: title,
                        subtitle: "\(tenancy.tenant?.fullName ?? "") · \(tenancy.unit?.name ?? "") · ab \(nextDate.asShortDate) · \(advice.hint)",
                        severity: .info,
                        systemImage: "arrow.up.circle",
                        dueDate: nextDate
                    ))
                }
            }

            if let declaredAt = tenancy.modernizationIncreaseDeclaredAt,
               let effectiveDate = RentIncreaseAdvisor.modernizationIncreaseEffectiveDate(declaredAt: declaredAt) {
                let days = daysUntil(effectiveDate)
                if days >= -14 && days <= 60 {
                    items.append(ReminderItem(
                        id: "modernization-increase-\(tenancyKey)",
                        title: days <= 0 ? "Modernisierungsmieterhöhung wirksam" : "Modernisierungsmieterhöhung bald wirksam",
                        subtitle: "\(tenancy.tenant?.fullName ?? "") · \(tenancy.unit?.name ?? "") · erhöhte Miete zu entrichten ab \(effectiveDate.asShortDate) (§ 559b Abs. 2 BGB) – ggf. Kaltmiete im Mietvertrag nachtragen.",
                        severity: .info,
                        systemImage: "hammer.circle",
                        dueDate: effectiveDate
                    ))
                }
            }
        }

        // Beendete Mietverhältnisse: Kautionsrückzahlung noch offen. Eigene Schleife, da
        // `tenancy.isActive` für beendete Mietverhältnisse false ist und sie oben nicht erfasst.
        for tenancy in tenancies where !tenancy.isRunning(on: today) {
            guard let daysSince = tenancy.daysSinceEndWithUnreturnedDeposit(today: today), daysSince <= 365 else { continue }
            let tenancyKey = tenancy.persistentModelID
            let dueDate = tenancy.endDate.flatMap { calendar.date(byAdding: .month, value: 6, to: $0) }
            items.append(ReminderItem(
                id: "deposit-unreturned-\(tenancyKey)",
                title: daysSince > 180 ? "Kaution noch nicht zurückgezahlt" : "Kautionsrückzahlung prüfen",
                subtitle: "\(tenancy.tenant?.fullName ?? "") · \(tenancy.unit?.name ?? "") · Mietende \(tenancy.endDate?.asShortDate ?? "") · keine feste gesetzliche Frist, bis zu 6 Monate gelten als übliche Obergrenze (Rechtsprechung).",
                severity: daysSince > 180 ? .warning : .info,
                systemImage: "eurosign.circle",
                dueDate: dueDate
            ))
        }

        let currentYear = calendar.component(.year, from: today)
        for property in properties {
            let propertyKey = property.persistentModelID
            let existingStatements = property.utilityStatements ?? []
            let existingYears = Set(existingStatements.map { $0.year })
            // Monat/Tag-Muster des Zeitraumendes, abgeleitet aus der zuletzt erfassten Abrechnung
            // dieser Immobilie (z.B. 30.06. bei einem abweichenden Wirtschaftsjahr) – ohne
            // vorhandene Abrechnung bleibt mangels Daten nur die Kalenderjahresannahme (31.12.).
            let periodEndPattern: DateComponents = {
                guard let latest = existingStatements.sorted(by: { $0.periodEnd > $1.periodEnd }).first else {
                    return DateComponents(month: 12, day: 31)
                }
                let comps = calendar.dateComponents([.month, .day], from: latest.periodEnd)
                return DateComponents(month: comps.month, day: comps.day)
            }()

            for candidateYear in [currentYear - 2, currentYear - 1] {
                guard !existingYears.contains(candidateYear) else { continue }
                guard !(property.units ?? []).isEmpty else { continue }
                guard let expectedPeriodEnd = calendar.date(from: DateComponents(year: candidateYear, month: periodEndPattern.month, day: periodEndPattern.day)) else { continue }
                guard let deadline = calendar.date(byAdding: .month, value: 12, to: expectedPeriodEnd) else { continue }
                let daysLeft = daysUntil(deadline)

                if daysLeft < 0 {
                    items.append(ReminderItem(
                        id: "utility-statement-overdue-\(propertyKey)-\(candidateYear)",
                        title: "Nebenkostenabrechnung überfällig",
                        subtitle: "\(property.name) · Abrechnungsjahr \(candidateYear) · Frist war \(deadline.asShortDate)",
                        severity: .overdue,
                        systemImage: "doc.badge.clock",
                        dueDate: deadline
                    ))
                } else if daysLeft <= 90 {
                    items.append(ReminderItem(
                        id: "utility-statement-due-\(propertyKey)-\(candidateYear)",
                        title: "Nebenkostenabrechnung fällig",
                        subtitle: "\(property.name) · Abrechnungsjahr \(candidateYear) · Frist bis \(deadline.asShortDate)",
                        severity: .warning,
                        systemImage: "doc.badge.clock",
                        dueDate: deadline
                    ))
                }
            }

            // Grunderwerbsteuer-Status: kein fester, aus dem Kaufdatum berechenbarer Fristtermin
            // (hängt vom individuellen Steuerbescheid des Finanzamts ab, siehe
            // `Property.purchaseTransferTaxPaid`) – daher nur ein einmaliger Check-in-Hinweis ohne
            // `dueDate`, nicht als Frist mit Datum.
            if !property.purchaseTransferTaxPaid,
               let purchaseDate = property.purchaseDate,
               let checkDate = calendar.date(byAdding: .month, value: 3, to: purchaseDate),
               let expiryDate = calendar.date(byAdding: .month, value: 24, to: purchaseDate),
               today >= checkDate, today <= expiryDate {
                items.append(ReminderItem(
                    id: "transfer-tax-check-\(propertyKey)",
                    title: "Grunderwerbsteuer prüfen",
                    subtitle: "\(property.name) · noch nicht als bezahlt markiert – Status beim Steuerbescheid/Finanzamt prüfen (kein fester, berechenbarer Fristtermin).",
                    severity: .info,
                    systemImage: "building.columns",
                    dueDate: nil
                ))
            }

            // Wirtschaftsplan fürs laufende Jahr – anders als die Abrechnung keine gesetzliche
            // Frist, aber üblicherweise zu Jahresbeginn von der Hausverwaltung beschlossen. Ab dem
            // 1. April ohne erfassten Plan gilt das als Hinweis, um ihn nachzutragen.
            let planYears = Set((property.wirtschaftsplaene ?? []).map { $0.year })
            if !planYears.contains(currentYear),
               !(property.units ?? []).isEmpty,
               let cutoff = calendar.date(from: DateComponents(year: currentYear, month: 4, day: 1)),
               today >= cutoff {
                items.append(ReminderItem(
                    id: "wirtschaftsplan-missing-\(propertyKey)-\(currentYear)",
                    title: "Wirtschaftsplan fehlt",
                    subtitle: "\(property.name) · für \(currentYear) noch kein Wirtschaftsplan erfasst",
                    severity: .warning,
                    systemImage: "doc.badge.clock",
                    dueDate: nil
                ))
            }
        }

        for status in taxFilingStatuses where !status.isSubmitted {
            let deadline = status.effectiveDeadline(usesTaxAdvisor: landlord?.usesTaxAdvisor ?? false)
            let daysLeft = daysUntil(deadline)
            guard daysLeft <= 90 else { continue }
            items.append(ReminderItem(
                id: "tax-filing-\(status.taxYear)",
                title: daysLeft < 0 ? "Steuererklärung überfällig" : "Steuererklärung fällig",
                subtitle: "Steuerjahr \(status.taxYear) · Frist \(deadline.asShortDate)",
                severity: daysLeft < 0 ? .overdue : (daysLeft <= 30 ? .warning : .info),
                systemImage: "doc.text.magnifyingglass",
                dueDate: deadline
            ))
        }

        for meeting in ownersMeetings {
            let daysLeft = daysUntil(meeting.date)
            guard daysLeft >= 0, daysLeft <= 14 else { continue }
            items.append(ReminderItem(
                id: "owners-meeting-\(meeting.persistentModelID)",
                title: "Eigentümerversammlung bevorstehend",
                subtitle: "\(meeting.property?.name ?? "") · \(meeting.title) am \(meeting.date.asShortDate)" + (meeting.location.isEmpty ? "" : " · \(meeting.location)"),
                severity: daysLeft <= 3 ? .warning : .info,
                systemImage: "person.3.fill",
                dueDate: meeting.date
            ))
        }

        return items.sorted { $0.severity < $1.severity }
    }
}
