import SwiftUI
import UIKit

@MainActor fileprivate protocol NTVCatalogScrolling: AnyObject {
    func reveal(_ identifier: String, anchor: UnitPoint?)
    func cancelPendingReveal()
}

@MainActor final class NTVCatalogScrollProxy {
    fileprivate weak var target: (any NTVCatalogScrolling)?

    func scrollTo(_ identifier: String, anchor: UnitPoint? = nil) {
        target?.reveal(identifier, anchor: anchor)
    }

    func cancelPending() { target?.cancelPendingReveal() }
}

/// Only the vertical owner changes; each hosted row keeps its existing buttons and actions.
struct NTVNativeCatalogScroll<Content: View>: UIViewControllerRepresentable {
    let identifiers: [String]
    let scope: String
    let identifier: String
    let proxy: NTVCatalogScrollProxy
    @ViewBuilder var content: (String) -> Content

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(identifiers: identifiers, scope: scope, identifier: identifier,
                          proxy: proxy, environment: context.environment, content: content)
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.stop()
    }

    @MainActor final class Controller: UIViewController, NTVCatalogScrolling {
        private var collection: UICollectionView!
        private var source: UICollectionViewDiffableDataSource<Int, String>!
        private var identifiers: [String] = []
        private var scope: String?
        private var environment = EnvironmentValues()
        private var content: ((String) -> Content)?
        private weak var proxy: NTVCatalogScrollProxy?
        private var pending: (identifier: String, anchor: UnitPoint?)?

        override func loadView() {
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(500))
            let item = NSCollectionLayoutItem(layoutSize: size)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 22
            let configuration = UICollectionViewCompositionalLayoutConfiguration()
            configuration.contentInsetsReference = .none
            let layout = UICollectionViewCompositionalLayout(section: section, configuration: configuration)
            collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
            collection.backgroundColor = .clear
            collection.contentInsetAdjustmentBehavior = .never
            collection.contentInset = UIEdgeInsets(top: 26, left: 0, bottom: 100, right: 0)
            collection.showsVerticalScrollIndicator = false
            collection.allowsSelection = false
            collection.remembersLastFocusedIndexPath = false
            view = collection
            let registration = UICollectionView.CellRegistration<NTVCatalogHostingCell, String> {
                [weak self] cell, _, identifier in self?.configure(cell, identifier: identifier)
            }
            source = UICollectionViewDiffableDataSource<Int, String>(collectionView: collection) {
                collection, indexPath, identifier in
                return collection.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: identifier)
            }
        }

        func update(identifiers: [String], scope: String, identifier: String,
                    proxy: NTVCatalogScrollProxy, environment: EnvironmentValues,
                    content: @escaping (String) -> Content) {
            loadViewIfNeeded()
            precondition(Set(identifiers).count == identifiers.count)
            if let previous = self.proxy, previous !== proxy, previous.target === self { previous.target = nil }
            self.proxy = proxy
            proxy.target = self
            self.environment = environment
            self.content = content
            collection.accessibilityIdentifier = identifier
            let contextChanged = self.scope != scope
            if contextChanged { pending = nil }
            if contextChanged || self.identifiers != identifiers {
                let retained = Set(self.identifiers).intersection(identifiers)
                self.identifiers = identifiers
                self.scope = scope
                var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
                snapshot.appendSections([0])
                snapshot.appendItems(identifiers)
                snapshot.reconfigureItems(identifiers.filter { retained.contains($0) })
                source.apply(snapshot, animatingDifferences: false) { [weak self] in
                    guard let self, self.scope == scope else { return }
                    self.flushPendingReveal()
                }
            } else {
                // Refresh live callbacks/environment, without replacing the diffable snapshot on focus.
                for indexPath in collection.indexPathsForVisibleItems {
                    guard let cell = collection.cellForItem(at: indexPath) as? NTVCatalogHostingCell,
                          let identifier = source.itemIdentifier(for: indexPath) else { continue }
                    configure(cell, identifier: identifier)
                }
            }
        }

        private func configure(_ cell: NTVCatalogHostingCell, identifier: String) {
            guard let content, let scope else { return }
            let hosted = content(identifier), environment = environment
            cell.backgroundConfiguration = .clear()
            cell.contentView.clipsToBounds = false
            cell.clipsToBounds = false
            cell.isAccessibilityElement = false
            cell.contentConfiguration = UIHostingConfiguration {
                hosted.environment(\.self, environment).id(scope + "#" + identifier)
            }.margins(.all, 0)
        }

        func reveal(_ identifier: String, anchor: UnitPoint?) {
            guard isViewLoaded, let indexPath = source.indexPath(for: identifier) else {
                pending = (identifier, anchor)
                return
            }
            collection.layoutIfNeeded()
            if anchor == .top {
                collection.scrollToItem(at: indexPath, at: .top, animated: false)
            } else if let attributes = collection.layoutAttributesForItem(at: indexPath) {
                collection.scrollRectToVisible(attributes.frame, animated: false)
            } else {
                pending = (identifier, anchor)
                return
            }
            // Materialize and size the revealed cell before its SwiftUI focus request runs.
            collection.layoutIfNeeded()
            pending = nil
        }

        private func flushPendingReveal() {
            if let pending { reveal(pending.identifier, anchor: pending.anchor) }
        }

        func cancelPendingReveal() { pending = nil }

        func stop() {
            pending = nil
            if proxy?.target === self { proxy?.target = nil }
            for cell in collection?.visibleCells ?? [] { cell.contentConfiguration = nil }
            collection?.dataSource = nil
            source = nil
            content = nil
        }
    }

}

/// UIKit supplies scrolling/reuse; focus stays on the existing SwiftUI buttons.
private final class NTVCatalogHostingCell: UICollectionViewCell {
    override var canBecomeFocused: Bool { false }
}
