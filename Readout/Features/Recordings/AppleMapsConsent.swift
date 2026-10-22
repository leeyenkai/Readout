import SwiftUI

extension View {
    /// The one dialog that turns Apple Maps on, wherever it is turned on from (R-81).
    ///
    /// The route panel asked first; the switch in Settings simply flipped. Turning on the only
    /// thing in Readout that uses the network should say so whichever way it is reached.
    func appleMapsConsent(isPresented: Binding<Bool>) -> some View {
        modifier(AppleMapsConsent(isPresented: isPresented))
    }
}

private struct AppleMapsConsent: ViewModifier {
    @Binding var isPresented: Bool

    @Environment(AppSettings.self) private var settings

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Show routes on Apple Maps?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Show on Apple Maps") {
                withReadoutAnimation { settings.usesAppleMaps = true }
            }
            Button("Keep the plot", role: .cancel) {}
        } message: {
            Text("""
                Apple Maps downloads map tiles for the area a route covers, so this is the one \
                part of Readout that uses the network. Your recordings are never uploaded. You \
                can turn it off again in Settings.
                """)
        }
    }
}
