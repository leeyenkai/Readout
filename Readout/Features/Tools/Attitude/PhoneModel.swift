import RealityKit
import SwiftUI
import UIKit

/// Builds the 3D phone the Attitude tool turns (R-86).
///
/// Made from shapes rather than loaded from a model file: no asset to license or ship, and a
/// generic modern phone rather than any particular one — no logo, no maker's details. It is
/// built in the phone's own axes, so Core Motion's attitude turns it with no further maths:
/// x to the right of the screen, y to its top, z out of the glass. Sizes are millimetres,
/// scaled to metres once at the end, because the extruder rounds sub-centimetre curves badly.
@MainActor
enum PhoneModel {
    /// The body, in millimetres.
    static let width: Float = 71.5
    static let height: Float = 147
    static let depth: Float = 8.25
    static let cornerRadius: Float = 11.5

    /// The phone, its axis guides and the push arrow, as named children of one entity.
    static func make(accent: UIColor) -> Entity {
        let phone = Entity()
        phone.name = "phone"

        let model = Entity()
        model.scale = SIMD3(repeating: 0.001)
        model.addChild(body())
        model.addChild(display(accent: accent))
        model.addChild(island())
        model.addChild(cameraPlateau())
        for button in sideButtons() { model.addChild(button) }
        phone.addChild(model)

        let guides = axisGuides()
        guides.name = "guides"
        phone.addChild(guides)
        return phone
    }

    // MARK: - Body

    /// A rounded slab with chamfered edges: black glass on the front, coloured glass on the
    /// back, and a brushed-metal band round the sides.
    private static func body() -> Entity {
        let outline = Path(
            roundedRect: CGRect(x: -Double(width) / 2, y: -Double(height) / 2, width: Double(width), height: Double(height)),
            cornerRadius: Double(cornerRadius),
            style: .continuous
        )
        // The chamfers are added outside the extruded depth, one on each face, so the slab is
        // extruded that much thinner to come out at the phone's real thickness.
        let chamfer: Float = 1.1
        var options = MeshResource.ShapeExtrusionOptions()
        options.extrusionMethod = .linear(depth: depth - chamfer * 2)
        options.chamferRadius = chamfer
        options.chamferMode = .both
        options.boundaryResolution = .uniformSegmentsPerSpan(segmentCount: 12)
        options.chamferResolution = .uniformSegmentsPerSpan(segmentCount: 4)
        options.materialAssignment = .init(front: 0, back: 1, extrusion: 2, frontChamfer: 2, backChamfer: 2)

        let materials: [any RealityKit.Material] = [frontGlass, backGlass, frame]
        let entity: ModelEntity
        if let mesh = try? MeshResource(extruding: outline, extrusionOptions: options) {
            entity = ModelEntity(mesh: mesh, materials: materials)
            // Centred on its own bounds, so the phone turns about its own middle whatever
            // origin the extruder chose.
            entity.position = -mesh.bounds.center
        } else {
            // A rounded box is a plainer phone, but a phone nonetheless.
            let box = MeshResource.generateBox(
                size: SIMD3(width, height, depth),
                majorCornerRadius: cornerRadius,
                minorCornerRadius: 1.5
            )
            entity = ModelEntity(mesh: box, materials: [backGlass])
        }
        entity.name = "body"
        return entity
    }

    /// The screen, lit from within so the front is never mistaken for the back.
    private static func display(accent: UIColor) -> Entity {
        let inset: Float = 1.7
        let mesh = MeshResource.generatePlane(
            width: width - inset * 2,
            height: height - inset * 2,
            cornerRadius: cornerRadius - inset
        )
        var material = UnlitMaterial()
        if let image = ScreenArt.image(accent: accent),
           let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            material.color = .init(tint: .white, texture: .init(texture))
        } else {
            material.color = .init(tint: UIColor(white: 0.08, alpha: 1))
        }
        let screen = ModelEntity(mesh: mesh, materials: [material])
        screen.position = SIMD3(0, 0, depth / 2 + 0.06)
        screen.name = "display"
        return screen
    }

    /// The pill at the top of the screen.
    private static func island() -> Entity {
        let mesh = MeshResource.generatePlane(width: 12.5, height: 3.7, cornerRadius: 1.85)
        var material = UnlitMaterial()
        material.color = .init(tint: .black)
        let pill = ModelEntity(mesh: mesh, materials: [material])
        pill.position = SIMD3(0, height / 2 - 9, depth / 2 + 0.1)
        return pill
    }

    /// The raised square on the back with three lenses, a flash and a sensor. Top right as
    /// seen from the front, which is top left as you look at the back of a phone.
    private static func cameraPlateau() -> Entity {
        let side: Float = 34
        let plateauDepth: Float = 1.3
        let centre = SIMD3<Float>(width / 2 - 4.5 - side / 2, height / 2 - 4.5 - side / 2, -depth / 2 - plateauDepth / 2)

        let plateau = Entity()
        plateau.position = centre

        let base = ModelEntity(
            mesh: .generateBox(size: SIMD3(side, side, plateauDepth), majorCornerRadius: 8.5, minorCornerRadius: 0.6),
            materials: [backGlass]
        )
        plateau.addChild(base)

        // Seen from the back the lenses sit two by the phone's edge and one inboard. That edge
        // is +x in the frame the model is built in, which is the front's.
        let lenses: [SIMD2<Float>] = [SIMD2(7.6, 7.6), SIMD2(7.6, -7.6), SIMD2(-7.6, 0)]
        for position in lenses {
            plateau.addChild(lens(at: position, plateauDepth: plateauDepth))
        }

        let flash = ModelEntity(mesh: .generateCylinder(height: 0.4, radius: 2.2), materials: [flashMaterial])
        flash.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        flash.position = SIMD3(-7.6, 11.5, -plateauDepth / 2 - 0.2)
        plateau.addChild(flash)

        let sensor = ModelEntity(mesh: .generateCylinder(height: 0.4, radius: 2), materials: [lensGlass])
        sensor.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        sensor.position = SIMD3(-7.6, -11.5, -plateauDepth / 2 - 0.2)
        plateau.addChild(sensor)
        return plateau
    }

    private static func lens(at position: SIMD2<Float>, plateauDepth: Float) -> Entity {
        let lens = Entity()
        lens.position = SIMD3(position.x, position.y, -plateauDepth / 2)
        // Cylinders stand along y; a quarter turn about x points them out of the back.
        let facingBack = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))

        let ring = ModelEntity(mesh: .generateCylinder(height: 1.6, radius: 6.6), materials: [frame])
        ring.orientation = facingBack
        ring.position = SIMD3(0, 0, -0.8)
        lens.addChild(ring)

        let glass = ModelEntity(mesh: .generateCylinder(height: 0.4, radius: 5.4), materials: [lensGlass])
        glass.orientation = facingBack
        glass.position = SIMD3(0, 0, -1.65)
        lens.addChild(glass)
        return lens
    }

    private static func sideButtons() -> [Entity] {
        let thickness: Float = 1.1
        let band: Float = 3.2
        let left = -width / 2 - thickness / 2 + 0.2
        let right = width / 2 + thickness / 2 - 0.2
        let buttons: [(x: Float, y: Float, length: Float)] = [
            (left, 44, 6.5),     // action
            (left, 30, 10),      // volume up
            (left, 17.5, 10),    // volume down
            (right, 26, 17),     // side
            (right, -14, 12),    // camera control
        ]
        return buttons.map { button in
            let entity = ModelEntity(
                mesh: .generateBox(size: SIMD3(thickness, button.length, band), majorCornerRadius: 0.5, minorCornerRadius: 0.3),
                materials: [frame]
            )
            entity.position = SIMD3(button.x, button.y, 0)
            return entity
        }
    }

    // MARK: - Guides

    /// The phone's own three axes, in the colours every chart in Readout uses for them — so
    /// pitch is visibly a turn about the red one, roll about the green, yaw about the blue
    /// (R-49).
    private static func axisGuides() -> Entity {
        let guides = Entity()
        let reach: Float = 0.105
        let axes: [(axis: Axis, direction: SIMD3<Float>)] = [
            (.x, SIMD3(1, 0, 0)),
            (.y, SIMD3(0, 1, 0)),
            (.z, SIMD3(0, 0, 1)),
        ]
        for (axis, direction) in axes {
            var material = UnlitMaterial()
            material.color = .init(tint: UIColor(axis.colour))
            let length = axis == .y ? reach : reach * 0.75
            let shaft = ModelEntity(mesh: .generateCylinder(height: length, radius: 0.0007), materials: [material])
            let head = ModelEntity(mesh: .generateCone(height: 0.007, radius: 0.0026), materials: [material])
            let pointer = Entity()
            shaft.position = SIMD3(0, length / 2, 0)
            head.position = SIMD3(0, length + 0.0035, 0)
            pointer.addChild(shaft)
            pointer.addChild(head)
            pointer.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: direction)
            guides.addChild(pointer)
        }
        return guides
    }

    /// An arrow along +y, one unit long, for the push: scaled and turned each frame.
    static func pushArrow(accent: UIColor) -> Entity {
        var material = UnlitMaterial()
        material.color = .init(tint: accent)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        let shaft = ModelEntity(mesh: .generateCylinder(height: 1, radius: 0.0016), materials: [material])
        shaft.position = SIMD3(0, 0.5, 0)
        shaft.name = "shaft"
        let head = ModelEntity(mesh: .generateCone(height: 0.012, radius: 0.0052), materials: [material])
        head.name = "head"
        let arrow = Entity()
        arrow.name = "arrow"
        arrow.addChild(shaft)
        arrow.addChild(head)
        return arrow
    }

    // MARK: - Materials

    private static var frontGlass: PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(white: 0.02, alpha: 1))
        material.roughness = 0.06
        material.metallic = 0.0
        material.clearcoat = 1.0
        material.clearcoatRoughness = 0.03
        return material
    }

    private static var backGlass: PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1))
        material.roughness = 0.42
        material.metallic = 0.0
        material.clearcoat = 0.6
        material.clearcoatRoughness = 0.25
        return material
    }

    private static var frame: PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.62, green: 0.63, blue: 0.66, alpha: 1))
        material.roughness = 0.3
        material.metallic = 1.0
        return material
    }

    private static var lensGlass: PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1))
        material.roughness = 0.05
        material.clearcoat = 1.0
        return material
    }

    private static var flashMaterial: PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.95, green: 0.9, blue: 0.75, alpha: 1))
        material.roughness = 0.5
        return material
    }
}

/// The picture on the 3D phone's screen: a dark wash, a glow in the accent, and Readout's own
/// rising-trace mark — enough to tell the front from the back at a glance.
@MainActor
private enum ScreenArt {
    static func image(accent: UIColor) -> CGImage? {
        let size = CGSize(width: 480, height: 987)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()

            // Background, dark navy at the top to near black.
            let wash = CGGradient(
                colorsSpace: space,
                colors: [UIColor(red: 0.05, green: 0.08, blue: 0.16, alpha: 1).cgColor, UIColor(red: 0.01, green: 0.01, blue: 0.03, alpha: 1).cgColor] as CFArray,
                locations: [0, 1]
            )
            if let wash {
                cg.drawLinearGradient(wash, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }

            // A soft glow in the accent behind the mark.
            let glow = CGGradient(
                colorsSpace: space,
                colors: [accent.withAlphaComponent(0.55).cgColor, accent.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 1]
            )
            if let glow {
                let centre = CGPoint(x: size.width / 2, y: size.height * 0.42)
                cg.drawRadialGradient(glow, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: size.width * 0.75, options: [])
            }

            // The mark, from the app icon's artwork, centred and a third of the width.
            let corners: [CGPoint] = [
                CGPoint(x: 176, y: 712), CGPoint(x: 312, y: 628), CGPoint(x: 416, y: 772),
                CGPoint(x: 560, y: 420), CGPoint(x: 688, y: 524), CGPoint(x: 812, y: 322),
            ]
            let markSide = size.width * 0.5
            let scale = markSide / 1024
            let origin = CGPoint(x: (size.width - markSide) / 2, y: size.height * 0.42 - markSide / 2)
            let points = corners.map { CGPoint(x: origin.x + $0.x * scale, y: origin.y + $0.y * scale) }
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setLineWidth(88 * scale)
            cg.setStrokeColor(accent.cgColor)
            cg.addLines(between: points)
            cg.strokePath()
            if let end = points.last {
                let radius = 84 * scale
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillEllipse(in: CGRect(x: end.x - radius, y: end.y - radius, width: radius * 2, height: radius * 2))
            }

            // A home indicator, so the bottom of the screen reads as the bottom.
            let bar = CGRect(x: size.width / 2 - 70, y: size.height - 26, width: 140, height: 8)
            cg.setFillColor(UIColor(white: 1, alpha: 0.75).cgColor)
            cg.addPath(UIBezierPath(roundedRect: bar, cornerRadius: 4).cgPath)
            cg.fillPath()
        }
        return image.cgImage
    }
}
