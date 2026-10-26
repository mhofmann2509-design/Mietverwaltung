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
/// oder eine bald fällige Nebenkostenabrechnung.
struct ReminderItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let severity: ReminderSeverity
    let systemImage: String
}

/// Leitet aus den vorhandenen Daten (ohne eigenes Speichermodell) anstehende
/// Aufgaben und Fristen ab: überfällige Mieten, bald endende Mietverträge und die
/// gesetzliche Nebenkostenabrechnungs-Frist (12 Monate nach Ablauf des Abrechnungsjahres).
enum RemindersEngine {
    static func reminders(properties: [Property], tenancies: [Tenancy]) -> [ReminderItem] {
        var items: [ReminderItem] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        for tenancy in tenancies where tenancy.isActive {
            if let payment = tenancy.payment(forMonthContaining: today), payment.isOverdue {
                items.append(ReminderItem(
                    title: "Miete überfällig",
                    subtitle: "\(tenancy.tenant?.fullName ?? "Unbekannter Mieter") · \(tenancy.unit?.name ?? "") · offen seit \(payment.dueDate.asShortDate)",
                    severity: .overdue,
                    systemImage: "exclamationmark.circle.fill"
                ))
            }

            if let endDate = tenancy.endDate {
                let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: endDate)).day ?? -1
                if days >= 0 && days <= 90 {
                    items.append(ReminderItem(
                        title: "Mietvertrag endet bald",
                        subtitle: "\(tenancy.tenant?.fullName ?? "") · \(tenancy.unit?.name ?? "") · endet am \(endDate.asShortDate)",
                        severity: days <= 30 ? .warning : .info,
                        systemImage: "calendar.badge.exclamationmark"
                    ))
                }
            }
        }

        let currentYear = calendar.component(.year, from: today)
        for property in properties {
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
                let daysLeft = calendar.dateComponents([.day], from: today, to: deadline).day ?? 0

                if daysLeft < 0 {
                    items.append(ReminderItem(
                        title: "Nebenkostenabrechnung überfällig",
                        subtitle: "\(property.name) · Abrechnungsjahr \(candidateYear) · Frist war \(deadline.asShortDate)",
                        severity: .overdue,
                        systemImage: "doc.badge.clock"
                    ))
                } else if daysLeft <= 90 {
                    items.append(ReminderItem(
                        title: "Nebenkostenabrechnung fällig",
                        subtitle: "\(property.name) · Abrechnungsjahr \(candidateYear) · Frist bis \(deadline.asShortDate)",
                        severity: .warning,
                        systemImage: "doc.badge.clock"
                    ))
                }
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
                    title: "Wirtschaftsplan fehlt",
                    subtitle: "\(property.name) · für \(currentYear) noch kein Wirtschaftsplan erfasst",
                    severity: .warning,
                    systemImage: "doc.badge.clock"
                ))
            }
        }

        return items.sorted { $0.severity < $1.severity }
    }
}
