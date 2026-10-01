import AppKit
import SwiftUI

enum SidetapTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
}

extension View {
    @ViewBuilder
    func sidetapPrimaryButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func sidetapSecondaryButton() -> some View {
        self.buttonStyle(.bordered)
    }
}
