import Foundation
import Testing
@testable import PlaybackCore

@Suite("Turning, mirroring, zoom and 360° view")
struct VideoGeometryTests {
    // MARK: Turning and mirroring

    /// Where the picture's top-left corner and its right-hand edge end up.
    private func corners(_ transform: VideoTransform) -> [String] {
        [transform.apply(x: -1, y: -1), transform.apply(x: 1, y: 0)].map { "\(Int($0.x)),\(Int($0.y))" }
    }

    @Test func quarterTurnsGoClockwise() {
        let turned = VideoTransform.identity.rotated()
        #expect(turned.rotation == .quarter)
        // The top-left corner goes to the top right; the right edge points down.
        #expect(corners(turned) == ["1,-1", "0,1"])
        #expect(turned.swapsWidthAndHeight)
        #expect(VideoTransform.identity.rotated(clockwise: false).rotation == .threeQuarters)
        #expect(turned.rotated().rotated().rotated() == .identity)
    }

    @Test func flipsActOnTheScreenWhateverCameBefore() {
        // Flipped left to right after a quarter turn: the top-left corner,
        // which the turn sent to the top right, comes back to the top left,
        // and the right-hand edge still points down.
        let turnedThenFlipped = VideoTransform.identity.rotated().flippedHorizontally()
        #expect(corners(turnedThenFlipped) == ["-1,-1", "0,1"])
        // Two flips the same way cancel out.
        #expect(VideoTransform.identity.flippedHorizontally().flippedHorizontally() == .identity)
        #expect(VideoTransform(rotation: .quarter).flippedVertically().flippedVertically() == VideoTransform(rotation: .quarter))
        // Upside down then mirrored is flipped vertically.
        #expect(VideoTransform(rotation: .half).flippedHorizontally() == VideoTransform.identity.flippedVertically())
        // Both flips are a half turn.
        #expect(VideoTransform.identity.flippedHorizontally().flippedVertically() == VideoTransform(rotation: .half))
    }

    @Test func everyCombinationHasOneFormAndOneVLCName() {
        var names: Set<String> = []
        var transform = VideoTransform.identity
        var seen: Set<VideoTransform> = []
        for flip in 0..<2 {
            for _ in 0..<4 {
                seen.insert(transform)
                if let name = transform.vlcTransformType { names.insert(name) }
                transform = transform.rotated()
            }
            if flip == 0 { transform = transform.flippedHorizontally() }
        }
        #expect(seen.count == 8)
        #expect(names == ["90", "180", "270", "hflip", "vflip", "transpose", "antitranspose"])
    }

    @Test func vlcNamesMatchWhatTheyDo() {
        // libVLC's "transpose" swaps x and y; "antitranspose" swaps and negates them.
        let transpose = VideoTransform(rotation: .threeQuarters, isMirrored: true)
        #expect(transpose.vlcTransformType == "transpose")
        #expect(corners(transpose) == ["-1,-1", "0,1"])
        let vflip = VideoTransform(rotation: .half, isMirrored: true)
        #expect(vflip.vlcTransformType == "vflip")
        #expect(corners(vflip) == ["-1,1", "1,0"])
    }

    @Test func matrixMatchesApply() {
        let transform = VideoTransform(rotation: .quarter, isMirrored: true)
        let m = transform.matrix
        let point = transform.apply(x: 3, y: 2)
        #expect(m.a * 3 + m.c * 2 == point.x)
        #expect(m.b * 3 + m.d * 2 == point.y)
    }

    @Test func summaries() {
        #expect(VideoTransform.identity.summary == "None")
        #expect(VideoTransform(rotation: .quarter).summary == "Turned 90°")
        #expect(VideoTransform.identity.flippedHorizontally().summary == "Flipped Horizontally")
        #expect(VideoTransform.identity.flippedVertically().summary == "Flipped Vertically")
        #expect(VideoTransform(rotation: .half).summary == "Upside Down")
    }

    // MARK: Zoom

    @Test func zoomStaysInsideThePicture() {
        let zoomed = VideoZoom.none.zoomed(by: 2)
        #expect(zoomed.scale == 2)
        #expect(zoomed.centerX == 0.5)
        // Dragging far to the right stops at the picture's left edge.
        let panned = zoomed.panned(byX: 5, y: 0)
        #expect(panned.centerX == 0.25)
        #expect(VideoZoom(scale: 10).scale == VideoZoom.maximumScale)
        #expect(VideoZoom(scale: 0.2).scale == 1)
        #expect(!VideoZoom(scale: 1, centerX: 0.9).isZoomed)
        #expect(VideoZoom(scale: 1, centerX: 0.9).centerX == 0.5)
    }

    @Test func zoomKeepsThePointUnderTheFingers() {
        // Pinching at the right-hand quarter of the view: the point of the
        // picture there stays put.
        let zoomed = VideoZoom.none.zoomed(by: 2, anchorX: 0.75, anchorY: 0.5)
        let pointUnderAnchor = zoomed.centerX + (0.75 - 0.5) / zoomed.scale
        #expect(abs(pointUnderAnchor - 0.75) < 1e-9)
        #expect(abs(zoomed.centerX - 0.625) < 1e-9)
    }

    @Test func zoomSteps() {
        #expect(VideoZoom.none.stepped(up: true).scale == 1.25)
        #expect(VideoZoom(scale: 2).stepped(up: true).scale == 3)
        #expect(VideoZoom(scale: 2).stepped(up: false).scale == 1.5)
        #expect(VideoZoom(scale: 4).stepped(up: true).scale == 4)
        #expect(VideoZoom.none.stepped(up: false).scale == 1)
        #expect(VideoZoom(scale: 2).title == "2×")
    }

    @Test func zoomOffsetMovesTheVisiblePartToTheMiddle() {
        let zoomed = VideoZoom(scale: 2, centerX: 0.25, centerY: 0.5)
        let offset = zoomed.offset(width: 1000, height: 500)
        // The left half is in view: the picture moves right by half the view.
        #expect(offset.x == 500)
        #expect(offset.y == 0)
    }

    @Test func zoomDecodesInRange() throws {
        let data = Data(#"{"scale": 9, "centerX": -3, "centerY": 0.5}"#.utf8)
        let zoom = try JSONDecoder().decode(VideoZoom.self, from: data)
        #expect(zoom.scale == 4)
        #expect(zoom.centerX == 0.125)
    }

    // MARK: Deinterlacing

    @Test func deinterlaceFiltersAreLibVLCNames() {
        #expect(DeinterlaceFilter.standard.rawValue == "yadif")
        #expect(Set(DeinterlaceFilter.allCases.map(\.rawValue)) == ["yadif", "yadif2x", "blend", "bob", "linear", "mean", "discard", "x", "phosphor", "ivtc"])
        #expect(DeinterlaceFilter.allCases.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
    }

    // MARK: 360° view

    @Test func draggingTurnsTheView() {
        // Dragging a whole view's width to the left turns right by the field of view.
        let view = Viewpoint.straightAhead.dragged(byX: -1000, y: 0, viewWidth: 1000)
        #expect(view.yaw == Viewpoint.defaultFieldOfView)
        // Dragging down looks up.
        #expect(Viewpoint.straightAhead.dragged(byX: 0, y: 500, viewWidth: 1000).pitch == 40)
        // Never past straight up or down.
        #expect(Viewpoint.straightAhead.dragged(byX: 0, y: 1e6, viewWidth: 1000).pitch == 90)
    }

    @Test func viewWrapsAndZooms() {
        #expect(Viewpoint(yaw: 190).yaw == -170)
        #expect(Viewpoint(yaw: -540).yaw == 180)
        #expect(Viewpoint.straightAhead.turned(yaw: 370).yaw == 10)
        #expect(Viewpoint.straightAhead.zoomed(by: 2).fieldOfView == 40)
        #expect(Viewpoint.straightAhead.zoomed(by: 100).fieldOfView == 20)
        #expect(Viewpoint.straightAhead.zoomed(by: 0.1).fieldOfView == 150)
        #expect(Viewpoint(fieldOfView: .nan).fieldOfView == Viewpoint.defaultFieldOfView)
        #expect(Viewpoint.straightAhead.isStraightAhead)
    }
}

@Suite("Placing the turned picture")
struct VideoPlacementTests {
    private func rounded(_ point: (x: Double, y: Double)) -> String {
        "\(Int(point.x.rounded())),\(Int(point.y.rounded()))"
    }

    @Test func nothingChosenFillsTheContainer() {
        for (anchorX, anchorY, yUp) in [(0.5, 0.5, false), (0.0, 0.0, true)] {
            let placement = VideoPlacement(transform: .identity, zoom: .none, width: 160, height: 90, anchorX: anchorX, anchorY: anchorY, yUp: yUp)
            #expect(placement.frame == VideoPlacement.Rect(x: 0, y: 0, width: 160, height: 90))
            #expect(placement.transform == .identity)
        }
    }

    @Test func aQuarterTurnStandsTheViewOnEndThenCoversTheContainer() {
        // iOS: y down, anchored in the middle.
        let phone = VideoPlacement(transform: VideoTransform(rotation: .quarter), zoom: .none, width: 160, height: 90, anchorX: 0.5, anchorY: 0.5, yUp: false)
        #expect(phone.frame == VideoPlacement.Rect(x: 35, y: -35, width: 90, height: 160))
        // The view's top-left corner lands at the container's top right.
        #expect(rounded(phone.rendered(x: 35, y: -35, width: 160, height: 90, anchorX: 0.5, anchorY: 0.5)) == "160,0")
        // Its bottom-right corner at the bottom left.
        #expect(rounded(phone.rendered(x: 125, y: 125, width: 160, height: 90, anchorX: 0.5, anchorY: 0.5)) == "0,90")

        // The Mac: y up, anchored at the bottom-left corner.
        let mac = VideoPlacement(transform: VideoTransform(rotation: .quarter), zoom: .none, width: 160, height: 90, anchorX: 0, anchorY: 0, yUp: true)
        #expect(mac.frame == phone.frame)
        // The middle stays put.
        #expect(rounded(mac.rendered(x: 80, y: 45, width: 160, height: 90, anchorX: 0, anchorY: 0)) == "80,45")
        // Turning clockwise on screen takes the view's bottom-left corner
        // (y up) to the container's top left.
        #expect(rounded(mac.rendered(x: 35, y: -35, width: 160, height: 90, anchorX: 0, anchorY: 0)) == "0,90")
    }

    @Test func mirroringSwapsLeftAndRightOnBothPlatforms() {
        let mirrored = VideoTransform.identity.flippedHorizontally()
        let phone = VideoPlacement(transform: mirrored, zoom: .none, width: 160, height: 90, anchorX: 0.5, anchorY: 0.5, yUp: false)
        #expect(rounded(phone.rendered(x: 0, y: 10, width: 160, height: 90, anchorX: 0.5, anchorY: 0.5)) == "160,10")
        let mac = VideoPlacement(transform: mirrored, zoom: .none, width: 160, height: 90, anchorX: 0, anchorY: 0, yUp: true)
        #expect(rounded(mac.rendered(x: 0, y: 10, width: 160, height: 90, anchorX: 0, anchorY: 0)) == "160,10")
        // Upside down: top and bottom swap, left and right stay.
        let upsideDown = VideoPlacement(transform: VideoTransform.identity.flippedVertically(), zoom: .none, width: 160, height: 90, anchorX: 0, anchorY: 0, yUp: true)
        #expect(rounded(upsideDown.rendered(x: 0, y: 10, width: 160, height: 90, anchorX: 0, anchorY: 0)) == "0,80")
    }

    @Test func zoomMagnifiesWhatsInView() {
        // Twice the size, looking at the left half: the picture's left edge
        // stays at the container's left edge, its middle goes to the right edge.
        let zoom = VideoZoom(scale: 2, centerX: 0.25, centerY: 0.5)
        for (anchorX, anchorY, yUp) in [(0.5, 0.5, false), (0.0, 0.0, true)] {
            let placement = VideoPlacement(transform: .identity, zoom: zoom, width: 160, height: 90, anchorX: anchorX, anchorY: anchorY, yUp: yUp)
            #expect(rounded(placement.rendered(x: 0, y: 45, width: 160, height: 90, anchorX: anchorX, anchorY: anchorY)) == "0,45")
            #expect(rounded(placement.rendered(x: 80, y: 45, width: 160, height: 90, anchorX: anchorX, anchorY: anchorY)) == "160,45")
        }
        // Looking at the top half on the Mac (y up): the top stays at the top.
        let top = VideoPlacement(transform: .identity, zoom: VideoZoom(scale: 2, centerX: 0.5, centerY: 0.25), width: 160, height: 90, anchorX: 0, anchorY: 0, yUp: true)
        #expect(rounded(top.rendered(x: 80, y: 90, width: 160, height: 90, anchorX: 0, anchorY: 0)) == "80,90")
    }
}
