import SwiftUI

struct SshTerminalView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        EmbeddedPage(title: "SSH 终端", path: "/ssh/terminal")
    }
}
