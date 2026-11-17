import SwiftUI
import Combine

struct MainView: View {
    @EnvironmentObject private var photoDialog: PhotoDialogCoordinator
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var entitlementStore: EntitlementStore

    @State private var selectedTab: AppTab = .input
    @State private var inputInitialDate = Date()
    @State private var inputInitialType = "支出"
    @State private var isCalculatorKeyboardPresented = false
    @State private var isCalendarEditingPresented = false
    @State private var analysisJumpTarget: AnalysisJumpTarget? = nil

    // MARK: - タブ再タップ時のリセット用トリガー

    @State private var inputResetTrigger = 0
    @State private var calendarResetTrigger = 0
    @State private var analysisResetTrigger = 0
    @State private var budgetResetTrigger = 0
    @State private var otherResetTrigger = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            currentScreen
                .ignoresSafeArea(.keyboard, edges: .bottom)

            if !isCalculatorKeyboardPresented && !isCalendarEditingPresented {
                VStack(spacing: AppLayout.adBannerSpacing) {
                    BottomNavigationView(selectedTab: $selectedTab, onReselectTab: handleReselect)
                    if !entitlementStore.hasRemoveAds {
                        AdBannerView(adUnitID: AdBannerView.testBannerAdUnitID)
                            .frame(height: AppLayout.adBannerHeight)
                            .background(Color.white)
                    }
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .overlay {
            if photoDialog.isPresented {
                PhotoActionSheetView(
                    isPresented: $photoDialog.isPresented,
                    hasPhoto: photoDialog.hasPhoto,
                    onTakePhoto: photoDialog.onTakePhoto,
                    onSelectLibrary: photoDialog.onSelectLibrary,
                    onDeletePhoto: photoDialog.onDeletePhoto
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: photoDialog.isPresented)
        .background(themeManager.backgroundColor)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: selectedTab) { oldTab, newTab in
            isCalculatorKeyboardPresented = false
            isCalendarEditingPresented = false
            // カレンダー以外からの戻りは日付を今日にリセット（カレンダー→入力の日付引き継ぎを保護）
            if newTab == .input && oldTab != .calendar {
                inputInitialDate = Date()
                inputInitialType = "支出"
            }
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch selectedTab {
        case .input:
            InputView(
                selectedTab: $selectedTab,
                initialDate: $inputInitialDate,
                initialType: $inputInitialType,
                isCalculatorKeyboardPresented: $isCalculatorKeyboardPresented,
                resetTrigger: inputResetTrigger
            )

        case .calendar:
            CalendarView(
                selectedTab: $selectedTab,
                inputInitialDate: $inputInitialDate,
                inputInitialType: $inputInitialType,
                isEditingTransactionPresented: $isCalendarEditingPresented,
                analysisJumpTarget: $analysisJumpTarget,
                resetTrigger: calendarResetTrigger
            )

        case .analysis:
            AnalysisView(analysisJumpTarget: $analysisJumpTarget, resetTrigger: analysisResetTrigger)

        case .budget:
            BudgetView(resetTrigger: budgetResetTrigger)

        case .other:
            OtherView(resetTrigger: otherResetTrigger)
        }
    }

    // MARK: - タブ再タップ時のリセット処理

    private func handleReselect(_ tab: AppTab) {
        switch tab {
        case .input:    inputResetTrigger += 1
        case .calendar: calendarResetTrigger += 1
        case .analysis: analysisResetTrigger += 1
        case .budget:   budgetResetTrigger += 1
        case .other:    otherResetTrigger += 1
        }
    }
}
