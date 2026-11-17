import Foundation
import Combine

protocol TransactionInputSetting {
    var typeName: String { get }
    var methodTitle: String { get }
    var defaultCategory: String { get }
    var defaultMethod: String { get }
    var methods: [String] { get }
    var categories: [String] { get }
}
