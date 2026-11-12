import XCTest
import SwiftData
@testable import Mietverwaltung

/// Lösch-Regeln zwischen Modellen: Verweise dürfen nach dem Löschen des Ziels nicht ins Leere zeigen.
@MainActor
final class ModelIntegrityTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = AppSchema.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = container.mainContext
    }

    func testDeletingInvitationDocumentClearsMeetingReference() throws {
        let document = Document(title: "Einladung", fileName: "einladung.pdf", fileExtension: "pdf")
        let meeting = OwnersMeetingEvent()
        context.insert(document)
        context.insert(meeting)
        meeting.invitationDocument = document
        try context.save()

        context.delete(document)
        try context.save()

        XCTAssertNil(meeting.invitationDocument)
    }

    func testDeletingExpenseRemovesItsThresholdAssessment() throws {
        let thresholdCase = ThreeYearThresholdCase()
        let expense = Expense(amount: 1_000, taxTreatment: .maintenanceExpense)
        context.insert(thresholdCase)
        context.insert(expense)
        let assessment = ThresholdExpenseAssessment()
        assessment.expense = expense
        assessment.thresholdCase = thresholdCase
        context.insert(assessment)
        try context.save()

        context.delete(expense)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ThresholdExpenseAssessment>()), 0)
        XCTAssertTrue((thresholdCase.assessments ?? []).isEmpty)
    }

    func testDeletingCapitalizedAssetRevertsSourceExpenses() throws {
        let property = Property(name: "Haus")
        context.insert(property)
        let expenses = [Expense(amount: 4_000, taxTreatment: .maintenanceExpense), Expense(amount: 6_000, taxTreatment: .maintenanceExpense)]
        expenses.forEach { $0.property = property; context.insert($0) }
        let decision = try XCTUnwrap(CapitalizationDecision.create(from: expenses, property: property, thresholdCase: nil, reason: "Dach", context: context).first)
        let asset = try XCTUnwrap(decision.resultingAsset)
        try context.save()
        XCTAssertTrue(expenses.allSatisfy { $0.taxTreatment == .capitalized })
        XCTAssertTrue(asset.deletionWarning.contains("2 Ausgabe(n)"))

        DepreciableAsset.delete(asset, context: context)
        try context.save()

        XCTAssertTrue(expenses.allSatisfy { $0.taxTreatment == .maintenanceExpense && $0.capitalizationDecision == nil })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CapitalizationDecision>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DepreciableAsset>()), 0)
    }

    func testEnsureAssessmentsRemovesOrphans() throws {
        let thresholdCase = ThreeYearThresholdCase()
        context.insert(thresholdCase)
        let orphan = ThresholdExpenseAssessment()
        orphan.thresholdCase = thresholdCase
        context.insert(orphan)
        try context.save()

        thresholdCase.ensureAssessments(context: context)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ThresholdExpenseAssessment>()), 0)
    }

    func testNetAmountIgnoresImpossibleVatRate() {
        let expense = Expense(amount: 119)
        expense.vatRatePercent = -100
        XCTAssertNil(expense.netAmount)
        expense.vatRatePercent = 19
        XCTAssertEqual(expense.netAmount ?? 0, 100, accuracy: 0.001)
    }
}
