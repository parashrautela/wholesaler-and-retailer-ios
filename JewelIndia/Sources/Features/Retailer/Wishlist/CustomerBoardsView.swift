import SwiftUI

/// One customer's boards: the designs they liked, grouped the way the store
/// wants to talk about them ("Wedding", "Daily wear", …).
struct CustomerBoardsView: View {
    @Environment(\.employeeAppearance) private var appearance
    let customer: StoreCustomer
    /// The list behind shows a design count, which changes here.
    var onChanged: () -> Void = {}

    @State private var boards: [CustomerBoard] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedProduct: Product?
    @State private var addingTo: CustomerBoard?
    @State private var sharing: CustomerBoard?
    @State private var showNewBoard = false
    @State private var newBoardTitle = ""
    @State private var confirmDeleteBoard: CustomerBoard?
    /// A change that didn't save — shown over the boards, which stay as they were.
    @State private var notice: String?

    #if DEBUG
    /// Peeks only: boards to show instead of fetching.
    var peekBoards: [CustomerBoard]?
    #endif

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header

                if isLoading && boards.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xxl)
                } else if let errorMessage, boards.isEmpty {
                    VStack(spacing: Spacing.sm) {
                        Text(errorMessage)
                            .font(appearance.body(13))
                            .foregroundStyle(appearance.secondaryInk(Palette.muted))
                        Button("Try Again") { Task { await load() } }
                            .font(appearance.body(13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.xxl)
                } else {
                    ForEach(boards) { board in
                        boardSection(board)
                    }
                }
            }
            .padding(Spacing.base)
        }
        .scrollIndicators(.hidden)
        .background(appearance.panel())
        .navigationTitle(customer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newBoardTitle = ""
                    showNewBoard = true
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(appearance.ink(Palette.dark))
                }
                .accessibilityLabel("New board")
            }
        }
        .task { await load() }
        .sheet(item: $sharing) { board in WishlistShareView(board: board).employeePresentationChrome() }
        .refreshTask { await load() }
        .sheet(item: $selectedProduct) { product in
            MarketplaceProductDetail(product: product).employeePresentationChrome()
        }
        .navigationDestination(item: $addingTo) { board in
            YourTasteView(board: board)
                .onDisappear {
                    Task { await load() }
                    onChanged()
                }
        }
        .alert("New Board", isPresented: $showNewBoard) {
            TextField("Wedding, Daily wear…", text: $newBoardTitle)
            Button("Cancel", role: .cancel) {}
            Button("Create") { Task { await createBoard() } }
        } message: {
            Text("Group the designs \(customer.name) likes.")
        }
        .alert(notice ?? "", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog(
            confirmDeleteBoard.map { "Delete \"\($0.title)\"?" } ?? "",
            isPresented: Binding(
                get: { confirmDeleteBoard != nil },
                set: { if !$0 { confirmDeleteBoard = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Board", role: .destructive) {
                if let board = confirmDeleteBoard {
                    Task { await delete(board) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The designs saved on it are removed from this customer.")
        }
    }

    @ViewBuilder
    private var header: some View {
        let details = [customer.phone, customer.note].compactMap { $0?.trimmed.nilIfEmpty }
        if !details.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .font(appearance.body(13))
                        .foregroundStyle(appearance.secondaryInk(Palette.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appearance.quiet(Palette.background), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func boardSection(_ board: CustomerBoard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(board.title)
                    .font(appearance.cirka(22))
                    .foregroundStyle(appearance.ink(Palette.foreground))
                Text("\(board.products.count)")
                    .font(appearance.body(12, weight: .semibold))
                    .foregroundStyle(appearance.secondaryInk(Palette.muted))
                Spacer()
                Menu {
                    Button { sharing = board } label: {
                        Label("Share Wishlist", systemImage: "square.and.arrow.up")
                    }
                    .disabled(board.products.isEmpty)
                    Button {
                        addingTo = board
                    } label: {
                        Label("Add Designs", systemImage: "plus")
                    }
                    // A customer always keeps at least one board.
                    if boards.count > 1 {
                        Button(role: .destructive) {
                            confirmDeleteBoard = board
                        } label: {
                            Label("Delete Board", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(appearance.ink(Palette.dark))
                        .frame(width: appearance.inEmployeeView ? 44 : 32, height: appearance.inEmployeeView ? 44 : 32)
                }
                .accessibilityLabel("\(board.title) options")
            }

            if board.products.isEmpty {
                Button {
                    addingTo = board
                } label: {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Add designs")
                            .font(appearance.body(13, weight: .semibold))
                    }
                    .foregroundStyle(appearance.secondaryInk(Palette.muted))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
                    .background(appearance.quiet(Palette.background), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: columns, spacing: Spacing.xl) {
                    ForEach(board.products) { product in
                        MarketplaceProductCard(
                            product: product,
                            isSelected: true,
                            isUpdating: false,
                            savesToBoard: true,
                            onOpen: { selectedProduct = product },
                            onToggle: { Task { await remove(product, from: board) } }
                        )
                    }
                }
            }
        }
    }

    private func load() async {
        #if DEBUG
        if let peekBoards {
            boards = peekBoards
            isLoading = false
            return
        }
        #endif
        isLoading = true
        defer { isLoading = false }
        do {
            boards = try await WishlistAPI.fetchBoards(customerID: customer.id)
            errorMessage = nil
        } catch {
            // A cancelled load (the view went away mid-fetch) is not a failure.
            if error is CancellationError { return }
            errorMessage = "Couldn't load these boards."
        }
    }

    private func createBoard() async {
        let title = newBoardTitle.trimmed
        guard !title.isEmpty else { return }
        do {
            try await WishlistAPI.addBoard(customerID: customer.id, title: title)
            await load()
        } catch {
            notice = "Couldn't create that board. Please try again."
        }
    }

    private func delete(_ board: CustomerBoard) async {
        do {
            try await WishlistAPI.deleteBoard(id: board.id)
            boards.removeAll { $0.id == board.id }
            onChanged()
        } catch {
            notice = "Couldn't delete that board. Please try again."
        }
    }

    private func remove(_ product: Product, from board: CustomerBoard) async {
        guard let index = boards.firstIndex(where: { $0.id == board.id }) else { return }
        let before = boards[index].products
        boards[index].products.removeAll { $0.id == product.id }
        do {
            try await WishlistAPI.setDesign(product.id, onBoard: board.id, saved: false)
            onChanged()
        } catch {
            // Boards may have reloaded while this was in flight.
            if let current = boards.firstIndex(where: { $0.id == board.id }) {
                boards[current].products = before
            }
            notice = "Couldn't remove that design. Please try again."
        }
    }
}
