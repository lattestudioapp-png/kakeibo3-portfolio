import Foundation

// MARK: - 振替（移動元/移動先）の参加者リスト構築
//
// TransferFormView / TransferEditView で重複していた
// 「銀行口座 + 支払い方法（クレカ除く）+ 受け取り方法」の統合ロジックを共通化する。

enum TransferParticipantBuilder {
    static func build(
        bankAccounts: [BankAccountData],
        paymentMethods: [PaymentMethodSettingData],
        receiveMethods: [ReceiveMethodData]
    ) -> [TransferParticipant] {
        typealias Entry = (participant: TransferParticipant, sortOrder: Int, createdAt: Date)

        let banks: [Entry] = bankAccounts
            .filter { $0.isActive }
            .map { b in
                (
                    participant: TransferParticipant(
                        id: b.id, name: b.accountName, type: TransferAccountType.bank.rawValue, isLocked: b.isLocked, colorHex: b.colorHex
                    ),
                    sortOrder: b.sortOrder, createdAt: b.createdAt
                )
            }
        // isActiveだけでは「支払い一覧・受け取り一覧のどちらからも外されているが、
        // レコード自体は残っている（showInInputPicker/useForReceiveが共にfalse）」項目を
        // 拾ってしまう。支払い方法設定・受け取り方法設定の一覧と同じ条件（いずれかの用途に
        // 使われているか）も合わせて見ることで、両方の一覧から外した項目は振替候補にも出さない。
        let payments: [Entry] = paymentMethods
            .filter {
                $0.isActive && $0.type != PaymentMethodType.creditCard.rawValue
                    && ($0.showInInputPicker || $0.useForReceive)
            }
            .map { p in
                (
                    participant: TransferParticipant(
                        id: p.id, name: p.methodName, type: TransferAccountType.paymentMethod.rawValue, isLocked: p.isLocked, colorHex: p.colorHex
                    ),
                    sortOrder: p.sortOrder, createdAt: p.createdAt
                )
            }

        // 孤立したReceiveMethodData対策：同じ帳簿・同じ名前の支払い方法がかつて存在し、
        // それが今は無効化されている（削除済み）場合、対応する資産/支払い方法が
        // 既に無くなったとみなし、その受け取り方法は振替候補に出さない
        // （例：「現金」の支払い方法を削除した後もReceiveMethodData側の「現金」が
        // 残るケース。DataInitializerService.reconcileReceiveMethodsForBook参照）。
        let deletedPaymentNames = Set(
            paymentMethods
                .filter { !$0.isActive }
                .map { $0.methodName.trimmingCharacters(in: .whitespacesAndNewlines) }
        )

        // ReceiveMethodDataは色を持たないため、同じ帳簿・同名のPaymentMethodSettingDataの色を逆引きする
        // （「現金」の支払い方法と受け取り方法は同じ財布を指す別レコードのため、同じ色で表示する）。
        var colorByPaymentName: [String: String] = [:]
        for p in paymentMethods {
            let key = p.methodName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let color = p.colorHex { colorByPaymentName[key] = color }
        }

        // ReceiveMethodData は無料版上限のロック対象に含まれていないため常に isLocked=false
        let receives: [Entry] = receiveMethods
            .filter {
                $0.isActive
                    && !deletedPaymentNames.contains($0.methodName.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .map { m in
                (
                    participant: TransferParticipant(
                        id: m.id, name: m.methodName, type: TransferAccountType.receive.rawValue, isLocked: false,
                        colorHex: colorByPaymentName[m.methodName.trimmingCharacters(in: .whitespacesAndNewlines)]
                    ),
                    sortOrder: m.sortOrder, createdAt: m.createdAt
                )
            }
        // 有効（未ロック）なものを先に、ロック中のものは自動で下にまとめる
        let sorted = (banks + payments + receives)
            .sorted {
                $0.participant.isLocked != $1.participant.isLocked ? !$0.participant.isLocked
                    : ($0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder)
            }

        // 名前（前後空白trim）が重複している場合、並び順が先のもの（最も古い/優先度が高いもの）だけ残す。
        // 「現金」のように支払い方法と受け取り方法の両方に同名レコードが存在するケース
        // （DataInitializerService参照。両者は同じ財布を指す別レコードで、統合移行が
        // 全帳簿共通の一度きりフラグのため新しい帳簿では効かないことがある）を含め、
        // 振替候補としては種別をまたいでも同名なら同一の移動元/移動先とみなして1つにまとめる。
        var seenNames = Set<String>()
        var deduped: [TransferParticipant] = []
        for entry in sorted {
            let key = entry.participant.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !seenNames.contains(key) else { continue }
            seenNames.insert(key)
            deduped.append(entry.participant)
        }
        return deduped
    }
}
