import SwiftUI
import SwiftData

/// Übersicht der Restnutzungsdauergutachten einer Immobilie – jedes Gutachten berechnet aus
/// Baujahr, Bewertungsstichtag und Modernisierungsgrad eine Restnutzungsdauer (RND) und daraus
/// einen AfA-Satz, der auf Wunsch als manueller AfA-Satz der Immobilie übernommen werden kann.
struct RemainingUsefulLifeAppraisalListView: View {
    @Bindable var property: Property
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddSheet = false
    @State private var appraisalToEdit: RemainingUsefulLifeAppraisal?

    private var appraisals: [RemainingUsefulLifeAppraisal] {
        (property.remainingUsefulLifeAppraisals ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            if appraisals.isEmpty {
                Section {
                    Text("Noch kein Restnutzungsdauergutachten erfasst.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(appraisals) { appraisal in
                        Button {
                            appraisalToEdit = appraisal
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Baujahr \(String(appraisal.constructionYear)) · Stichtag \(appraisal.valuationDate.asShortDate)")
                                    .foregroundStyle(.primary)
                                HStack {
                                    Text("RND: \(Int(appraisal.remainingUsefulLifeYears.rounded())) Jahre")
                                    Spacer()
                                    Text("AfA-Satz: \(appraisal.suggestedAfaRatePercent.asPercent)")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteAppraisals)
                }
            }

            Section {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Restnutzungsdauergutachten anlegen", systemImage: "plus")
                }
            } footer: {
                Text("Vereinfachtes Modell nach Anlage 2 ImmoWertV, ersetzt kein Gutachten eines öffentlich bestellten Sachverständigen.")
            }
        }
        .navigationTitle("Restnutzungsdauergutachten")
        .sheet(isPresented: $showingAddSheet) {
            RemainingUsefulLifeAppraisalEditView(property: property, appraisal: nil)
        }
        .sheet(item: $appraisalToEdit) { appraisal in
            RemainingUsefulLifeAppraisalEditView(property: property, appraisal: appraisal)
        }
    }

    private func deleteAppraisals(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(appraisals[index])
        }
    }
}

#Preview {
    let context = PreviewData.container.mainContext
    let property = (try? context.fetch(FetchDescriptor<Property>()))?.first ?? Property()
    return NavigationStack {
        RemainingUsefulLifeAppraisalListView(property: property)
    }
    .modelContainer(PreviewData.container)
}
