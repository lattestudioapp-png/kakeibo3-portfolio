import SwiftUI
import os

private let creditCardSettingLogger = Logger(subsystem: "com.kusumoto.kakeibo3", category: "CreditCardSettingView")

struct CreditCardSettingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bookDataObserver = BookDataSync.observer()
    private var bookDataList: [BookData] { bookDataObserver.items }
    @AppStorage(BookSettings.storageKey) private var selectedBookIdString: String = ""

    private var currentBookId: UUID? {
        BookResolver.resolveCurrentBook(from: bookDataList, selectedIdString: selectedBookIdString)?.id
    }

    @StateObject private var paymentMethodSettingDataObserver = PaymentMethodSettingDataSync.observer()
    private var allSettings: [PaymentMethodSettingData] { paymentMethodSettingDataObserver.items }

    @AppStorage(CreditCardAssetReflectionTiming.storageKey)
    private var storedTiming: String = CreditCardAssetReflectionTiming.defaultValue.rawValue

    // 保存済みの設定値（「現在：」表示に使う）
    private var savedTiming: CreditCardAssetReflectionTiming {
        CreditCardAssetReflectionTiming(rawValue: storedTiming) ?? .usageDate
    }

    // 編集中の選択値（ラジオボタンの選択状態）
    @State private var selectedTiming: CreditCardAssetReflectionTiming = CreditCardAssetReflectionTiming.defaultValue

    @State private var editingCard: PaymentMethodSettingData? = nil
    @State private var isAdding = false

    private var creditCards: [PaymentMethodSettingData] {
        allSettings
            .filter { $0.type == PaymentMethodType.creditCard.rawValue && $0.isActive && $0.bookId == currentBookId }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        // cardsをbody内で1回だけ計算して使い回す（ForEach・空判定・ヘッダー表示のそれぞれで
        // 毎回フィルタ・ソートし直さないように）
        let cards = creditCards
        let _ = creditCardSettingLogger.debug("body evaluated: \(cards.count) cards")

        NavigationStack {
            List {
                // MARK: - 総資産への反映タイミング設定
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("カード利用の資産反映")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.75))
                            Text("現在：\(savedTiming.displayName)")
                                .font(AppFonts.caption)
                                .foregroundStyle(AppColors.main)
                        }

                        Text(selectedTiming.description)
                            .font(AppFonts.caption)
                            .foregroundStyle(Color.black.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        ForEach(CreditCardAssetReflectionTiming.allCases, id: \.rawValue) { timing in
                            Button {
                                selectedTiming = timing
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedTiming == timing
                                          ? "largecircle.fill.circle"
                                          : "circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(selectedTiming == timing
                                                         ? AppColors.main
                                                         : Color.black.opacity(0.25))
                                    Text(timing.displayName)
                                        .font(.system(size: 14, weight: selectedTiming == timing ? .semibold : .regular))
                                        .foregroundStyle(Color.black.opacity(0.8))
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        if selectedTiming != savedTiming {
                            Button {
                                storedTiming = selectedTiming.rawValue
                                // 計上日そのものが変わるため、全期間のスナップショットを作り直す
                                SnapshotUpdateService.handle(.fullRebuildRequested)
                            } label: {
                                Text("適用する")
                                    .font(AppFonts.button)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(AppColors.main)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("総資産への反映タイミング")
                }

                // MARK: - 登録済みクレジットカード
                Section {
                    if cards.isEmpty {
                        Text("登録されていません")
                            .font(AppFonts.body)
                            .foregroundStyle(Color.black.opacity(0.35))
                    } else {
                        ForEach(cards) { card in
                            CreditCardRow(card: card, onTapRow: { editingCard = card })
                        }
                    }
                    Button {
                        isAdding = true
                    } label: {
                        Label("クレジットカードを追加", systemImage: "plus")
                            .font(AppFonts.button)
                            .foregroundStyle(AppColors.main)
                    }
                } header: {
                    Text("登録済みクレジットカード")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.sheetBackground)
            .navigationTitle("クレジットカード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
        .onAppear {
            selectedTiming = savedTiming
        }
        .sheet(item: $editingCard) { card in
            CreditCardEditView(existing: card)
        }
        .sheet(isPresented: $isAdding) {
            CreditCardEditView(existing: nil)
        }
    }
}

// MARK: - カード1行分（専用View。対象カードと必要な値だけを受け取り、リスト全体の再計算に巻き込まれない）

private struct CreditCardRow: View {
    let card: PaymentMethodSettingData
    let onTapRow: () -> Void

    var body: some View {
        let _ = creditCardSettingLogger.debug("row evaluated: \(card.methodName)")

        Button(action: onTapRow) {
            HStack {
                Circle()
                    .fill(ColorHexConverter.color(from: card.colorHex))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.methodName)
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.8))
                    Text(subtitle)
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.45))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.4))
            }
            .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let closing = card.closingDay {
            parts.append("締め日：\(closing == 31 ? "月末" : "\(closing)日")")
        }
        if let withdrawal = card.withdrawalDay {
            parts.append("引き落とし：翌月\(withdrawal == 31 ? "末" : "\(withdrawal)日")")
        }
        return parts.isEmpty ? "締め日・引き落とし日 未設定" : parts.joined(separator: "　")
    }
}
