import Foundation

public struct FolderSession: Equatable, Sendable {
    public var folderURL: URL
    public var items: [ImageItem] {
        didSet { trimSelectionToVisibleItems() }
    }
    public var filter: FolderFilter {
        didSet { trimSelectionToVisibleItems() }
    }
    public var sortMode: FolderSortMode
    public var selectedItemIDs: [ImageItem.ID]
    public var lastOpenedItemID: ImageItem.ID?

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
        trimSelectionToVisibleItems()
    }

    public var visibleItems: [ImageItem] {
        items
            .filter(matchesFilter)
            .sorted(by: sortMode.areInIncreasingOrder)
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
        trimSelectionToVisibleItems()
    }

    public mutating func replaceItems(_ newItems: [ImageItem]) {
        items = newItems
        if let lastOpenedItemID, !items.contains(where: { $0.id == lastOpenedItemID }) {
            self.lastOpenedItemID = nil
        }
        trimSelectionToVisibleItems()
    }

    private func matchesFilter(_ item: ImageItem) -> Bool {
        let formatMatches = filter.allowedFormats.contains(item.format)
        guard formatMatches else {
            return false
        }

        let searchText = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchText.isEmpty else {
            return true
        }

        return item.url.lastPathComponent.range(
            of: searchText,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private mutating func trimSelectionToVisibleItems() {
        let visibleIDs = Set(visibleItems.map(\.id))
        selectedItemIDs = selectedItemIDs.filter { visibleIDs.contains($0) }
    }
}
