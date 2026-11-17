import Foundation

/// 初回インストール時のデフォルトデータ作成を担当するサービス。
/// 各テーブルが空の場合のみ初期データを投入する（重複防止）。
struct DataInitializerService {

    // MARK: - 支払い方法の初期化

    /// 指定した帳簿にPaymentMethodSettingDataが1件もなければ「現金」を追加する。
    static func createDefaultPaymentMethodsIfNeeded(
        existing: [PaymentMethodSettingData],
        bookId: UUID
    ) {
        guard !existing.contains(where: { $0.bookId == bookId }) else { return }
        var cash = PaymentMethodSettingData(
            methodName: "現金",
            type: PaymentMethodType.cash.rawValue,
            sortOrder: 0
        )
        cash.showInInputPicker = true
        cash.useForReceive = true
        cash.isAsset = true
        cash.bookId = bookId
        PaymentMethodSettingDataSync.insert(cash)
    }

    // MARK: - 現金 type 補正

    /// 以前は「現金」を type=other で作成していたため、その名残の
    /// レコードを type=cash に補正する（現金専用の設定画面から見えるようにするため）。
    static func migrateCashTypeIfNeeded(
        paymentMethods: [PaymentMethodSettingData]
    ) {
        let needsFix = paymentMethods.filter {
            $0.methodName == "現金" && $0.type == PaymentMethodType.other.rawValue
        }
        guard !needsFix.isEmpty else { return }
        for method in needsFix {
            var updated = method
            updated.type = PaymentMethodType.cash.rawValue
            PaymentMethodSettingDataSync.update(updated)
        }
    }

    // MARK: - 受け取り方法の初期化

    /// 指定した帳簿にReceiveMethodDataが1件もなければ「現金」を追加する。
    static func createDefaultReceiveMethodsIfNeeded(
        existing: [ReceiveMethodData],
        bookId: UUID
    ) {
        guard !existing.contains(where: { $0.bookId == bookId }) else { return }
        var cash = ReceiveMethodData(methodName: "現金", sortOrder: 0)
        cash.bookId = bookId
        ReceiveMethodDataSync.insert(cash)
    }

    // MARK: - ReceiveMethodData → PaymentMethodSettingData 移行

    /// ReceiveMethodData を PaymentMethodSettingData(useForReceive=true) に統合する。
    /// 名前が一致するエントリがあれば useForReceive=true を設定、なければ新規作成。
    /// 旧エントリは isActive=false に設定して無効化する。
    static func migrateReceiveMethodsIfNeeded(
        receiveMethodSettings: [ReceiveMethodData],
        paymentMethodSettings: [PaymentMethodSettingData]
    ) {
        guard !UserDefaults.standard.bool(forKey: "receiveMethodsMigratedV1") else { return }
        reconcileReceiveMethods(
            receiveMethodSettings: receiveMethodSettings,
            paymentMethodSettings: paymentMethodSettings
        )
        UserDefaults.standard.set(true, forKey: "receiveMethodsMigratedV1")
    }

    // MARK: - 帳簿単位の再整合（データリセット・新規帳簿作成直後などに使う）
    //
    // migrateReceiveMethodsIfNeeded はアプリ全体で一度きりのUserDefaultsフラグで
    // ガードされているため、初回移行が済んだ後に作成・リセットされた帳簿には
    // 二度と効かない。データリセット直後・新規帳簿作成直後は「現金」等の初期データを
    // 支払い方法・受け取り方法の両方に作り直した直後なので、フラグに関係なくこの帳簿
    // ぶんだけ即座に再整合させる（対象が無ければ何もしない、常に安全に呼べる処理）。
    static func reconcileReceiveMethodsForBook(bookId: UUID) {
        let receiveMethodSettings = ReceiveMethodDataSync.fetchAll(bookId: bookId)
        let paymentMethodSettings = PaymentMethodSettingDataSync.fetchAll(bookId: bookId)
        reconcileReceiveMethods(
            receiveMethodSettings: receiveMethodSettings,
            paymentMethodSettings: paymentMethodSettings
        )
    }

    /// ReceiveMethodData(isActive) のうち、同名・同帳簿のPaymentMethodSettingDataが既にあれば
    /// そちらへ useForReceive=true を設定して一本化し、古いReceiveMethodDataは無効化する。
    /// 一致するものが無ければ新しいPaymentMethodSettingData(useForReceive=true)を作る。
    /// UserDefaultsのフラグは見ない（呼び出し側の責任）。何度呼んでも安全（冪等）。
    private static func reconcileReceiveMethods(
        receiveMethodSettings: [ReceiveMethodData],
        paymentMethodSettings: [PaymentMethodSettingData]
    ) {
        for receiveMethod in receiveMethodSettings where receiveMethod.isActive {
            if let match = paymentMethodSettings.first(where: {
                $0.methodName == receiveMethod.methodName
                    && $0.bookId == receiveMethod.bookId
                    && $0.type != PaymentMethodType.creditCard.rawValue
                    && $0.isActive
            }) {
                var updatedMatch = match
                updatedMatch.useForReceive = true
                PaymentMethodSettingDataSync.update(updatedMatch)
            } else {
                var newMethod = PaymentMethodSettingData(
                    methodName: receiveMethod.methodName,
                    type: PaymentMethodType.other.rawValue,
                    sortOrder: receiveMethod.sortOrder
                )
                newMethod.showInInputPicker = false
                newMethod.useForReceive = true
                newMethod.bookId = receiveMethod.bookId
                PaymentMethodSettingDataSync.insert(newMethod)
            }
            var updated = receiveMethod
            updated.isActive = false
            ReceiveMethodDataSync.update(updated)
        }
    }

}
