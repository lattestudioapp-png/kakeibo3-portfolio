import Foundation
import StoreKit
import Combine

// MARK: - 買い切り課金（広告削除）の購入状態を管理するストア
//
// StoreKit 2 を使い、非消耗型（non-consumable）の商品を扱う。
// Transaction.currentEntitlements は失効済み・返金済みの購入を
// 自動的に除外するため、含まれているかどうかだけで判定できる。
//
// 実機・シミュレータでのテストには、Xcode の StoreKit Configuration File に
// productId と同じ商品IDを登録し、スキームの
// 「Run > Options > StoreKit Configuration」で選択しておく必要がある
// （App Store Connect 側の商品作成が済んでいなくてもローカルでテストできる）。
//
// iCloud同期は公開後に別途実装予定のため、現時点では扱わない。

@MainActor
final class EntitlementStore: ObservableObject {
    static let shared = EntitlementStore()

    /// 広告削除（買い切り・非消耗型）商品ID。App Store Connect 側でもこのIDで商品を作成する。
    static let removeAdsProductId = "com.kusumoto.kakeibo3.removeads"

    @Published private(set) var hasRemoveAds: Bool = false
    @Published private(set) var removeAdsProduct: Product? = nil
    @Published private(set) var isLoadingProducts = false
    @Published var errorMessage: String? = nil

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - 商品情報の取得

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let products = try await Product.products(for: [Self.removeAdsProductId])
            removeAdsProduct = products.first { $0.id == Self.removeAdsProductId }
        } catch {
            removeAdsProduct = nil
        }
    }

    // MARK: - 購入済み状態の判定

    func refreshEntitlements() async {
        var hasRemoveAds = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            if transaction.productID == Self.removeAdsProductId { hasRemoveAds = true }
        }
        self.hasRemoveAds = hasRemoveAds
    }

    // MARK: - 購入

    func purchaseRemoveAds() async {
        await purchase(product: removeAdsProduct)
    }

    private func purchase(product: Product?) async {
        errorMessage = nil
        guard let product else {
            errorMessage = "商品情報を取得できませんでした。時間をおいて再度お試しください。"
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(transactionResult: verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "購入に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - 購入の復元

    func restorePurchases() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = "復元に失敗しました: \(error.localizedDescription)"
            return
        }
        await refreshEntitlements()
        if !hasRemoveAds {
            errorMessage = "復元できる購入が見つかりませんでした。"
        }
    }

    // MARK: - デバッグ用（開発用画面から購入済み表示を確認するためだけの切り替え）
    //
    // StoreKit を経由せずフラグを直接切り替える。DEBUG ビルドにのみ含まれ、
    // リリースビルドには一切コンパイルされない。

    #if DEBUG
    func debugSetRemoveAds(_ value: Bool) {
        hasRemoveAds = value
    }
    #endif

    // MARK: - トランザクション処理共通

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else { return }
        guard transaction.revocationDate == nil else {
            await transaction.finish()
            return
        }
        if transaction.productID == Self.removeAdsProductId { hasRemoveAds = true }
        await transaction.finish()
    }
}
