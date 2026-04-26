//
//  SpotAnnotationView.swift
//  Spot
//
//  Custom UIKit annotation view for spot pins. Renders a minimal branded
//  green pin (vector-based, *no* network thumbnails) with deterministic
//  per-pin entry animation and clean state transitions for default,
//  filter-match, filter-non-match, selected, and pressed states.
//
//  v1 hard rule from the PRD:
//    "No network images inside spot annotation views in v1."
//  This view enforces that — image data never enters the marker.
//

import UIKit
import MapKit
import SwiftUI

// MARK: - Annotation model

/// Internal annotation type used by the map. Carries the spot, the
/// resolved coordinate (after overlap resolution), and the visual state
/// the diffing pass last assigned.
final class SpotMapAnnotation: NSObject, MKAnnotation {
    let spot: Spot
    /// `dynamic` so KVO observers (i.e. MapKit) re-render when overlap
    /// resolution shifts the coordinate slightly.
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var visualState: SpotMarkerVisualState

    init(spot: Spot, coordinate: CLLocationCoordinate2D, visualState: SpotMarkerVisualState = .default) {
        self.spot = spot
        self.coordinate = coordinate
        self.visualState = visualState
        super.init()
    }

    var spotId: String? { spot.id }
}

// MARK: - View

/// Reusable annotation view for a `SpotMapAnnotation`.
///
/// Layout: an outer halo (only visible in `.selected` state) wrapping a
/// rounded-square pin tile with a small cream center dot. All visuals are
/// drawn in `CALayer`s — no `UIImageView`, no network images, no
/// SwiftUI hosting. This is a deliberate memory-budget choice (v1).
final class SpotAnnotationView: MKAnnotationView {

    static let reuseIdentifier = "SpotMarkerDefault"

    private let haloLayer = CAShapeLayer()
    private let bodyLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()

    private(set) var renderedState: SpotMarkerVisualState = .default
    private var hasAnimatedIn: Bool = false

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        let pinSize = Constants.MapDesign.pinSize
        let haloSize: CGFloat = pinSize + 14
        let frame = CGRect(x: 0, y: 0, width: haloSize, height: haloSize)
        self.frame = frame
        self.backgroundColor = .clear
        self.canShowCallout = false
        self.isOpaque = false
        // Center the pin on the coordinate; lift the visual a touch so the
        // tail of the rounded body sits on the location.
        self.centerOffset = CGPoint(x: 0, y: -pinSize * 0.18)

        // Halo (selection ring)
        haloLayer.frame = frame
        haloLayer.path = UIBezierPath(ovalIn: frame.insetBy(dx: 1, dy: 1)).cgPath
        haloLayer.fillColor = UIColor(Constants.Colors.mapSelectedGlow).cgColor
        haloLayer.opacity = 0
        layer.addSublayer(haloLayer)

        // Body (the green pin tile)
        let bodyFrame = CGRect(
            x: (haloSize - pinSize) / 2,
            y: (haloSize - pinSize) / 2,
            width: pinSize,
            height: pinSize
        )
        bodyLayer.frame = bodyFrame
        bodyLayer.path = UIBezierPath(roundedRect: bodyLayer.bounds, cornerRadius: pinSize * 0.32).cgPath
        bodyLayer.fillColor = UIColor(Constants.Colors.mapMarkerGreen).cgColor
        bodyLayer.strokeColor = UIColor(Constants.Colors.mapMarkerStroke).cgColor
        bodyLayer.lineWidth = 0.5
        bodyLayer.shadowColor = UIColor.black.cgColor
        bodyLayer.shadowOpacity = 0.18
        bodyLayer.shadowOffset = CGSize(width: 0, height: 1.5)
        bodyLayer.shadowRadius = 2
        layer.addSublayer(bodyLayer)

        // Inner dot (cream readability)
        let dotSize = pinSize * 0.30
        dotLayer.frame = CGRect(
            x: bodyFrame.midX - dotSize / 2,
            y: bodyFrame.midY - dotSize / 2,
            width: dotSize,
            height: dotSize
        )
        dotLayer.path = UIBezierPath(ovalIn: dotLayer.bounds).cgPath
        dotLayer.fillColor = UIColor(Constants.Colors.mapMarkerDot).cgColor
        layer.addSublayer(dotLayer)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Always reset transform/opacity so reuse never inherits stale state.
        transform = .identity
        alpha = 1
        haloLayer.opacity = 0
        renderedState = .default
        hasAnimatedIn = false
    }

    /// Apply a visual state. Animations are restrained:
    ///  * default  →  reset
    ///  * selected →  scale + halo fade-in
    ///  * pressed  →  brief shrink
    ///  * filter   →  body color shift (filter match) / dim (non-match)
    func apply(state: SpotMarkerVisualState, animated: Bool) {
        guard state != renderedState else { return }
        renderedState = state

        let scale: CGFloat
        switch state {
        case .default, .filterMatch, .filterNonMatch:
            scale = 1.0
        case .selected:
            scale = Constants.MapDesign.pinSelectedScale
        case .pressed:
            scale = Constants.MapDesign.pinPressedScale
        }

        let bodyColor: UIColor = {
            switch state {
            case .default, .selected, .pressed:
                return UIColor(Constants.Colors.mapMarkerGreen)
            case .filterMatch:
                return UIColor(Constants.Colors.mapFilterMatch)
            case .filterNonMatch:
                return UIColor(Constants.Colors.mapMarkerGreen).withAlphaComponent(0.30)
            }
        }()

        let haloOpacity: Float = state == .selected ? 1 : 0

        let actions = {
            self.transform = CGAffineTransform(scaleX: scale, y: scale)
            self.bodyLayer.fillColor = bodyColor.cgColor
            self.haloLayer.opacity = haloOpacity
        }

        if animated {
            UIView.animate(
                withDuration: Constants.MapDesign.selectSpringResponse,
                delay: 0,
                usingSpringWithDamping: Constants.MapDesign.selectSpringDamping,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: actions
            )
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            actions()
            CATransaction.commit()
        }
        // z-priority — selected pins always sit on top.
        self.zPriority = state == .selected
            ? .max
            : .defaultUnselected
    }

    /// Animate the pin onto the map when it first appears.
    /// Idempotent — calling repeatedly only animates the first time.
    func animateInIfNeeded(delay: Double) {
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true
        let endTransform = transform
        alpha = 0
        transform = endTransform.translatedBy(x: 0, y: -10).scaledBy(x: 0.6, y: 0.6)
        UIView.animate(
            withDuration: Constants.MapDesign.pinEntryDuration,
            delay: delay,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.5,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.alpha = 1
                self.transform = endTransform
            }
        )
    }

    /// Force a fade-out, e.g. when the pin is removed from the viewport.
    func animateOut(completion: @escaping () -> Void) {
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseIn],
            animations: {
                self.alpha = 0
                self.transform = self.transform.scaledBy(x: 0.6, y: 0.6)
            },
            completion: { _ in completion() }
        )
    }
}
