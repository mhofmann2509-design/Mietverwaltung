import Foundation
import SwiftData

/// A single month's rent/utility charge and whether it has been paid.
@Model
final class RentPayment {
    var dueDate: Date = Date.now        // normalized to the 1st of the month
    var coldRentDue: Double = 0
    var utilityAdvanceDue: Double = 0
    var paidDate: Date?
    var paidAmount: Double?
    var note: String = ""

    var tenancy: Tenancy?

    init(dueDate: Date = .now, coldRentDue: Double = 0, utilityAdvanceDue: Double = 0, paidDate: Date? = nil, paidAmount: Double? = nil, note: String = "") {
        self.dueDate = dueDate
        self.coldRentDue = coldRentDue
        self.utilityAdvanceDue = utilityAdvanceDue
        self.paidDate = paidDate
        self.paidAmount = paidAmount
        self.note = note
    }

    var totalDue: Double {
        coldRentDue + utilityAdvanceDue
    }

    var isPaid: Bool {
        paidDate != nil
    }

    var isOverdue: Bool {
        !isPaid && dueDate < Calendar.current.startOfDay(for: .now)
    }

    var outstandingAmount: Double {
        max(0, totalDue - (paidAmount ?? 0))
    }

    func markPaid(amount: Double? = nil, date: Date = .now) {
        paidAmount = amount ?? totalDue
        paidDate = date
    }

    func markUnpaid() {
        paidAmount = nil
        paidDate = nil
    }
}
