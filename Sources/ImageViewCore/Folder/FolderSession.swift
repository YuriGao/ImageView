import Foundation

public struct FolderSession: Equatable, Sendable {
    public var folderURL: URL
    public var items: [ImageItem] {
        didSet { rebuildSearchIndexAndSort(); rebuildVisibleItems() }
    }
    public var filter: FolderFilter {
        didSet { if filter != oldValue { rebuildVisibleItems() } }
    }
    public var sortMode: FolderSortMode {
        didSet { if sortMode != oldValue { sortedItems = items.sorted(by: sortMode.areInIncreasingOrder); rebuildVisibleItems() } }
    }
    public var selectedItemIDs: [ImageItem.ID]
    public var lastOpenedItemID: ImageItem.ID?
    public private(set) var visibleItems: [ImageItem]
    private var sortedItems: [ImageItem] = []
    private var searchableNames: [ImageItem.ID: String] = [:]

    public init(
        folderURL: URL,
        items: [ImageItem] = [],
        filter: FolderFilter = FolderFilter(),
        sortMode: FolderSortMode = .nameAscending,
        selectedItemIDs: [ImageItem.ID] = [],
        lastOpenedItemID: ImageItem.ID? = nil
    ) {
        self.folderURL = folderURL
        self.items = items
        self.filter = filter
        self.sortMode = sortMode
        self.selectedItemIDs = selectedItemIDs
        self.lastOpenedItemID = lastOpenedItemID
        self.visibleItems = []
        rebuildSearchIndexAndSort()
        rebuildVisibleItems()
    }

    public var selectedItems: [ImageItem] {
        let visibleByID = Dictionary(uniqueKeysWithValues: visibleItems.map { ($0.id, $0) })
        return selectedItemIDs.compactMap { visibleByID[$0] }
    }

    public mutating func recordOpenedItem(with id: ImageItem.ID) {
        guard items.contains(where: { $0.id == id }) else { return }
        lastOpenedItemID = id
    }

    public mutating func removeItems(with ids: Set<ImageItem.ID>) {
        items.removeAll { ids.contains($0.id) }
        if let lastOpenedItemID, ids.contains(lastOpenedItemID) {
            self.lastOpenedItemID = nil
        }
    }

    public mutating func replaceItems(_ newItems: [ImageItem]) {
        items = newItems
        if let lastOpenedItemID, !items.contains(where: { $0.id == lastOpenedItemID }) {
            self.lastOpenedItemID = nil
        }
    }

    private static func searchKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private mutating func rebuildSearchIndexAndSort() {
        searchableNames = Dictionary(uniqueKeysWithValues: items.map { ($0.id, Self.searchKey($0.displayFilename)) })
        sortedItems = items.sorted(by: sortMode.areInIncreasingOrder)
    }

    private mutating func rebuildVisibleItems() {
        let needle = Self.searchKey(filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        visibleItems = sortedItems.filter {
            filter.allowedFormats.contains($0.format)
                && (needle.isEmpty || searchableNames[$0.id]?.contains(needle) == true)
        }
        let visibleIDs = Set(visibleItems.map(\.id))
        selectedItemIDs = selectedItemIDs.filter { visibleIDs.contains($0) }
    }
}
