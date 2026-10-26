import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import QuickLook

private struct UtilityAllocationRow: Identifiable {
    let id = UUID()
    let tenancy: Tenancy
    let unitName: String
    let tenantName: String
    /// Fertige Anrede fürs Anschreiben, z.B. „Sehr geehrter Herr Mustermann,“ (siehe `Tenant.formalSalutation`).
    let tenantSalutation: String
    let allocatedCost: Double
    let advancesPaid: Double
    /// Konkreter Anteil dieser Einheit am gewählten Umlageschlüssel als Verhältnis (z.B. „144/1.000“).
    let keyDetail: String

    /// Positiv = Nachzahlung des Mieters, negativ = Guthaben zugunsten des Mieters.
    var difference: Double { (allocatedCost - advancesPaid).roundedToCents }
}

struct UtilityStatementDetailView: View {
    @Bindable var statement: UtilityStatement
    @Environment(\.modelContext) private var modelContext
    @Query private var landlords: [Landlord]
    @State private var showingEditSheet = false
    @State private var showingFileImporter = false
    @State private var pdfPreviewURL: URL?

    private var landlordEmail: String { landlords.first?.email ?? "" }

    private var periodText: String {
        "\(statement.periodStart.asShortDate) – \(statement.periodEnd.asShortDate)"
    }

    /// Gewicht einer Einheit/eines Mietverhältnisses nach dem gewählten Umlageschlüssel,
    /// bezogen auf die gesamte Immobilie (unabhängig von der Belegung – Leerstand bleibt beim Vermieter).
    private func weight(forUnit unit: Unit, property: Property) -> Double {
        switch statement.allocationMethod {
        case .livingSpace:
            let totalSize = property.totalSizeSquareMeters
            return totalSize > 0 ? unit.sizeSquareMeters / totalSize : 0
        case .unitCount:
            let totalUnits = (property.units ?? []).count
            return totalUnits > 0 ? 1.0 / Double(totalUnits) : 0
        case .personCount:
            let totalPersons = (property.units ?? []).reduce(0) { sum, unit in
                sum + (unit.tenancies ?? []).filter { $0.isRunning(on: statement.periodEnd) }.reduce(0) { $0 + $1.occupantCount }
            }
            let unitPersons = (unit.tenancies ?? []).filter { $0.isRunning(on: statement.periodEnd) }.reduce(0) { $0 + $1.occupantCount }
            return totalPersons > 0 ? Double(unitPersons) / Double(totalPersons) : 0
        case .coOwnershipShare:
            let totalShare = property.totalCoOwnershipShare
            return totalShare > 0 ? unit.coOwnershipShare / totalShare : 0
        }
    }

    /// Konkreter Anteil dieser Einheit am gewählten Umlageschlüssel als Verhältnis
    /// (Einheit/Gesamt), z.B. „144/1.000“ bei MEA oder „68/123 m²“ bei Wohnfläche.
    private func keyDetail(forUnit unit: Unit, property: Property, weight: Double) -> String {
        switch statement.allocationMethod {
        case .livingSpace:
            return "\(unit.sizeSquareMeters.formatted())/\(property.totalSizeSquareMeters.formatted()) m²"
        case .unitCount:
            let totalUnits = (property.units ?? []).count
            return "1/\(totalUnits)"
        case .personCount:
            let totalPersons = (property.units ?? []).reduce(0) { sum, u in
                sum + (u.tenancies ?? []).filter { $0.isRunning(on: statement.periodEnd) }.reduce(0) { $0 + $1.occupantCount }
            }
            let unitPersons = (unit.tenancies ?? []).filter { $0.isRunning(on: statement.periodEnd) }.reduce(0) { $0 + $1.occupantCount }
            return "\(unitPersons)/\(totalPersons)"
        case .coOwnershipShare:
            return "\(unit.coOwnershipShare.formatted())/\(property.totalCoOwnershipShare.formatted())"
        }
    }

    private var allocationRows: [UtilityAllocationRow] {
        guard let property = statement.property else { return [] }
        let calendar = Calendar.current
        let totalDays = (calendar.dateComponents([.day], from: statement.periodStart, to: statement.periodEnd).day ?? 0) + 1
        guard totalDays > 0 else { return [] }

        var rows: [UtilityAllocationRow] = []
        for unit in property.units ?? [] {
            let unitWeight = weight(forUnit: unit, property: property)
            guard unitWeight > 0 else { continue }
            for tenancy in unit.tenancies ?? [] {
                let days = tenancy.activeDays(from: statement.periodStart, to: statement.periodEnd)
                guard days > 0 else { continue }
                let timeShare = Double(days) / Double(totalDays)
                let allocated = (statement.totalApportionableCosts * unitWeight * timeShare).roundedToCents
                let paid = tenancy.utilityAdvancesPaid(from: statement.periodStart, to: statement.periodEnd).roundedToCents
                rows.append(UtilityAllocationRow(
                    tenancy: tenancy,
                    unitName: unit.name.isEmpty ? "Einheit" : unit.name,
                    tenantName: tenancy.tenant?.fullName ?? "Unbekannter Mieter",
                    tenantSalutation: tenancy.tenant?.formalSalutation ?? "Sehr geehrte(r) Mieter/in,",
                    allocatedCost: allocated,
                    advancesPaid: paid,
                    keyDetail: keyDetail(forUnit: unit, property: property, weight: unitWeight)
                ))
            }
        }
        return rows.sorted { $0.unitName < $1.unitName }
    }

    // MARK: - Verschickt-Markierung je Mietverhältnis

    private func dispatch(for tenancy: Tenancy) -> UtilityStatementDispatch? {
        (statement.dispatches ?? []).first { $0.tenancy == tenancy }
    }

    private func toggleDispatch(for tenancy: Tenancy) {
        if let existing = dispatch(for: tenancy) {
            modelContext.delete(existing)
        } else {
            let new = UtilityStatementDispatch()
            new.statement = statement
            new.tenancy = tenancy
            modelContext.insert(new)
        }
    }

    /// Individuelles Abrechnungsschreiben für einen einzelnen Mieter (zum Versenden/Ablegen).
    private func letterText(for row: UtilityAllocationRow) -> String {
        let property = statement.property
        var lines = [
            "Nebenkostenabrechnung für den Zeitraum \(periodText)",
            "\(property?.name ?? "") · \(row.unitName)",
            "",
            row.tenantSalutation,
            "",
            "anbei die Abrechnung der umlagefähigen Betriebskosten für den oben genannten Zeitraum.",
            "Umlageschlüssel: \(statement.allocationMethod.label) – \(row.keyDetail)",
            "",
        ]
        for item in (statement.lineItems ?? []).filter({ $0.isApportionable }).sorted(by: { $0.costType < $1.costType }) {
            lines.append("• \(item.costType): \(item.amount.asCurrency)")
        }
        lines.append("• Grundsteuer: \(statement.propertyTaxAmount.asCurrency)")
        lines.append("")
        lines.append("Umlagefähige Gesamtkosten: \(statement.totalApportionableCosts.asCurrency)")
        lines.append("Ihr Anteil: \(row.allocatedCost.asCurrency)")
        lines.append("Geleistete Vorauszahlungen: \(row.advancesPaid.asCurrency)")
        lines.append("")
        if row.difference >= 0.005 {
            lines.append("Nachzahlung: \(row.difference.asCurrency)")
            if let property, !property.iban.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("Bitte überweisen Sie den Betrag auf folgendes Konto:")
                lines.append("\(property.bankAccountHolder)")
                lines.append("IBAN: \(property.iban)")
                if !property.bic.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.append("BIC: \(property.bic)")
                }
            }
        } else {
            lines.append("Guthaben zu Ihren Gunsten: \(abs(row.difference).asCurrency)")
        }
        lines.append("")
        lines.append("Mit freundlichen Grüßen")
        return lines.joined(separator: "\n")
    }

    private func saveAsDocument(title: String, text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let document = Document(title: title, fileName: "\(title).txt", fileExtension: "txt", data: data, receiptDate: .now)
        document.property = statement.property
        document.utilityStatement = statement
        modelContext.insert(document)
    }

    /// Gesamtübersicht als echte `.xlsx`-Tabelle: ein Blatt mit den Kostenarten (inkl.
    /// Umlagefähigkeit), ein zweites mit der Verteilung auf die Mieter.
    private func overviewXLSXURL() -> URL? {
        var costRows: [[XLSXExporter.CellValue]] = (statement.lineItems ?? []).sorted(by: { $0.costType < $1.costType }).map { item in
            [.string(item.costType), .string(item.isApportionable ? "Ja" : "Nein"), .currency(item.amount)]
        }
        costRows.append([.string("Grundsteuer"), .string("Ja"), .currency(statement.propertyTaxAmount)])
        let costSheet = XLSXExporter.Sheet(
            name: "Kostenarten",
            headers: ["Kostenart", "Umlagefähig", "Betrag"],
            rows: costRows
        )

        let tenantRows: [[XLSXExporter.CellValue]] = allocationRows.map { row in
            [.string(row.tenantName), .string(row.unitName), .currency(row.allocatedCost), .currency(row.advancesPaid), .currency(row.difference)]
        }
        let tenantSheet = XLSXExporter.Sheet(
            name: "Mieterverteilung",
            headers: ["Mieter", "Einheit", "Anteil", "Vorauszahlung", "Nachzahlung (+) / Guthaben (-)"],
            rows: tenantRows
        )

        guard let data = XLSXExporter.data(sheets: [costSheet, tenantSheet]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nebenkostenabrechnung \(statement.year) – Übersicht.xlsx")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func saveXLSXAsDocument(title: String, url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let document = Document(title: title, fileName: "\(title).xlsx", fileExtension: "xlsx", data: data, receiptDate: .now)
        document.property = statement.property
        document.utilityStatement = statement
        modelContext.insert(document)
    }

    /// Gesamtübersicht als PDF – nennt, anders als die Schreiben an die Mieter, auch die nicht
    /// umlagefähigen Kostenarten und die komplette Mieterverteilung auf einen Blick.
    @MainActor
    private func overviewPDFURL() -> URL? {
        let items = (statement.lineItems ?? []).sorted(by: { $0.costType < $1.costType }).map {
            GesamtuebersichtReportDocument.LineItem(costType: $0.costType, amount: $0.amount, isApportionable: $0.isApportionable)
        }
        let rows = allocationRows.map {
            GesamtuebersichtReportDocument.AllocationRow(tenantName: $0.tenantName, unitName: $0.unitName, allocatedCost: $0.allocatedCost, advancesPaid: $0.advancesPaid)
        }
        let document = GesamtuebersichtReportDocument(
            propertyName: statement.property?.name ?? "",
            propertyAddress: statement.property?.address ?? "",
            year: statement.year,
            periodText: periodText,
            allocationMethodLabel: statement.allocationMethod.label,
            lineItems: items,
            propertyTaxAmount: statement.propertyTaxAmount,
            totalApportionableCosts: statement.totalApportionableCosts,
            nonApportionableTotal: statement.nonApportionableLineItemsTotal,
            reserveFundAccountInfo: statement.reserveFundAccountInfo,
            allocationRows: rows,
            generatedAt: .now
        )
        guard let data = PDFExporter.renderPDF(size: GesamtuebersichtReportDocument.pageSize, content: { document }) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nebenkostenabrechnung \(statement.year) – Gesamtübersicht.pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func saveOverviewPDFAsDocument(title: String, url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let document = Document(title: title, fileName: "\(title).pdf", fileExtension: "pdf", data: data, receiptDate: .now)
        document.property = statement.property
        document.utilityStatement = statement
        modelContext.insert(document)
    }

    /// Erzeugt das druckfertige PDF-Abrechnungsschreiben für einen Mieter, inklusive der
    /// Original-Belege der Hausverwaltung als Anlage (falls welche hinterlegt sind).
    private func pdfData(for row: UtilityAllocationRow) -> Data? {
        guard let property = statement.property else { return nil }
        let apportionableItems = (statement.lineItems ?? [])
            .filter { $0.isApportionable }
            .sorted { $0.costType < $1.costType }
            .map { NebenkostenabrechnungDocument.LineItem(type: $0.costType, amount: $0.amount) }

        guard let letter = PDFExporter.renderPDF(size: NebenkostenabrechnungDocument.pageSize, content: {
            NebenkostenabrechnungDocument(
                propertyName: property.name,
                propertyAddress: property.address,
                year: statement.year,
                periodStart: statement.periodStart,
                periodEnd: statement.periodEnd,
                tenantName: row.tenantName,
                tenantSalutationLine: row.tenantSalutation,
                unitName: row.unitName,
                allocationMethodLabel: statement.allocationMethod.label,
                allocationKeyDetail: row.keyDetail,
                apportionableLineItems: apportionableItems,
                propertyTaxAmount: statement.propertyTaxAmount,
                apportionableTotal: statement.totalApportionableCosts,
                allocatedShare: row.allocatedCost,
                advancesPaid: row.advancesPaid,
                landlordName: property.landlordName,
                landlordEmail: landlordEmail,
                bankAccountHolder: property.bankAccountHolder,
                iban: property.iban,
                bic: property.bic
            )
        }) else { return nil }

        let attachments = (statement.documents ?? []).map { (data: $0.data, fileExtension: $0.fileExtension) }
        guard !attachments.isEmpty else { return letter }
        return PDFExporter.appendingAttachments(attachments, to: letter)
    }

    /// Schreibt das PDF in eine temporäre Datei, damit es per `ShareLink` geteilt werden kann.
    private func pdfTemporaryURL(for row: UtilityAllocationRow) -> URL? {
        guard let data = pdfData(for: row) else { return nil }
        let safeName = "Nebenkostenabrechnung \(statement.year) – \(row.tenantName).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func savePDFAsDocument(title: String, data: Data) {
        let document = Document(title: title, fileName: "\(title).pdf", fileExtension: "pdf", data: data, receiptDate: .now)
        document.property = statement.property
        document.utilityStatement = statement
        modelContext.insert(document)
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Zeitraum", value: periodText)
                LabeledContent("Umlageschlüssel", value: statement.allocationMethod.label)
            }

            if !statement.reserveFundAccountInfo.isEmpty {
                Section("Instandhaltungsrücklagenkonto bei der Hausverwaltung") {
                    Text(statement.reserveFundAccountInfo)
                }
            }

            Section {
                ForEach((statement.lineItems ?? []).sorted(by: { $0.costType < $1.costType })) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.costType)
                            if !item.isApportionable {
                                Text("Nicht umlagefähig")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.statusWarning)
                            }
                            if !item.allocationKeyLabel.isEmpty {
                                Text("Schlüssel lt. Hausverwaltung: \(item.allocationKeyLabel)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(item.amount.asCurrency)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Grundsteuer")
                    Spacer()
                    Text(statement.propertyTaxAmount.asCurrency)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Umlagefähig gesamt (Basis Mieterverteilung)", value: statement.totalApportionableCosts.asCurrency)
                    .font(.headline)
                if statement.nonApportionableLineItemsTotal > 0 {
                    LabeledContent("Nicht umlagefähig (beim Vermieter)", value: statement.nonApportionableLineItemsTotal.asCurrency)
                        .foregroundStyle(Theme.statusWarning)
                }
            } header: {
                Text("Kostenarten lt. Hausverwaltung")
            } footer: {
                Text("Die Grundsteuer wird hier eingegeben, da sie meist nicht im Schreiben der Hausverwaltung steht, aber umlagefähig ist. Nicht umlagefähige Kosten mindern den freien Cashflow der Immobilie, erscheinen aber nicht im Schreiben an die Mieter.")
            }

            Section {
                ForEach(statement.documents ?? []) { document in
                    Text(document.title.isEmpty ? document.fileName : document.title)
                }
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Abrechnung der Hausverwaltung anhängen", systemImage: "paperclip")
                }
            } header: {
                Text("Original-Belege")
            } footer: {
                Text("Werden als Anlage an jedes PDF-Abrechnungsschreiben angehängt.")
            }

            if allocationRows.isEmpty {
                Section("Verteilung auf Mieter") {
                    Text("Keine Zuordnung möglich – stelle sicher, dass Einheiten die für den gewählten Umlageschlüssel nötigen Werte (z.B. Wohnfläche, Miteigentumsanteil oder Personenzahl) und laufende Mietverhältnisse im Zeitraum \(periodText) haben.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(allocationRows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(row.tenantName) · \(row.unitName)")
                                    .font(.headline)
                                Spacer()
                                Menu {
                                    Button("Nebenkostenabrechnung erstellen") {
                                        pdfPreviewURL = pdfTemporaryURL(for: row)
                                    }
                                    if let url = pdfTemporaryURL(for: row) {
                                        ShareLink("Als PDF teilen", item: url)
                                    }
                                    Button("Als PDF ablegen") {
                                        if let data = pdfData(for: row) {
                                            savePDFAsDocument(title: "Nebenkostenabrechnung \(statement.year) – \(row.tenantName)", data: data)
                                        }
                                    }
                                    ShareLink("Als Text teilen", item: letterText(for: row))
                                    Button("Als Text ablegen") {
                                        saveAsDocument(title: "Nebenkostenabrechnung \(statement.year) – \(row.tenantName)", text: letterText(for: row))
                                    }
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderless)
                            }
                            HStack {
                                Text("Anteil: \(row.allocatedCost.asCurrency)")
                                Spacer()
                                Text("Vorauszahlung: \(row.advancesPaid.asCurrency)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text(row.difference >= 0 ? "Nachzahlung: \(row.difference.asCurrency)" : "Guthaben: \(abs(row.difference).asCurrency)")
                                .font(.subheadline.bold())
                                .foregroundStyle(row.difference >= 0 ? Theme.statusCritical : Theme.statusGood)

                            Button {
                                toggleDispatch(for: row.tenancy)
                            } label: {
                                if let sent = dispatch(for: row.tenancy) {
                                    Label("Verschickt am \(sent.sentDate.asShortDate)", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.statusGood)
                                } else {
                                    Label("Noch nicht verschickt", systemImage: "circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .padding(.top, 2)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Verteilung auf Mieter (\(statement.allocationMethod.label.lowercased())) – \((statement.dispatches ?? []).count)/\(allocationRows.count) verschickt")
                } footer: {
                    Text("Anteilig nach Tagen des Mietverhältnisses im Abrechnungszeitraum. Über das Teilen-Symbol lässt sich je Mieter ein fertiges PDF-Abrechnungsschreiben (inkl. Original-Belegen als Anlage) teilen oder ablegen. Der Haken „Verschickt“ markiert nur, dass das Schreiben versendet wurde – unabhängig davon, wie oft das PDF erzeugt wird; Tippen setzt bzw. entfernt das heutige Datum.")
                }

                Section {
                    Button {
                        pdfPreviewURL = overviewPDFURL()
                    } label: {
                        Label("Gesamtübersicht als PDF anzeigen", systemImage: "doc.text.magnifyingglass")
                    }
                    if let url = overviewPDFURL() {
                        ShareLink("Gesamtübersicht als PDF teilen", item: url)
                        Button {
                            saveOverviewPDFAsDocument(title: "Nebenkostenabrechnung \(statement.year) – Gesamtübersicht", url: url)
                        } label: {
                            Label("Gesamtübersicht als PDF ablegen", systemImage: "tray.and.arrow.down")
                        }
                    }
                    Button {
                        pdfPreviewURL = overviewXLSXURL()
                    } label: {
                        Label("Gesamtübersicht als Excel-Tabelle anzeigen", systemImage: "tablecells")
                    }
                    if let url = overviewXLSXURL() {
                        ShareLink("Gesamtübersicht als Excel-Tabelle teilen (.xlsx)", item: url)
                        Button {
                            saveXLSXAsDocument(title: "Nebenkostenabrechnung \(statement.year) – Übersicht", url: url)
                        } label: {
                            Label("Gesamtübersicht als Excel-Dokument ablegen", systemImage: "tray.and.arrow.down")
                        }
                    }
                } footer: {
                    Text("Die interne Gesamtübersicht nennt – anders als die Schreiben an die Mieter – auch die nicht umlagefähigen Kosten und die komplette Mieterverteilung, zur eigenen Kontrolle.")
                }
            }
        }
        .themedScrollBackground()
        .navigationTitle("Nebenkosten \(String(statement.year))")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            UtilityStatementEditView(property: statement.property ?? Property(), statement: statement)
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf, .image, .data]) { result in
            handleFileImport(result)
        }
        .quickLookPreview($pdfPreviewURL)
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let document = Document(
            title: url.deletingPathExtension().lastPathComponent,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            data: data,
            receiptDate: .now
        )
        document.property = statement.property
        document.utilityStatement = statement
        modelContext.insert(document)
    }
}

#Preview {
    let context = PreviewData.container.mainContext
    let statement = (try? context.fetch(FetchDescriptor<UtilityStatement>()))?.first ?? UtilityStatement()
    return NavigationStack {
        UtilityStatementDetailView(statement: statement)
    }
    .modelContainer(PreviewData.container)
}
