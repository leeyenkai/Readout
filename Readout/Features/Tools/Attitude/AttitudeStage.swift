import RealityKit
import SwiftUI

/// The RealityKit view the 3D phone is drawn in (R-86).
///
/// It hands everything to `PhoneStage` and keeps nothing of its own but whether a drag is
/// under way, so nothing SwiftUI observes changes as the model moves: the drag goes straight
/// to the stage, and the stage turns the model from RealityKit's own per-frame update.
struct AttitudeStage: View {
    let stage: PhoneStage

    @Environment(\.themeAccent) private var accent
    /// Resets itself however the drag ends. `onEnded` is skipped when the gesture is
    /// cancelled — a back swipe or a scroll taking over — which left the orbit stuck.
    @GestureState private var isDragging = false

    var body: some View {
        RealityView { [stage, accent] content in
            content.camera = .virtual
            let environment = await StudioLighting.environment()
            stage.install(into: &content, environment: environment, accent: UIColor(accent))
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .updating($isDragging) { _, isDragging, _ in isDragging = true }
                .onChanged { stage.orbit(by: $0.translation) }
        )
        .onChange(of: isDragging) { _, isDragging in
            if !isDragging { stage.endOrbit() }
        }
        .accessibilityElement()
        .accessibilityLabel("A 3D model of your iPhone, turning as it does")
        .accessibilityHint("Drag to look at it from another side")
    }
}
