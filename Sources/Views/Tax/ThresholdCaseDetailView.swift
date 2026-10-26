import SwiftUI
import SwiftData

/// Einzelnachweis der 15-%-Grenze (§6 Abs. 1 Nr. 1a EStG): Zeitraum und Summenübersicht, sowie je
/// Erhaltungsaufwand-Position im Dreijahreszeitraum eine manuelle Einordnung. Keine Position wird
/// anhand ihrer Bezeichnung automatisch eingeordnet – neue Positionen starten immer als
/// „Nicht klassifiziert“.
struct ThresholdCaseDetailView: View {
    @Bindable var thresholdCase: ThreeYearThresholdCase
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            Section("Zeitraum") {
                LabeledContent("Beginn", value: thresholdCase.periodStart.asShortDate)
                LabeledContent("Ende", value: thresholdCase.periodEnd.asShortDate)
                if thresholdCase.isPeriodOver {
                    Toggle("Prüfung abgeschlossen", isOn: $thresholdCase.manuallyClosed)
                }
            }

            Section("Summe") {
                LabeledContent("Bemessungsgrundlage (Gebäude-AK ohne Grund)", value: thresholdCase.basisAmount.asCurrency)
                LabeledContent("Schwelle (15 %)", value: thresholdCase.thresholdAmount.asCurrency)
                LabeledContent("Einbezogene Netto-Summe", value: thresholdCase.includedNetTotal.asCurrency)
                if let percent = thresholdCase.utilizationPercent {
                    LabeledContent("Auslastung", value: percent.asPercent)
                }
                LabeledContent("Status", value: thresholdCase.status.label)
                    .foregroundStyle(statusColor(thresholdCase.status))
            }

            if !thresholdCase.missingNetAmountExpenses.isEmpty {
                Section {
                    Text("\(thresholdCase.missingNetAmountExpenses.count) Position(en) ohne hinterlegten Umsatzsteuersatz – Netto-Betrag nicht ermittelbar, Summe daher vorläufig.")
                        .foregroundStyle(Theme.statusWarning)
                }
            }

            Section("Positionen im Zeitraum") {
                if thresholdCase.candidateExpenses.isEmpty {
                    Text("Keine Erhaltungsaufwendungen im Dreijahreszeitraum erfasst.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(thresholdCase.candidateExpenses) { expense in
                        if let assessment = thresholdCase.assessment(for: expense) {
                            ThresholdExpenseRow(expense: expense, assessment: assessment)
                        }
                    }
                }
            }
        }
        .navigationTitle("15-%-Grenze")
        .onAppear {
            thresholdCase.ensureAssessments(context: context)
        }
    }

    private func statusColor(_ status: ThresholdCaseStatus) -> Color {
        switch status {
        case .belowThreshold, .completed: return Theme.statusGood
        case .thresholdReached: return Theme.statusWarning
        case .exceeded: return Theme.statusCritical
        case .notConclusivelyCheckable: return .secondary
        }
    }
}

private struct ThresholdExpenseRow: View {
    let expense: Expense
    @Bindable var assessment: ThresholdExpenseAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading) {
                    Text(expense.title).font(.subheadline)
                    Text(expense.date.asShortDate).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(expense.amount.asCurrency)
                    if let netAmount = expense.netAmount {
                        Text("netto \(netAmount.asCurrency)").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Netto unbekannt").font(.caption).foregroundStyle(Theme.statusWarning)
                    }
                }
            }
            Picker("Einordnung", selection: Binding(
                get: { assessment.status },
                set: { assessment.status = $0 }
            )) {
                ForEach(ThresholdExpenseStatus.allCases) { status in
                    Text(status.label).tag(status)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            if assessment.status == .excluded {
                TextField("Begründung (Rechtsgrundlage)", text: $assessment.reason, axis: .vertical)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    let context = PreviewData.container.mainContext
    let property = (try? context.fetch(FetchDescriptor<Property>()))?.first ?? Property()
    let thresholdCase = ThreeYearThresholdCase(periodStart: .now, periodEnd: Calendar.current.date(byAdding: .year, value: 3, to: .now) ?? .now)
    thresholdCase.property = property
    context.insert(thresholdCase)
    thresholdCase.ensureAssessments(context: context)
    return NavigationStack {
        ThresholdCaseDetailView(thresholdCase: thresholdCase)
    }
    .modelContainer(PreviewData.container)
}
