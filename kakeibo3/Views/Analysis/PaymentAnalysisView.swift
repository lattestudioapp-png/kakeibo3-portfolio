import SwiftUI

struct PaymentAnalysisView: View {
    let allExpenses: [ExpenseData]
    let items: [AnalysisCategorySummary]
    let comparisonLabel: String
    let dateRange: AnalysisDateRange
    var showsCreditCardDue: Bool = true

    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var allPaymentSettingsRaw: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }
    @StateObject private var bankAccountDataObserver = BankAccountDataSync.observer()
    private var allBankAccountsRaw: [BankAccountData] { bankAccountDataObserver.items }
    private var allPaymentSettings: [PaymentMethodSettingData] {
        allPaymentSettingsRaw.filter { $0.bookId == currentBookId }
    }
    private var allBankAccounts: [BankAccountData] {
        allBankAccountsRaw.filter { $0.bookId == currentBookId }
    }

    @State private var chartAngle: Double? = nil
    @State private var showsComparison: Bool = false

    // MARK: - Computed

    private var itemsVersionKey: String {
        "\(items.count)-\(items.reduce(0) { $0 + $1.totalAmount })"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            AnalysisDonutChartCard(
                title: "支払い割合",
                items: items,
                selectedAngle: $chartAngle
            )
            .padding(.bottom, 24)

            if showsCreditCardDue {
                CreditCardDueCard(
                    settings: allPaymentSettings,
                    allExpenses: allExpenses,
                    bankAccounts: allBankAccounts,
                    selectedDate: dateRange.start
                )
                .padding(.bottom, 24)
            }

            AnalysisCategoryListCard(
                title: "支払い別",
                items: items,
                showsMonthOverMonth: $showsComparison,
                comparisonLabel: comparisonLabel,
                emptyMessage: "データがありません",
                mode: .paymentMethod,
                dateRange: dateRange
            )
        }
        .onAppear { chartAngle = nil }
        .onChange(of: itemsVersionKey) { _, _ in chartAngle = nil }
    }
}
