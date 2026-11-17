import CoreData
import Combine

// MARK: - SwiftDataの@Queryに代わる汎用の生きた配列（Core Data移行 Phase 1）
//
// Viewは`@Query private var expenses: [ExpenseData]`のかわりに
// `@StateObject private var observer = ExpenseDataSync.observer(bookId: ...)`のように使い、
// `observer.items`を既存のViewModelへそのまま渡す。ViewModel側は「structの配列を受け取って
// 純粋計算する」という既存の契約を変えずに済む。
//
// NSFetchedResultsControllerを1つラップするだけの薄い実装。CD側のNSManagedObjectを
// Domain（Viewが実際に触るstruct）へ変換するmapクロージャは各`*DataSync`側が提供する。
final class CoreDataListObserver<CD: NSManagedObject, Domain>: NSObject, ObservableObject, NSFetchedResultsControllerDelegate {
    @Published private(set) var items: [Domain] = []

    private let frc: NSFetchedResultsController<CD>
    private let map: (CD) -> Domain?

    init(
        request: NSFetchRequest<CD>,
        context: NSManagedObjectContext,
        map: @escaping (CD) -> Domain?
    ) {
        self.map = map
        self.frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        super.init()
        frc.delegate = self
        try? frc.performFetch()
        items = (frc.fetchedObjects ?? []).compactMap(map)
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        items = (frc.fetchedObjects ?? []).compactMap(map)
    }
}
