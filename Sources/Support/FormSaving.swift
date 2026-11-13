import Foundation
import SwiftData

/// Speicher-Logik der Bearbeiten-Formulare – aus den Views ausgelagert, damit sie ohne Oberfläche
/// testbar ist. Die Views sammeln ihre Eingaben in einem `…FormValues`-Wert und rufen `save`.
/// Zahlenfelder sind zu diesem Zeitpunkt bereits über `FormValidation` geprüft.
enum FormSaving {
    // MARK: - Mietvertrag

    struct TenancyFormValues {
        enum TenantChoice {
            case existing(Tenant)
            case new(firstName: String, lastName: String)
        }

        var tenant: TenantChoice?
        var startDate: Date
        var endDate: Date?
        var coldRentText = ""
        var utilityAdvanceText = ""
        var depositText = ""
        var depositReceived = false
        var depositReturnedAt: Date?
        var noticePeriodMonths = 3
        var occupantCount = 1
        var notes = ""
        var contractType: TenancyContractType = .standard
        var lastRentIncreaseDate: Date?
        var lastIndexAdjustmentDate: Date?
        var modernizationAnnouncedAt: Date?
        var modernizationIncreaseDeclaredAt: Date?
        var rentSteps: [(effectiveDate: Date, coldRentText: String)] = []
    }

    /// Legt den Mietvertrag an oder aktualisiert ihn. `nil`, wenn kein Mieter gewählt ist.
    /// Staffelstufen werden komplett durch die Eingabe ersetzt und nur bei Staffelmiete gespeichert;
    /// ein Rückgabedatum der Kaution gibt es nur bei beendetem Mietverhältnis.
    @discardableResult
    static func saveTenancy(_ values: TenancyFormValues, existing: Tenancy?, unit: Unit, context: ModelContext) -> Tenancy? {
        let tenant: Tenant
        switch values.tenant {
        case .new(let firstName, let lastName):
            tenant = Tenant(firstName: firstName, lastName: lastName)
            context.insert(tenant)
        case .existing(let selected):
            tenant = selected
        case nil:
            return nil
        }

        let tenancy: Tenancy
        if let existing {
            tenancy = existing
        } else {
            tenancy = Tenancy(startDate: values.startDate)
            tenancy.unit = unit
            context.insert(tenancy)
        }
        tenancy.tenant = tenant
        tenancy.startDate = values.startDate
        tenancy.endDate = values.endDate
        tenancy.coldRent = values.coldRentText.parsedDecimal ?? 0
        tenancy.utilityAdvance = values.utilityAdvanceText.parsedDecimal ?? 0
        tenancy.deposit = values.depositText.parsedDecimal ?? 0
        tenancy.depositReceived = values.depositReceived
        tenancy.noticePeriodMonths = values.noticePeriodMonths
        tenancy.occupantCount = values.occupantCount
        tenancy.notes = values.notes
        tenancy.contractType = values.contractType
        tenancy.lastRentIncreaseDate = values.lastRentIncreaseDate
        tenancy.lastIndexAdjustmentDate = values.lastIndexAdjustmentDate
        tenancy.depositReturnedAt = values.endDate == nil ? nil : values.depositReturnedAt
        tenancy.modernizationAnnouncedAt = values.modernizationAnnouncedAt
        tenancy.modernizationIncreaseDeclaredAt = values.modernizationIncreaseDeclaredAt

        for existingStep in tenancy.rentSteps ?? [] {
            context.delete(existingStep)
        }
        if values.contractType == .staffel {
            for draft in values.rentSteps {
                let step = RentStep(effectiveDate: draft.effectiveDate, coldRent: draft.coldRentText.parsedDecimal ?? 0)
                step.tenancy = tenancy
                context.insert(step)
            }
        }
        return tenancy
    }

    // MARK: - Mietzahlung

    struct PaymentFormValues {
        var coldRentDueText = ""
        var utilityAdvanceDueText = ""
        var isPaid = false
        var paidDate = Date.now
        /// Leer = voller Sollbetrag gezahlt.
        var paidAmountText = ""
        var note = ""
    }

    /// Erfasst die Zahlung für den Monat von `month`; ein bestehender Eintrag wird aktualisiert.
    @discardableResult
    static func savePayment(_ values: PaymentFormValues, tenancy: Tenancy, month: Date, context: ModelContext) -> RentPayment {
        let payment = tenancy.payment(forMonthContaining: month) ?? {
            let newPayment = RentPayment(dueDate: month)
            newPayment.tenancy = tenancy
            context.insert(newPayment)
            return newPayment
        }()
        payment.coldRentDue = values.coldRentDueText.parsedDecimal ?? 0
        payment.utilityAdvanceDue = values.utilityAdvanceDueText.parsedDecimal ?? 0
        payment.note = values.note
        if values.isPaid {
            payment.paidDate = values.paidDate
            payment.paidAmount = values.paidAmountText.parsedDecimal ?? payment.totalDue
        } else {
            payment.markUnpaid()
        }
        return payment
    }

    // MARK: - Ausgabe

    struct ExpenseFormValues {
        var title = ""
        var amountText = ""
        var date = Date.now
        var category: ExpenseCategory = .other
        var taxTreatment: TaxTreatment = ExpenseCategory.other.defaultTaxTreatment
        var property: Property?
        var unit: Unit?
        var vatRateText = ""
        var notes = ""
        var receiptPending = true
    }

    /// Legt die Ausgabe an oder aktualisiert sie. Ein Umsatzsteuersatz wird nur bei sofort
    /// abziehbarem Erhaltungsaufwand gespeichert.
    @discardableResult
    static func saveExpense(_ values: ExpenseFormValues, existing: Expense?, context: ModelContext) -> Expense {
        let expense: Expense
        if let existing {
            expense = existing
        } else {
            expense = Expense(date: values.date, amount: 0)
            context.insert(expense)
        }
        expense.title = values.title
        expense.amount = values.amountText.parsedDecimal ?? 0
        expense.date = values.date
        expense.category = values.category
        expense.taxTreatment = values.taxTreatment
        expense.property = values.property
        expense.unit = values.unit
        expense.vatRatePercent = values.taxTreatment == .maintenanceExpense ? values.vatRateText.parsedDecimal : nil
        expense.notes = values.notes
        expense.receiptPending = values.receiptPending
        return expense
    }
}

extension LineItemDraft {
    /// Die speicherbaren Positionen eines Formulars: leere Zeilen und Beträge ≤ 0 entfallen,
    /// die Kostenart wird von Leerzeichen befreit. Gemeinsam von Nebenkostenabrechnung und
    /// Wirtschaftsplan genutzt.
    static func persistable(_ drafts: [LineItemDraft]) -> [(costType: String, amount: Double, isApportionable: Bool, allocationKeyLabel: String)] {
        drafts.compactMap { draft in
            let costType = draft.costType.trimmingCharacters(in: .whitespaces)
            guard let amount = draft.amountText.parsedDecimal, amount > 0, !costType.isEmpty else { return nil }
            return (costType, amount, draft.isApportionable, draft.allocationKeyLabel ?? "")
        }
    }
}
