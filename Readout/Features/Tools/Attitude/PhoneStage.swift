import RealityKit
import SwiftUI
import UIKit

/// Everything the 3D view moves, and the per-frame work of moving it (R-86).
///
/// A plain main-actor class rather than SwiftUI state on purpose. The model turns at the
/// display's frame rate; doing that through view state would rebuild the SwiftUI view sixty
/// or a hundred and twenty times a second. Instead RealityKit calls `tick` once a frame and
/// this reads the latest attitude straight from the hub, so nothing in SwiftUI is invalidated
/// by the model moving at all.
@MainActor
final class PhoneStage {
    /// Shows the phone's own three axes.
    var showsGuides = true {
        didSet { guides?.isEnabled = showsGuides }
    }
    /// Lets the phone sway with the pushes it is given.
    var sways = true
    /// Freezes the model where it is.
    var isHeld = false
    /// Under Reduce Motion the model still follows the phone — that is the reading — but
    /// without the sway, the springing back after a drag, or any smoothing lag.
    var reduceMotion = false

    private weak var hub: SensorHub?
    private var subscription: EventSubscription?

    // Lazy, so the throwaway copies `@State` makes of this class allocate nothing.
    private lazy var root = Entity()
    /// Turned by dragging, to look at the phone from another side.
    private lazy var turntable = Entity()
    /// Moved by the sway.
    private lazy var swayAnchor = Entity()
    private var phone: Entity?
    private var guides: Entity?
    private var arrow: Entity?

    /// The turn about the vertical that puts the model the way round the phone is held.
    private var recentringYaw: Double?
    private var wantsRecentre = true
    private var displayed = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
    private var spring = InertialSpring()
    /// The drag, as turns about the vertical and the horizontal, in radians.
    private var orbit = SIMD2<Float>(0, 0)
    private var orbitAtDragStart: SIMD2<Float>?
    private var isDragging = false

    private static let cameraDistance: Float = 0.46
    private static let cameraElevation: Float = 25 * .pi / 180

    func attach(_ hub: SensorHub) {
        self.hub = hub
    }

    func detach() {
        hub = nil
    }

    /// Puts the model the way round the phone is being held now.
    func recentre() {
        wantsRecentre = true
    }

    // MARK: - Building the scene

    /// Builds the scene into a RealityView's content. Safe to call again: anything a previous
    /// call added is taken away first.
    func install(into content: inout RealityViewCameraContent, environment: EnvironmentResource?, accent: UIColor) {
        subscription?.cancel()
        root.removeFromParent()
        root.children.removeAll()
        turntable.children.removeAll()
        swayAnchor.children.removeAll()

        let phone = PhoneModel.make(accent: accent)
        self.phone = phone
        guides = phone.findEntity(named: "guides")
        guides?.isEnabled = showsGuides
        swayAnchor.addChild(phone)
        turntable.addChild(swayAnchor)

        let arrow = PhoneModel.pushArrow(accent: accent)
        arrow.isEnabled = false
        self.arrow = arrow
        turntable.addChild(arrow)

        root.addChild(turntable)
        root.addChild(StudioLighting.lights())
        root.addChild(camera())

        if let environment {
            let light = Entity()
            light.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.3))
            root.addChild(light)
            for model in root.descendants(of: ModelEntity.self) {
                model.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
            }
        }

        content.add(root)
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let deltaTime = event.deltaTime
            MainActor.assumeIsolated {
                self?.tick(deltaTime)
            }
        }
    }

    private func camera() -> Entity {
        let camera = Entity()
        var lens = PerspectiveCameraComponent()
        lens.fieldOfViewInDegrees = 29
        lens.near = 0.01
        lens.far = 5
        camera.components.set(lens)
        let height = Self.cameraDistance * sin(Self.cameraElevation)
        let distance = Self.cameraDistance * cos(Self.cameraElevation)
        camera.look(at: SIMD3(0, -0.005, 0), from: SIMD3(0, height, distance), relativeTo: nil)
        return camera
    }

    // MARK: - Dragging

    /// Turns the scene to follow a drag: across turns it about the vertical, down tips it.
    func orbit(by translation: CGSize) {
        if orbitAtDragStart == nil { orbitAtDragStart = orbit }
        isDragging = true
        let start = orbitAtDragStart ?? .zero
        let perPoint: Float = 1 / 160
        orbit = SIMD2(
            start.x + Float(translation.width) * perPoint,
            (start.y + Float(translation.height) * perPoint).clamped(to: -1.1...1.1)
        )
    }

    /// Lets go, and the scene swings back to face the phone as it is held.
    func endOrbit() {
        isDragging = false
        orbitAtDragStart = nil
    }

    // MARK: - Each frame

    private func tick(_ deltaTime: TimeInterval) {
        guard let hub, let phone, deltaTime > 0 else { return }
        let dt = min(deltaTime, 0.1)

        if !isHeld, let attitude = hub.attitude {
            if wantsRecentre || recentringYaw == nil {
                recentringYaw = AttitudeMaths.recentringYaw(attitude) ?? recentringYaw ?? 0
                wantsRecentre = false
            }
            let yaw = recentringYaw ?? 0
            let target = Self.single(AttitudeMaths.sceneOrientation(attitude, yaw: yaw))
            // Smoothing over a few milliseconds: Core Motion arrives at 60 Hz and a ProMotion
            // screen draws at 120, so without it every other frame would repeat the last pose.
            displayed = reduceMotion ? target : simd_slerp(displayed, target, Float(1 - exp(-dt / 0.03)))
            phone.orientation = displayed

            updateSway(attitude: attitude, yaw: yaw, deltaTime: dt)
        } else if isHeld {
            arrow?.isEnabled = false
        }

        updateOrbit(deltaTime: dt)
    }

    private func updateSway(attitude: Attitude, yaw: Double, deltaTime: Double) {
        guard sways, !reduceMotion, let user = hub?.userAcceleration else {
            spring.reset()
            swayAnchor.position = .zero
            arrow?.isEnabled = false
            return
        }
        let drive = AttitudeMaths.sceneAcceleration(user, attitude: attitude, yaw: yaw)
        spring.step(drive: drive, deltaTime: deltaTime)
        swayAnchor.position = SIMD3<Float>(spring.position)

        // The arrow shows the push itself: which way, and how hard.
        let strength = simd_length(drive)
        guard let arrow, strength > InertialSpring.Parameters.sway.deadZone * 2 else {
            arrow?.isEnabled = false
            return
        }
        arrow.isEnabled = true
        let direction = SIMD3<Float>(drive / strength)
        let length = Float(min(max(strength * 0.012, 0.02), 0.07))
        arrow.position = swayAnchor.position
        arrow.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: direction)
        arrow.findEntity(named: "shaft")?.scale = SIMD3(1, length, 1)
        arrow.findEntity(named: "shaft")?.position = SIMD3(0, length / 2, 0)
        arrow.findEntity(named: "head")?.position = SIMD3(0, length + 0.006, 0)
    }

    /// RealityKit works in single precision; the maths is done in double.
    private static func single(_ quaternion: simd_quatd) -> simd_quatf {
        simd_quatf(
            ix: Float(quaternion.imag.x),
            iy: Float(quaternion.imag.y),
            iz: Float(quaternion.imag.z),
            r: Float(quaternion.real)
        )
    }

    private func updateOrbit(deltaTime: Double) {
        if !isDragging {
            // Critically damped back to centre: settles without overshooting.
            let pull = reduceMotion ? 1 : Float(1 - exp(-deltaTime * 7))
            orbit -= orbit * pull
            if simd_length(orbit) < 0.0005 { orbit = .zero }
        }
        turntable.orientation = simd_quatf(angle: orbit.y, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: orbit.x, axis: SIMD3(0, 1, 0))
    }
}

private extension Entity {
    /// Every descendant of a given type, for components that have to be set on each model.
    func descendants<T: Entity>(of type: T.Type) -> [T] {
        children.flatMap { child -> [T] in
            (child as? T).map { [$0] + child.descendants(of: type) } ?? child.descendants(of: type)
        }
    }
}
