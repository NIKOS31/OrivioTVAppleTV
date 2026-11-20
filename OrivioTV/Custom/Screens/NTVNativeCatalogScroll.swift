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
        private var collection: NTVCatalogCollectionView!
        private var source: UICollectionViewDiffableDataSource<Int, String>!
        private var identifiers: [String] = []
        private var scope: String?
        private var environment = EnvironmentValues()
        private var content: ((String) -> Content)?
        private weak var proxy: NTVCatalogScrollProxy?
        private var pending: (identifier: String, anchor: UnitPoint?)?
        private let hostedCells = NSHashTable<NTVCatalogHostingCell>.weakObjects()

        override func loadView() {
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(500))
            let item = NSCollectionLayoutItem(layoutSize: size)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 22
            let configuration = UICollectionViewCompositionalLayoutConfiguration()
            configuration.contentInsetsReference = .none
            let layout = UICollectionViewCompositionalLayout(section: section, configuration: configuration)
            collection = NTVCatalogCollectionView(frame: .zero, collectionViewLayout: layout)
            collection.delegate = collection
            collection.backgroundColor = .clear
            collection.contentInsetAdjustmentBehavior = .never
            collection.contentInset = UIEdgeInsets(top: 26, left: 0, bottom: 100, right: 0)
            collection.showsVerticalScrollIndicator = false
            collection.allowsSelection = false
            collection.selfSizingInvalidation = .enabledIncludingConstraints
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
                collection.allowVerticalScrolling()
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
            hostedCells.add(cell)
            cell.host(AnyView(hosted.environment(\.self, environment).id(scope + "#" + identifier)), in: self)
        }

        func reveal(_ identifier: String, anchor: UnitPoint?) {
            guard isViewLoaded, let indexPath = source.indexPath(for: identifier) else {
                pending = (identifier, anchor)
                return
            }
            collection.allowVerticalScrolling()
            collection.layoutIfNeeded()
            if anchor == .top {
                collection.scrollToItem(at: indexPath, at: .top, animated: false)
            } else if let attributes = collection.layoutAttributesForItem(at: indexPath) {
                collection.scrollRectToVisible(attributes.frame, animated: false)
            } else {
                pending = (identifier, anchor)
                return
            }
            pending = nil
        }

        private func flushPendingReveal() {
            if let pending { reveal(pending.identifier, anchor: pending.anchor) }
        }

        func cancelPendingReveal() { pending = nil }

        func stop() {
            pending = nil
            if proxy?.target === self { proxy?.target = nil }
            for cell in hostedCells.allObjects { cell.stopHosting() }
            hostedCells.removeAllObjects()
            collection?.delegate = nil
            collection?.dataSource = nil
            source = nil
            content = nil
        }
    }

}

private final class NTVCatalogCollectionView: UICollectionView, UICollectionViewDelegate {
    private var horizontalRow: CGRect?

    func allowVerticalScrolling() {
        #if DEBUG
        if horizontalRow != nil { traceViewport("clear") }
        #endif
        horizontalRow = nil
    }

    override var contentSize: CGSize {
        didSet { if oldValue != contentSize { allowVerticalScrolling() } }
    }

    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set {
            #if DEBUG
            if newValue.y != super.contentOffset.y { traceViewport("setter", proposedY: newValue.y) }
            #endif
            var offset = newValue
            if let horizontalRow, bounds.contains(horizontalRow), !isDragging, !isDecelerating {
                offset.y = super.contentOffset.y
            }
            super.contentOffset = offset
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        shouldUpdateFocusIn context: UICollectionViewFocusUpdateContext) -> Bool {
        allowVerticalScrolling()
        // Horizontal focus within a fully visible shelf must not recenter its vertical owner.
        if (context.focusHeading.contains(.left) || context.focusHeading.contains(.right)),
           !context.focusHeading.contains(.up), !context.focusHeading.contains(.down),
           let previous = context.previouslyFocusedIndexPath, context.nextFocusedIndexPath == previous,
           let frame = layoutAttributesForItem(at: previous)?.frame, bounds.contains(frame) {
            horizontalRow = frame
        }
        #if DEBUG
        traceViewport("focus-\(context.focusHeading.rawValue)-\(context.previouslyFocusedIndexPath?.item ?? -1)-\(context.nextFocusedIndexPath?.item ?? -1)")
        #endif
        return true
    }
}

#if DEBUG
extension NTVCatalogCollectionView {
    func traceViewport(_ stage: String, proposedY: CGFloat? = nil) {
        guard ProcessInfo.processInfo.arguments.contains("-ntvCatalogThreeRowsFixture") else { return }
        let row = horizontalRow
        NSLog("%@", "[FocusTrace] [ShelfScroll] stage=\(stage) y=\(bounds.minY) requested=\(proposedY ?? bounds.minY) armed=\(row != nil) contained=\(row.map { bounds.contains($0) } ?? false) dragging=\(isDragging) decel=\(isDecelerating)")
    }

    @objc func scrollViewDidScroll(_ scrollView: UIScrollView) {
        traceViewport("scrolled")
    }
}
#endif

/// UIKit supplies scrolling/reuse; focus stays on the existing SwiftUI buttons.
private final class NTVCatalogHostingCell: UICollectionViewCell {
    private var hosting: UIHostingController<AnyView>?
    private var hostingConstraints: [NSLayoutConstraint] = []
    override var canBecomeFocused: Bool { false }

    func host(_ content: AnyView, in parent: UIViewController) {
        if let hosting, hosting.parent === parent {
            hosting.rootView = content
            return
        }
        stopHosting()
        // A child hosting controller gives each shelf a complete native focus environment.
        let hosting = UIHostingController(rootView: content)
        self.hosting = hosting
        hosting.sizingOptions = .intrinsicContentSize
        parent.addChild(hosting)
        hosting.view.backgroundColor = .clear
        hosting.view.clipsToBounds = false
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hosting.view)
        hostingConstraints = [
            hosting.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ]
        NSLayoutConstraint.activate(hostingConstraints)
        hosting.didMove(toParent: parent)
    }

    func stopHosting() {
        guard let hosting else { return }
        hosting.willMove(toParent: nil)
        NSLayoutConstraint.deactivate(hostingConstraints)
        hosting.view.removeFromSuperview()
        hosting.removeFromParent()
        hosting.rootView = AnyView(EmptyView())
        self.hosting = nil
        hostingConstraints = []
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // A prepared cell may reappear without another configuration pass.
        stopHosting()
    }
}
