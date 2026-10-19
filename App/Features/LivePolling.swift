import SwiftUI

extension View {
    /// Runs `action` every 20 seconds while `isLive`, as long as the view is on screen.
    func refreshingWhileLive(_ isLive: Bool, action: @escaping () async -> Void) -> some View {
        task(id: isLive) {
            guard isLive else { return }
            while true {
                do {
                    try await Task.sleep(for: .seconds(20))
                } catch {
                    return
                }
                await action()
            }
        }
    }
}
