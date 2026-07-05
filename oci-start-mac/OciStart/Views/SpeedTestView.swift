import SwiftUI

struct SpeedTestView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        EmbeddedPage(title: "延迟测试", path: "/delayTest")
    }
}
