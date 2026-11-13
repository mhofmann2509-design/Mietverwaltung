import SwiftUI
import SwiftData

struct RecordPaymentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let tenancy: Tenancy
    let month: Date

    @State private var coldRentDueText = ""
    @State private var utilityAdvanceDueText = ""
    @State private var isPaid = false
    @State private var paidDate = Date.now
    @State private var paidAmountText = ""
    @State private var note = ""

    private var existingPayment: RentPayment? {
        tenancy.payment(forMonthContaining: month)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("\(tenancy.unit?.property?.name ?? "") · \(tenancy.unit?.name ?? "")") {
                    Text(month.asMonthYear)
                        .foregroundStyle(.secondary)
                    LabeledContent("Mieter", value: tenancy.tenant?.fullName ?? "–")
                }

                Section("Fälliger Betrag") {
                    TextField("Kaltmiete (€)", text: $coldRentDueText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Nebenkosten (€)", text: $utilityAdvanceDueText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }

                Section("Zahlung") {
                    Toggle("Bezahlt", isOn: $isPaid)
                    if isPaid {
                        DatePicker("Bezahlt am", selection: $paidDate, displayedComponents: .date)
                        TextField("Bezahlter Betrag (€)", text: $paidAmountText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                }

                Section("Notiz") {
                    TextField("Notiz", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                ValidationMessagesSection(messages: validationMessages)
            }
            .navigationTitle("Zahlung erfassen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!validationMessages.isEmpty)
                }
            }
            .onAppear(perform: loadExistingValues)
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 360, idealHeight: 460, maxHeight: 780)
            #endif
        }
    }

    private func loadExistingValues() {
        if let existingPayment {
            coldRentDueText = String(existingPayment.coldRentDue)
            utilityAdvanceDueText = String(existingPayment.utilityAdvanceDue)
            isPaid = existingPayment.isPaid
            paidDate = existingPayment.paidDate ?? .now
            paidAmountText = existingPayment.paidAmount.map { String($0) } ?? ""
            note = existingPayment.note
        } else {
            coldRentDueText = String(tenancy.coldRent(forMonthContaining: month))
            utilityAdvanceDueText = String(tenancy.utilityAdvance)
            paidAmountText = String(tenancy.totalMonthlyAmount(forMonthContaining: month))
        }
    }

    private var validationMessages: [String] {
        [
            FormValidation.number(coldRentDueText, "Kaltmiete"),
            FormValidation.number(utilityAdvanceDueText, "Nebenkosten"),
            isPaid ? FormValidation.number(paidAmountText, "Bezahlter Betrag") : nil
        ].compactMap { $0 }
    }

    private func save() {
        let values = FormSaving.PaymentFormValues(
            coldRentDueText: coldRentDueText,
            utilityAdvanceDueText: utilityAdvanceDueText,
            isPaid: isPaid,
            paidDate: paidDate,
            paidAmountText: paidAmountText,
            note: note
        )
        FormSaving.savePayment(values, tenancy: tenancy, month: month, context: modelContext)
        dismiss()
    }
}

#Preview {
    let context = PreviewData.container.mainContext
    let tenancy = (try? context.fetch(FetchDescriptor<Tenancy>()))?.first ?? Tenancy()
    return RecordPaymentView(tenancy: tenancy, month: .now)
        .modelContainer(PreviewData.container)
}
