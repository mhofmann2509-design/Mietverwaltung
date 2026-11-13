import Foundation
import SwiftData

/// Mietrückstandskonto je Mieter und Jahr sowie „Als bezahlt markieren“ – aus
/// `PaymentsOverviewView` ausgelagert, damit die Logik ohne Oberfläche testbar ist.
enum RentLedger {
    struct Row: Equatable {
        let month: Date
        let due: Double
        let paid: Double
        let runningBalance: Double
    }

    /// Ob das Mietverhältnis an einem Monatsersten des Jahres lief (wie bisher in der Übersicht).
    static func isRelevant(_ tenancy: Tenancy, inYear year: Int) -> Bool {
        let calendar = Calendar.current
        return (1...12).contains { month in
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return false }
            return tenancy.isRunning(on: date)
        }
    }

    /// Monatszeilen des Jahres. Der Saldo startet mit dem Rückstand aus den Vorjahren, damit er
    /// dem tatsächlichen Kontostand entspricht und nicht jedes Jahr bei 0 beginnt.
    static func rows(for tenancy: Tenancy, year: Int) -> [Row] {
        let calendar = Calendar.current
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let previousYearEnd = calendar.date(byAdding: .day, value: -1, to: yearStart) else { return [] }
        var running = tenancy.arrearsBalance(upTo: previousYearEnd)
        return (1...12).compactMap { month in
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  tenancy.isRunning(on: date) else { return nil }
            let due = tenancy.totalMonthlyAmount(forMonthContaining: date)
            let payment = tenancy.payment(forMonthContaining: date)
            let paid = (payment?.isPaid == true) ? (payment?.paidAmount ?? due) : 0
            running += (due - paid)
            return Row(month: date, due: due, paid: paid, runningBalance: running)
        }
    }

    /// Alle Jahre, in denen mindestens ein Mietverhältnis läuft, plus das Jahr von `now` –
    /// absteigend sortiert.
    static func availableYears(for tenancies: [Tenancy], now: Date = .now) -> [Int] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        var years: Set<Int> = [currentYear]
        for tenancy in tenancies {
            let startYear = calendar.component(.year, from: tenancy.startDate)
            let endYear = tenancy.endDate.map { calendar.component(.year, from: $0) } ?? currentYear
            guard startYear <= endYear else { continue }
            years.formUnion(startYear...endYear)
        }
        return years.sorted(by: >)
    }

    /// Mieter mit Rückstand zum Stichtag, größter Rückstand zuerst.
    static func currentArrears(_ tenancies: [Tenancy], upTo date: Date = .now) -> [(tenancy: Tenancy, balance: Double)] {
        tenancies
            .map { ($0, $0.arrearsBalance(upTo: date)) }
            .filter { $0.1 > 0.005 }
            .sorted { $0.1 > $1.1 }
    }

    /// Markiert den Monat als bezahlt; fehlt der Zahlungseintrag, wird er mit dem Soll angelegt.
    static func markPaid(tenancy: Tenancy, month: Date, on paidDate: Date = .now, context: ModelContext) {
        if let existing = tenancy.payment(forMonthContaining: month) {
            existing.markPaid(date: paidDate)
        } else {
            let payment = RentPayment(
                dueDate: month,
                coldRentDue: tenancy.coldRent(forMonthContaining: month),
                utilityAdvanceDue: tenancy.utilityAdvance
            )
            payment.markPaid(date: paidDate)
            payment.tenancy = tenancy
            context.insert(payment)
        }
    }

    static func markUnpaid(tenancy: Tenancy, month: Date) {
        tenancy.payment(forMonthContaining: month)?.markUnpaid()
    }
}
