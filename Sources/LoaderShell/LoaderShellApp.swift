import SwiftUI

@main
struct LoaderShellApp: App {
    @State private var shellModel = LoaderShellViewModel()

    var body: some Scene {
        WindowGroup("WARDEN4 Loader Shell") {
            LoaderShellView(viewModel: shellModel)
                .frame(minWidth: 760, minHeight: 520)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
    }
}
