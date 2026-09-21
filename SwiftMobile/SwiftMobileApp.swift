import SwiftUI

@main
struct SwiftMobileApp: App {
    init() {
        WalletService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // The wallet reopens this app through swiftmobile://, and the
                // SDK needs that URL to finish pairing.
                .onOpenURL { url in
                    WalletService.shared.handleDeeplink(url)
                }
        }
    }
}
