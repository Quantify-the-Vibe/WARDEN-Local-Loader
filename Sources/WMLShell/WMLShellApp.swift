import SwiftUI

@main
struct WMLShellApp: App {
    @State private var shellModel = WMLShellViewModel()

    var body: some Scene {
        WindowGroup("WARDEN Model Loader Shell") {
            WMLShellView(viewModel: shellModel)
                .frame(minWidth: 760, minHeight: 520)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
    }
}
