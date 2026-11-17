import Foundation

struct AssetPickerEntry: Identifiable, Hashable {
    let id: UUID
    let name: String
    let assetType: String
    var colorHex: String? = nil
}
