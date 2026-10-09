import Foundation
import Observation
import SwiftUI

/// Shared account-scoped repository and store for the retailer marketplace catalogue.
/// Provides instant cached startup, background revalidation, keyset pagination,
/// debounced search, server-side category filtering, and optimistic selection updates.
@MainActor
@Observable
final class MarketplaceCatalogueStore {
    static let shared = MarketplaceCatalogueStore()

    typealias MarketplaceCategoryItem = JewelAPI.MarketplaceCategoryItem

    // MARK: - State

    private(set) var products: [Product] = []
    private(set) var selectedProductIDs: Set<String> = []
    private(set) var categories: [MarketplaceCategoryItem] = []
    private(set) var selectedCategory: String?
    private(set) var searchQuery: String = ""

    private(set) var isInitialLoading: Bool = true
    private(set) var isRefreshing: Bool = false
    private(set) var isLoadingMore: Bool = false
    private(set) var hasMore: Bool = false
    private(set) var nextCursor: String?
    private(set) var error: String?
    private(set) var loadMoreError: String?

    // MARK: - Internal Tasks & State

    private var activeLoadTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?
    private var updatingSelectionIDs = Set<String>()
    private var currentScopeID: String?

    private let cacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("MarketplaceCatalogueCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private struct CachedMarketplacePage: Codable {
        let products: [Product]
        let selectedProductIDs: [String]
        let nextCursor: String?
        let hasMore: Bool
        let timestamp: Date
    }

    private init() {}

    // MARK: - Session Management

    /// Binds the store to the active retailer user account.
    func configure(for retailerUserID: String?) {
        guard retailerUserID != currentScopeID else { return }
        clearInMemory()
        currentScopeID = retailerUserID
    }

    // MARK: - Public Actions

    /// Initial entry load or view appearance.
    func loadInitial(forceRefresh: Bool = false) async {
        activeLoadTask?.cancel()

        // 1. Load categories metadata in parallel if empty
        if categories.isEmpty {
            Task { await self.loadCategories() }
        }

        let category = selectedCategory
        let search = searchQuery

        // 2. Serve from disk cache immediately if available for fast repeat entry (< 100ms)
        let cacheFile = diskCacheURL(category: category, search: search)
        if !forceRefresh, let cached = readDiskCache(from: cacheFile) {
            self.products = cached.products
            self.selectedProductIDs = Set(cached.selectedProductIDs)
            self.nextCursor = cached.nextCursor
            self.hasMore = cached.hasMore
            self.isInitialLoading = false
            self.error = nil

            // Stale-while-revalidate: refresh in background if cache is older than 60 seconds
            if Date().timeIntervalSince(cached.timestamp) > 60 {
                await refresh(category: category, search: search, background: true)
            }
            return
        }

        // 3. Cold fetch with loading indicator
        isInitialLoading = products.isEmpty
        isRefreshing = !products.isEmpty
        error = nil

        await fetchPageOne(category: category, search: search)
    }

    /// Pull-to-refresh
    func refresh() async {
        await refresh(category: selectedCategory, search: searchQuery, background: false)
    }

    private func refresh(category: String?, search: String, background: Bool) async {
        if !background {
            isRefreshing = true
        }
        await fetchPageOne(category: category, search: search)
    }

    /// Selects a category tab, resetting pagination and loading its first page.
    func selectCategory(_ category: String?) {
        guard selectedCategory != category else { return }
        selectedCategory = category
        searchQuery = ""
        searchDebounceTask?.cancel()
        activeLoadTask?.cancel()

        // Check if cached page 1 exists for this category
        let cacheFile = diskCacheURL(category: category, search: "")
        if let cached = readDiskCache(from: cacheFile) {
            self.products = cached.products
            self.selectedProductIDs = Set(cached.selectedProductIDs)
            self.nextCursor = cached.nextCursor
            self.hasMore = cached.hasMore
            self.isInitialLoading = false
            self.error = nil

            activeLoadTask = Task { [weak self] in
                await self?.refresh(category: category, search: "", background: true)
            }
        } else {
            isInitialLoading = true
            products = []
            nextCursor = nil
            hasMore = false
            error = nil
            activeLoadTask = Task { [weak self] in
                await self?.fetchPageOne(category: category, search: "")
            }
        }
    }

    /// Updates search query with 300ms debounce.
    func updateSearchQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard searchQuery != trimmed else { return }
        searchQuery = trimmed
        searchDebounceTask?.cancel()

        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.activeLoadTask?.cancel()
            self.isInitialLoading = true
            self.nextCursor = nil
            self.hasMore = false
            self.error = nil
            await self.fetchPageOne(category: self.selectedCategory, search: self.searchQuery)
        }
    }

    /// Keyset pagination: loads next page using nextCursor.
    func loadMore() async {
        guard hasMore, !isLoadingMore, !isInitialLoading, let cursor = nextCursor else { return }
        isLoadingMore = true
        loadMoreError = nil

        let category = selectedCategory
        let search = searchQuery

        do {
            let response = try await JewelAPI.fetchPaginatedMarketplace(
                category: category,
                search: search,
                cursor: cursor,
                limit: 24
            )

            // Deduplicate incoming products against existing IDs
            var seenIDs = Set(products.map(\.id))
            var newProducts: [Product] = []
            for product in response.products {
                if !seenIDs.contains(product.id) {
                    seenIDs.insert(product.id)
                    newProducts.append(product)
                }
            }

            self.products.append(contentsOf: newProducts)
            for id in response.selectedProductIDs {
                self.selectedProductIDs.insert(id)
            }
            self.nextCursor = response.nextCursor
            self.hasMore = response.hasMore
            self.isLoadingMore = false
        } catch {
            guard !Task.isCancelled else {
                isLoadingMore = false
                return
            }
            self.loadMoreError = error.localizedDescription
            self.isLoadingMore = false
        }
    }

    /// Optimistic toggle for product shortlist / board.
    func toggleSelection(for product: Product, onBoard board: CustomerBoard?) async throws {
        let productID = product.id
        guard !updatingSelectionIDs.contains(productID) else { return }
        updatingSelectionIDs.insert(productID)
        defer { updatingSelectionIDs.remove(productID) }

        let wasSelected = selectedProductIDs.contains(productID)
        let shouldSelect = !wasSelected

        // Optimistic update
        if shouldSelect {
            selectedProductIDs.insert(productID)
        } else {
            selectedProductIDs.remove(productID)
        }

        do {
            if let board {
                try await WishlistAPI.setDesign(productID, onBoard: board.id, saved: shouldSelect)
                if shouldSelect { StoreActivity.log(.designSavedToBoard, productID: productID) }
            } else {
                try await JewelAPI.setRetailerSelection(productID: productID, selected: shouldSelect)
                if shouldSelect { StoreActivity.log(.designShortlisted, productID: productID) }
            }
        } catch {
            // Rollback optimistic update
            if shouldSelect {
                selectedProductIDs.remove(productID)
            } else {
                selectedProductIDs.insert(productID)
            }
            throw error
        }
    }

    func isSelectionUpdating(for productID: String) -> Bool {
        updatingSelectionIDs.contains(productID)
    }

    /// Hydrates match IDs returned by image-search.
    /// Reuses products already held in memory, and fetches missing ones via batch hydration.
    func hydrateMatches(ids: [String]) async throws -> [Product] {
        guard !ids.isEmpty else { return [] }

        var inMemory = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        let missingIDs = ids.filter { inMemory[$0] == nil }

        if !missingIDs.isEmpty {
            let response = try await JewelAPI.hydrateMarketplaceProducts(ids: missingIDs)
            for p in response.products {
                inMemory[p.id] = p
            }
            for id in response.selectedProductIDs {
                selectedProductIDs.insert(id)
            }
        }

        // Return strictly in the caller's ranked match ID order
        return ids.compactMap { inMemory[$0] }
    }

    /// Clears memory and disk cache upon logout or account switch.
    func clear() {
        activeLoadTask?.cancel()
        searchDebounceTask?.cancel()
        clearInMemory()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Private Helpers

    private func fetchPageOne(category: String?, search: String) async {
        do {
            let response = try await JewelAPI.fetchPaginatedMarketplace(
                category: category,
                search: search,
                cursor: nil,
                limit: 24
            )

            guard !Task.isCancelled else { return }

            self.products = response.products
            if let fallbackCategories = response.fallbackCategories {
                self.categories = fallbackCategories
            }
            self.selectedProductIDs = Set(response.selectedProductIDs)
            self.nextCursor = response.nextCursor
            self.hasMore = response.hasMore
            self.isInitialLoading = false
            self.isRefreshing = false
            self.error = nil

            // Write first page to disk cache for fast repeat visits
            let cacheFile = diskCacheURL(category: category, search: search)
            writeDiskCache(
                CachedMarketplacePage(
                    products: response.products,
                    selectedProductIDs: response.selectedProductIDs,
                    nextCursor: response.nextCursor,
                    hasMore: response.hasMore,
                    timestamp: Date()
                ),
                to: cacheFile
            )
        } catch {
            guard !Task.isCancelled else { return }
            self.isInitialLoading = false
            self.isRefreshing = false
            if products.isEmpty {
                self.error = error.localizedDescription
            }
        }
    }

    private func loadCategories() async {
        do {
            let response = try await JewelAPI.fetchMarketplaceCategories()
            guard !Task.isCancelled else { return }
            self.categories = response.categories
        } catch {
            // Non-critical: failure leaves categories empty or fallback
        }
    }

    private func clearInMemory() {
        products = []
        selectedProductIDs = []
        categories = []
        selectedCategory = nil
        searchQuery = ""
        isInitialLoading = true
        isRefreshing = false
        isLoadingMore = false
        hasMore = false
        nextCursor = nil
        error = nil
        loadMoreError = nil
        currentScopeID = nil
    }

    private func diskCacheURL(category: String?, search: String) -> URL {
        let catKey = category?.lowercased().filter { $0.isLetter || $0.isNumber } ?? "all"
        let searchKey = search.isEmpty ? "none" : search.lowercased().filter { $0.isLetter || $0.isNumber }
        let scopeKey = currentScopeID ?? "anon"
        let filename = "page1_\(scopeKey)_\(catKey)_\(searchKey).json"
        return cacheDirectory.appendingPathComponent(filename)
    }

    private func readDiskCache(from url: URL) -> CachedMarketplacePage? {
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedMarketplacePage.self, from: data) else {
            return nil
        }
        return cached
    }

    private func writeDiskCache(_ page: CachedMarketplacePage, to url: URL) {
        guard let data = try? JSONEncoder().encode(page) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
