import SwiftUI

@MainActor
final class LauncherBus: ObservableObject {
    static let shared = LauncherBus()

    @Published var resetTick: Int = 0
    @Published var targetScreenTopSafeArea: CGFloat = 0

    func reset() { resetTick &+= 1 }
}
