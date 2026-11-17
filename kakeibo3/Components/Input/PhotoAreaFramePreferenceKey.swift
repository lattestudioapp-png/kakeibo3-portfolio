import SwiftUI

// MARK: - 写真サムネイル一覧の矩形をInputViewへ伝えるPreferenceKey
//
// 入力画面は支出/収入/振替のページ全体に対して横方向のDragGestureを
// .simultaneousGestureで付けており、写真サムネイル一覧（横スクロール）の上での
// 横ドラッグもそのままページ切り替えとして解釈されてしまう。
// simultaneousGestureはジェスチャー優先度の変更では止められないため、
// 写真エリアの実際の画面上の矩形（.global座標）をPreferenceKey経由で
// InputView側へ伝え、ページ切り替え側のDragGestureがその矩形内で開始した
// ドラッグを無視するようにする。
//
// 写真が1枚も無い場合は矩形を報告しない（空配列のまま）ことで、
// 従来通りそのエリア上でもページ切り替えスワイプが効くようにする。
struct PhotoAreaFramePreferenceKey: PreferenceKey {
    static var defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}
