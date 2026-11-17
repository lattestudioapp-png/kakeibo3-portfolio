import Foundation

// MARK: - メモ欄のカメラマーク表示設定
//
// 設定 > 入力 の「カメラマークの表示」トグル。
// ON: メモ欄にカメラマークを表示し、写真が0枚の間は写真追加エリアを隠す
//     （カメラマークから1枚以上追加すると写真一覧エリアが表示される）
// OFF: メモ欄のカメラマークを隠し、写真追加エリア（＋タイル）を最初から表示する
//
// この設定は表示の出し分けにのみ使い、既に追加済みの写真データ（memoPhotos）自体には
// 一切影響しない。

enum MemoCameraIconSettings {
    static let storageKey = "showsCameraIconInMemo"
    static let defaultValue = true
}
