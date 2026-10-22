import RealityKit
import UIKit

/// Lights the 3D phone like a product shot: a dark studio with two soft boxes for the glass and
/// metal to reflect, a key light that casts the camera's shadow, and a rim light so a black
/// phone does not vanish into a black background (R-86).
@MainActor
enum StudioLighting {
    /// The reflections, built from a picture drawn here rather than an image file shipped
    /// with the app. Nil if RealityKit cannot make one, in which case the lights alone do.
    static func environment() async -> EnvironmentResource? {
        guard let image = studioImage() else { return nil }
        return try? await EnvironmentResource(equirectangular: image, withName: "readout.studio")
    }

    /// The key and rim lights, under one entity.
    static func lights() -> Entity {
        let rig = Entity()

        let key = DirectionalLight()
        key.light = DirectionalLightComponent(color: .white, intensity: 2_400, isRealWorldProxy: false)
        key.shadow = DirectionalLightComponent.Shadow(
            shadowProjection: .automatic(maximumDistance: 1),
            depthBias: 1
        )
        key.look(at: .zero, from: SIMD3(-0.5, 0.9, 0.7), relativeTo: nil)
        rig.addChild(key)

        let rim = DirectionalLight()
        rim.light = DirectionalLightComponent(
            color: UIColor(red: 0.75, green: 0.85, blue: 1, alpha: 1),
            intensity: 1_600,
            isRealWorldProxy: false
        )
        rim.look(at: .zero, from: SIMD3(0.7, 0.3, -0.8), relativeTo: nil)
        rig.addChild(rim)

        let fill = DirectionalLight()
        fill.light = DirectionalLightComponent(color: .white, intensity: 500, isRealWorldProxy: false)
        fill.look(at: .zero, from: SIMD3(0.6, -0.2, 0.8), relativeTo: nil)
        rig.addChild(fill)
        return rig
    }

    /// An equirectangular studio: dark all round, a faintly lit floor, and two soft boxes high
    /// up — one in front and to the left, a long strip behind and to the right.
    private static func studioImage() -> CGImage? {
        let size = CGSize(width: 512, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let wash = CGGradient(
                colorsSpace: space,
                colors: [
                    UIColor(white: 0.16, alpha: 1).cgColor,
                    UIColor(white: 0.05, alpha: 1).cgColor,
                    UIColor(white: 0.09, alpha: 1).cgColor,
                ] as CFArray,
                locations: [0, 0.55, 1]
            )
            if let wash {
                cg.drawLinearGradient(wash, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            softbox(cg, in: CGRect(x: 150, y: 40, width: 90, height: 60), brightness: 1)
            softbox(cg, in: CGRect(x: 360, y: 55, width: 120, height: 26), brightness: 0.85)
            softbox(cg, in: CGRect(x: 20, y: 70, width: 50, height: 40), brightness: 0.4)
        }
        return image.cgImage
    }

    private static func softbox(_ cg: CGContext, in rect: CGRect, brightness: CGFloat) {
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: 18, color: UIColor(white: brightness, alpha: 1).cgColor)
        cg.setFillColor(UIColor(white: brightness, alpha: 1).cgColor)
        cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 10).cgPath)
        cg.fillPath()
        cg.restoreGState()
    }
}
