import SwiftUI

extension View {
    /// `.refreshable` whose work survives SwiftUI cancelling the gesture's own
    /// task: the reload runs in a task of its own and the indicator waits for it.
    func refreshTask(_ action: @escaping @MainActor () async -> Void) -> some View {
        refreshable { await Task { @MainActor in await action() }.value }
    }
}
