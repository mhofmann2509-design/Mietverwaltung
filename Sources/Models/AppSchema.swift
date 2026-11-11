import SwiftData

/// Die einzige Liste aller persistierten Modelltypen – von App, Previews und Tests gemeinsam
/// genutzt, damit ein neuer `@Model`-Typ nicht an einer von mehreren Kopien vergessen wird.
enum AppSchema {
    static let schema = Schema([
        Property.self, Unit.self, Tenant.self, Tenancy.self, RentStep.self, RentPayment.self,
        Expense.self, Document.self, DocumentFolder.self, DepreciableAsset.self,
        UtilityStatement.self, UtilityCostLineItem.self, UtilityStatementDispatch.self,
        Landlord.self, RemainingUsefulLifeAppraisal.self,
        WirtschaftsplanStatement.self, WirtschaftsplanLineItem.self,
        TrackedYear.self, TaxChecklistItem.self, TaxFilingStatus.self,
        ThreeYearThresholdCase.self, ThresholdExpenseAssessment.self, CapitalizationDecision.self,
        TravelExpense.self, HomeOfficeEntry.self, OwnersMeetingEvent.self
    ])
}
