import SwiftUI

// MARK: - 振替入力ページ（支出/収入と同じ InputFormLayout を使い、見た目を統一する）

struct TransferInputPageView: View {

    // MARK: - Props

    @Binding var date: Date
    @Binding var isDatePickerPresented: Bool
    @Binding var fromId: UUID?
    @Binding var toId: UUID?
    @Binding var amountText: String
    @Binding var memo: String
    @Binding var memoPhotos: [MemoPhoto]
    let isAddingPhoto: Bool

    let participants: [TransferParticipant]
    let recentTransfers: [TransferData]

    var focusedField: FocusState<InputFocusedField?>.Binding
    @Binding var isCalculatorKeyboardPresented: Bool

    let layout: InputFormLayout
    var onCameraButtonTap: (() -> Void)? = nil
    var onSelectHistoryTransfer: ((TransferData) -> Void)? = nil
    let onSave: () -> Void

    // MARK: - 内部

    @State private var fullScreenPhoto: MemoPhoto? = nil

    // 設定 > 入力 > 「カメラマークの表示」（支出/収入と同じ設定・同じ表示ルールにする）
    @AppStorage(MemoCameraIconSettings.storageKey) private var showsCameraIcon: Bool = MemoCameraIconSettings.defaultValue

    // ON: 写真が1枚もない間は写真追加エリアを隠す / OFF: 常に表示する
    private var showsPhotoThumbnailArea: Bool {
        showsCameraIcon ? !memoPhotos.isEmpty : true
    }

    private func participant(for id: UUID?) -> TransferParticipant? {
        guard let id else { return nil }
        return participants.first(where: { $0.id == id })
    }

    // MARK: - body

    var body: some View {
        VStack(spacing: 0) {
            InputDateAreaView(
                date: $date,
                isDatePickerPresented: $isDatePickerPresented,
                layout: layout
            )

            participantRow(label: "移動元", selectedId: $fromId)
                .overlay(alignment: .top) { ThinBorderView(layout: layout) }

            participantRow(label: "移動先", selectedId: $toId)
                .overlay(alignment: .top) { ThinBorderView(layout: layout) }

            MemoInputAreaView(
                memo: $memo,
                memoPhotos: $memoPhotos,
                focusedField: focusedField,
                isCalculatorKeyboardPresented: $isCalculatorKeyboardPresented,
                onCameraButtonTap: onCameraButtonTap ?? {},
                showsCameraIcon: showsCameraIcon,
                focusId: "transfer",
                layout: layout
            )

            // 写真サムネイル一覧 / 追加ボタン / ローディング表示
            // 設定ONの場合は写真が1枚もない間はエリアごと隠す。OFFの場合は常に表示する。
            if showsPhotoThumbnailArea {
                photoThumbnailArea
            }

            AmountInputAreaView(
                amountText: $amountText,
                isCalculatorKeyboardPresented: $isCalculatorKeyboardPresented,
                focusedField: focusedField,
                layout: layout
            )

            transferHistoryArea

            Spacer(minLength: 0)

            SaveButtonAreaView(layout: layout, onSave: onSave)

            Color.clear
                .frame(height: layout.bottomNavigationSpacerHeight)
        }
    }

    // MARK: - 移動元 / 移動先

    private func participantRow(label: String, selectedId: Binding<UUID?>) -> some View {
        HStack {
            Text(label)
                .font(layout.rowTitleFont)
                .foregroundStyle(Color.black)

            Spacer()

            if participants.isEmpty {
                Text("振替に使用できる項目がありません")
                    .font(AppFonts.caption)
                    .foregroundStyle(Color.black.opacity(0.35))
            } else {
                let selected = participant(for: selectedId.wrappedValue)
                Menu {
                    ForEach(participants) { p in
                        Button {
                            selectedId.wrappedValue = p.id
                        } label: {
                            if p.isLocked {
                                Label(p.name, systemImage: "lock.fill")
                            } else {
                                Text(p.name)
                            }
                        }
                        .disabled(p.isLocked)
                    }
                } label: {
                    Text(selected?.name ?? "未選択")
                        .font(layout.smallInputTextFont)
                        .foregroundStyle(selected == nil ? Color.black.opacity(0.4) : layout.mainColor)
                        .frame(width: layout.smallInputWidth, height: layout.smallInputHeight)
                        .background(layout.rowBackgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: layout.smallInputCornerRadius)
                                .stroke(layout.lineColor, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: layout.smallInputCornerRadius))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, layout.rowHorizontalPadding)
        .frame(height: layout.normalRowHeight)
        .background(layout.rowBackgroundColor)
    }

    // MARK: - サムネイルエリア

    private var photoThumbnailArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(memoPhotos) { photo in
                    thumbnailCell(for: photo)
                }
                if isAddingPhoto {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.12))
                            .frame(width: 75, height: 75)
                        ProgressView()
                    }
                } else {
                    addPhotoTile
                }
            }
            .padding(.horizontal, layout.memoHorizontalPadding)
            .padding(.vertical, 10)
        }
        .frame(height: 95)
        .background(Color.white)
        .background {
            // 写真が無い場合は矩形を報告せず、従来通りページ切り替えスワイプを優先させる
            GeometryReader { geometry in
                Color.clear.preference(
                    key: PhotoAreaFramePreferenceKey.self,
                    value: memoPhotos.isEmpty ? [] : [geometry.frame(in: .global)]
                )
            }
        }
        .fullScreenCover(item: $fullScreenPhoto) { photo in
            fullScreenView(for: photo)
        }
    }

    // MARK: - 写真追加ボタン（サムネイル一覧の末尾に表示）

    private var addPhotoTile: some View {
        Button {
            onCameraButtonTap?()
        } label: {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4]))
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
                .frame(width: 75, height: 75)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.gray.opacity(0.55))
                }
        }
        .buttonStyle(.plain)
    }

    private func thumbnailCell(for photo: MemoPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: photo.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 75, height: 75)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { fullScreenPhoto = photo }

            Button {
                memoPhotos.removeAll { $0.id == photo.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }

    private func fullScreenView(for photo: MemoPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let fullImage = UIImage(data: photo.imageData) {
                ZoomableImageView(image: fullImage)
            }
            Button {
                fullScreenPhoto = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                    .padding(16)
            }
        }
    }

    // MARK: - 振替履歴（カテゴリー欄の代わりに表示）

    private var transferHistoryArea: some View {
        VStack(spacing: 0) {
            HStack {
                Text("振替履歴")
                    .font(layout.rowTitleFont)
                    .foregroundStyle(Color.black)
                Spacer()
            }
            .padding(.horizontal, layout.rowHorizontalPadding)
            .frame(height: layout.categoryHeaderHeight)
            .background(layout.backgroundColor)

            ScrollView(.vertical, showsIndicators: true) {
                if recentTransfers.isEmpty {
                    Text("振替履歴がありません")
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.35))
                        .padding(.top, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(recentTransfers) { transfer in
                            transferHistoryRow(transfer)
                            if transfer.id != recentTransfers.last?.id {
                                Divider().padding(.leading, layout.categoryHorizontalPadding)
                            }
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(layout.lineColor, lineWidth: 1))
                    .padding(.horizontal, layout.categoryHorizontalPadding)
                    .padding(.top, layout.categoryGridTopPadding)
                    .padding(.bottom, layout.categoryGridBottomPadding)
                }
            }
            .frame(maxHeight: .infinity)
            .background(layout.backgroundColor)
        }
    }

    private func transferHistoryRow(_ transfer: TransferData) -> some View {
        Button {
            onSelectHistoryTransfer?(transfer)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(transfer.fromName) → \(transfer.toName)")
                        .font(AppFonts.rowTitle)
                        .foregroundStyle(Color.black.opacity(0.78))
                        .lineLimit(1)
                    Text(shortDate(transfer.date))
                        .font(AppFonts.caption)
                        .foregroundStyle(Color.black.opacity(0.4))
                }
                Spacer()
                Text(formattedAmount(transfer.amount))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.65))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func shortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateFormat = "M/d"
        return fmt.string(from: date)
    }

    private func formattedAmount(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return (f.string(from: NSNumber(value: value)) ?? "\(value)") + "円"
    }
}
