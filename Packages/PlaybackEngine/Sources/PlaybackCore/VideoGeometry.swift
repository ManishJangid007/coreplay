import Foundation

// Where the picture goes: turned, mirrored, magnified, or (for 360° video)
// which way you're looking. Plain values with their own rules, so the
// controller can keep them, re-apply them after a change of engine, and
// remember them per file.

// MARK: - Turning and mirroring

/// Turning and mirroring the picture, as VLC's Video ▸ Transform does.
///
/// A rectangle can be laid down eight ways: four turns, each mirrored or
/// not. Every one is stored as "mirror left to right, then turn clockwise",
/// so each has exactly one form, and the changes below compose on screen
/// whatever has been done already.
public struct VideoTransform: Hashable, Sendable, Codable {
    public enum Rotation: Int, Hashable, Sendable, Codable, CaseIterable, Identifiable {
        case none = 0
        case quarter = 90
        case half = 180
        case threeQuarters = 270

        public var id: Self { self }

        public var degrees: Int { rawValue }

        /// Any number of degrees, to the nearest quarter turn below.
        public init(degrees: Int) {
            let normalized = ((degrees % 360) + 360) % 360
            self = Rotation(rawValue: normalized - normalized % 90) ?? .none
        }
    }

    /// Clockwise, after mirroring.
    public var rotation: Rotation
    /// Mirrored left to right, before turning.
    public var isMirrored: Bool

    public init(rotation: Rotation = .none, isMirrored: Bool = false) {
        self.rotation = rotation
        self.isMirrored = isMirrored
    }

    public static let identity = VideoTransform()

    public var isIdentity: Bool { self == .identity }

    /// A quarter or three-quarter turn stands a wide picture on its end.
    public var swapsWidthAndHeight: Bool {
        rotation == .quarter || rotation == .threeQuarters
    }

    /// Turned a quarter, as seen on screen.
    public func rotated(clockwise: Bool = true) -> VideoTransform {
        VideoTransform(rotation: Rotation(degrees: rotation.degrees + (clockwise ? 90 : -90)), isMirrored: isMirrored)
    }

    /// Flipped left to right, as seen on screen.
    public func flippedHorizontally() -> VideoTransform {
        // Mirroring after a turn is the opposite turn after mirroring.
        VideoTransform(rotation: Rotation(degrees: -rotation.degrees), isMirrored: !isMirrored)
    }

    /// Flipped upside down, as seen on screen (a left-to-right flip, turned half way).
    public func flippedVertically() -> VideoTransform {
        VideoTransform(rotation: Rotation(degrees: 180 - rotation.degrees), isMirrored: !isMirrored)
    }

    /// Where a point of the picture ends up, measured from the centre in
    /// screen coordinates (x to the right, y down).
    public func apply(x: Double, y: Double) -> (x: Double, y: Double) {
        var point = (x: isMirrored ? -x : x, y: y)
        for _ in 0..<(rotation.degrees / 90) {
            // A quarter turn clockwise, with y pointing down.
            point = (x: -point.y, y: point.x)
        }
        return point
    }

    /// `apply` as a matrix: where (1, 0) goes is (a, b), where (0, 1) goes is
    /// (c, d), as `CGAffineTransform` takes them in y-down coordinates.
    public var matrix: (a: Double, b: Double, c: Double, d: Double) {
        let xAxis = apply(x: 1, y: 0)
        let yAxis = apply(x: 0, y: 1)
        return (xAxis.x, xAxis.y, yAxis.x, yAxis.y)
    }

    /// The name libVLC's transform filter knows it by, or `nil` for none.
    public var vlcTransformType: String? {
        switch (rotation, isMirrored) {
        case (.none, false): nil
        case (.quarter, false): "90"
        case (.half, false): "180"
        case (.threeQuarters, false): "270"
        case (.none, true): "hflip"
        case (.half, true): "vflip"
        case (.threeQuarters, true): "transpose"
        case (.quarter, true): "antitranspose"
        }
    }

    /// "Turned 90°", "Flipped", "Upside Down", "Turned 90°, Flipped".
    public var summary: String {
        switch (rotation, isMirrored) {
        case (.none, false): "None"
        case (.none, true): "Flipped Horizontally"
        case (.half, true): "Flipped Vertically"
        case (.half, false): "Upside Down"
        case (_, false): "Turned \(rotation.degrees)°"
        case (_, true): "Turned \(rotation.degrees)°, Flipped"
        }
    }
}

// MARK: - Magnifying

/// Magnifying the picture past fitting it, and which part is in view:
/// pinch, ⌘+ and ⌘− on the Mac, then drag to look around.
public struct VideoZoom: Hashable, Sendable, Codable {
    public static let minimumScale = 1.0
    public static let maximumScale = 4.0
    /// The steps ⌘+ and ⌘− go through.
    public static let steps: [Double] = [1, 1.25, 1.5, 2, 3, 4]

    /// 1 shows the whole picture.
    public private(set) var scale: Double
    /// The middle of what's in view, in the picture's own units (0…1 each way).
    public private(set) var centerX: Double
    public private(set) var centerY: Double

    public init(scale: Double = 1, centerX: Double = 0.5, centerY: Double = 0.5) {
        let scale = scale.isFinite ? min(max(scale, Self.minimumScale), Self.maximumScale) : 1
        self.scale = scale
        self.centerX = Self.clampCenter(centerX, scale: scale)
        self.centerY = Self.clampCenter(centerY, scale: scale)
    }

    public static let none = VideoZoom()

    /// Decoded values are kept in range too.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            scale: container.decode(Double.self, forKey: .scale),
            centerX: container.decode(Double.self, forKey: .centerX),
            centerY: container.decode(Double.self, forKey: .centerY)
        )
    }

    public var isZoomed: Bool { scale > 1.001 }

    /// "2×", "1.5×".
    public var title: String {
        "\(scale.formatted(.number.precision(.fractionLength(0...2))))\u{00D7}"
    }

    /// Magnified by `factor`, keeping the point under `anchor` (in the view,
    /// 0…1 each way) where it is.
    public func zoomed(by factor: Double, anchorX: Double = 0.5, anchorY: Double = 0.5) -> VideoZoom {
        guard factor.isFinite, factor > 0 else { return self }
        let newScale = min(max(scale * factor, Self.minimumScale), Self.maximumScale)
        // The point of the picture under the anchor stays under it.
        let pointX = centerX + (anchorX - 0.5) / scale
        let pointY = centerY + (anchorY - 0.5) / scale
        return VideoZoom(scale: newScale, centerX: pointX - (anchorX - 0.5) / newScale, centerY: pointY - (anchorY - 0.5) / newScale)
    }

    /// The next step up or down (⌘+ and ⌘−).
    public func stepped(up: Bool) -> VideoZoom {
        let next = up
            ? Self.steps.first { $0 > scale + 0.001 } ?? Self.maximumScale
            : Self.steps.last { $0 < scale - 0.001 } ?? Self.minimumScale
        return zoomed(by: next / scale)
    }

    /// Dragged by a fraction of the view's width and height: the picture
    /// follows the finger, so what's in view moves the other way.
    public func panned(byX dx: Double, y dy: Double) -> VideoZoom {
        guard dx.isFinite, dy.isFinite else { return self }
        return VideoZoom(scale: scale, centerX: centerX - dx / scale, centerY: centerY - dy / scale)
    }

    /// How far to move the magnified picture from the middle of a view of
    /// this size, in the view's points.
    public func offset(width: Double, height: Double) -> (x: Double, y: Double) {
        ((0.5 - centerX) * scale * width, (0.5 - centerY) * scale * height)
    }

    /// Never past the picture's edges: half of what's in view is 0.5 ÷ scale.
    private static func clampCenter(_ value: Double, scale: Double) -> Double {
        let half = 0.5 / scale
        guard value.isFinite else { return 0.5 }
        return min(max(value, half), 1 - half)
    }
}

// MARK: - Deinterlacing

/// libVLC's deinterlacing filters (VLC's Video ▸ Deinterlace Mode).
public enum DeinterlaceFilter: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case yadif
    case yadif2x
    case blend
    case bob
    case linear
    case mean
    case discard
    case x
    case phosphor
    case ivtc

    public var id: Self { self }

    /// The default: Yadif is sharp and steady for most interlaced video.
    public static let standard = DeinterlaceFilter.yadif

    public var title: String {
        switch self {
        case .yadif: "Yadif"
        case .yadif2x: "Yadif (2\u{00D7})"
        case .blend: "Blend"
        case .bob: "Bob"
        case .linear: "Linear"
        case .mean: "Mean"
        case .discard: "Discard"
        case .x: "X"
        case .phosphor: "Phosphor"
        case .ivtc: "Film NTSC (IVTC)"
        }
    }

    /// One line on what it's good for.
    public var detail: String {
        switch self {
        case .yadif: "Sharp and steady. Best for most video."
        case .yadif2x: "Every field becomes a frame: smoothest motion, more work."
        case .blend: "Mixes the two fields. Soft, but never flickers."
        case .bob: "Doubles the frame rate by stretching each field."
        case .linear: "Like Bob, filling the missing lines smoothly."
        case .mean: "Averages the fields into a half-rate picture."
        case .discard: "Keeps one field. Fast, at half the detail."
        case .x: "Adapts between fields, for detailed motion."
        case .phosphor: "Like a CRT's glow between fields."
        case .ivtc: "Restores films transferred to NTSC at 24 frames a second."
        }
    }
}

// MARK: - 360° video

/// Which way you're looking in a 360° video: libVLC's viewpoint, in degrees.
public struct Viewpoint: Hashable, Sendable, Codable {
    public static let defaultFieldOfView = 80.0
    public static let fieldOfViewRange: ClosedRange<Double> = 20...150

    /// Left and right, −180…180 (positive turns right).
    public private(set) var yaw: Double
    /// Up and down, −90…90 (positive looks up).
    public private(set) var pitch: Double
    /// Tilt, −180…180.
    public private(set) var roll: Double
    /// How wide the view is: smaller is closer.
    public private(set) var fieldOfView: Double

    public init(yaw: Double = 0, pitch: Double = 0, roll: Double = 0, fieldOfView: Double = Viewpoint.defaultFieldOfView) {
        self.yaw = Self.wrap(yaw)
        self.pitch = pitch.isFinite ? min(max(pitch, -90), 90) : 0
        self.roll = Self.wrap(roll)
        self.fieldOfView = fieldOfView.isFinite
            ? min(max(fieldOfView, Self.fieldOfViewRange.lowerBound), Self.fieldOfViewRange.upperBound)
            : Self.defaultFieldOfView
    }

    public static let straightAhead = Viewpoint()

    /// Decoded values are kept in range too.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            yaw: container.decode(Double.self, forKey: .yaw),
            pitch: container.decode(Double.self, forKey: .pitch),
            roll: container.decode(Double.self, forKey: .roll),
            fieldOfView: container.decode(Double.self, forKey: .fieldOfView)
        )
    }

    public var isStraightAhead: Bool { self == .straightAhead }

    /// Dragged across a view `width` points wide: the scene follows the
    /// finger, a full view's width turning by the field of view.
    public func dragged(byX dx: Double, y dy: Double, viewWidth width: Double) -> Viewpoint {
        guard width > 0, dx.isFinite, dy.isFinite else { return self }
        let degreesPerPoint = fieldOfView / width
        return Viewpoint(yaw: yaw - dx * degreesPerPoint, pitch: pitch + dy * degreesPerPoint, roll: roll, fieldOfView: fieldOfView)
    }

    /// Closer (`factor` above 1) or wider, as a pinch or scroll does.
    public func zoomed(by factor: Double) -> Viewpoint {
        guard factor.isFinite, factor > 0 else { return self }
        return Viewpoint(yaw: yaw, pitch: pitch, roll: roll, fieldOfView: fieldOfView / factor)
    }

    /// Turned by the arrow keys: 10° a press.
    public func turned(yaw yawDegrees: Double = 0, pitch pitchDegrees: Double = 0) -> Viewpoint {
        Viewpoint(yaw: yaw + yawDegrees, pitch: pitch + pitchDegrees, roll: roll, fieldOfView: fieldOfView)
    }

    /// Into −180…180.
    private static func wrap(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value <= -180 { value += 360 }
        return value
    }
}

/// How a video's picture is laid out.
public enum VideoProjection: String, Hashable, Sendable, Codable {
    /// An ordinary flat picture.
    case flat
    /// A 360° picture unrolled like a map of the world.
    case equirectangular
    /// A 360° picture as the six faces of a cube.
    case cubeMap

    /// You look around it rather than at it.
    public var isSpherical: Bool { self != .flat }
}

// MARK: - Placing the picture

/// Where the video view goes in its container, and the transform that
/// turns, mirrors and magnifies it there.
///
/// The view is centred, and for a quarter turn stood on its end (so once
/// turned it covers the container). The transform is meant for the
/// container's sublayer transform, which Core Animation applies about the
/// container layer's anchor point: the middle on iOS, a corner on the Mac.
public struct VideoPlacement: Equatable, Sendable {
    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
    }

    /// An affine transform: (x, y) goes to (a·x + c·y + tx, b·x + d·y + ty).
    public struct Affine: Equatable, Sendable {
        public var a: Double
        public var b: Double
        public var c: Double
        public var d: Double
        public var tx: Double
        public var ty: Double

        public static let identity = Affine(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

        public func apply(x: Double, y: Double) -> (x: Double, y: Double) {
            (a * x + c * y + tx, b * x + d * y + ty)
        }
    }

    /// The view's frame in the container (before the transform).
    public var frame: Rect
    /// The container's sublayer transform.
    public var transform: Affine

    /// - Parameters:
    ///   - width: The container's width.
    ///   - height: The container's height.
    ///   - anchorX: The container layer's anchor point, 0…1 across.
    ///   - anchorY: The container layer's anchor point, 0…1 down (or up, with `yUp`).
    ///   - yUp: The container measures y upwards (an unflipped view on the Mac).
    public init(transform: VideoTransform, zoom: VideoZoom, width: Double, height: Double, anchorX: Double, anchorY: Double, yUp: Bool) {
        let pictureWidth = transform.swapsWidthAndHeight ? height : width
        let pictureHeight = transform.swapsWidthAndHeight ? width : height
        frame = Rect(x: (width - pictureWidth) / 2, y: (height - pictureHeight) / 2, width: pictureWidth, height: pictureHeight)

        var linear = transform.matrix
        var offset = zoom.offset(width: width, height: height)
        if yUp {
            // The same turn and mirror, measured with y pointing up.
            linear = (linear.a, -linear.b, -linear.c, linear.d)
            offset.y = -offset.y
        }
        let scale = zoom.scale
        let a = linear.a * scale
        let b = linear.b * scale
        let c = linear.c * scale
        let d = linear.d * scale
        // About the container's middle: from the anchor, the middle is `v` away.
        let vx = width / 2 - anchorX * width
        let vy = height / 2 - anchorY * height
        self.transform = Affine(
            a: a, b: b, c: c, d: d,
            tx: vx + offset.x - (a * vx + c * vy),
            ty: vy + offset.y - (b * vx + d * vy)
        )
    }

    /// Where a point of the container ends up once drawn, for a layer whose
    /// sublayer transform is `transform` (about its anchor point).
    public func rendered(x: Double, y: Double, width: Double, height: Double, anchorX: Double, anchorY: Double) -> (x: Double, y: Double) {
        let anchor = (x: anchorX * width, y: anchorY * height)
        let moved = transform.apply(x: x - anchor.x, y: y - anchor.y)
        return (anchor.x + moved.x, anchor.y + moved.y)
    }
}
