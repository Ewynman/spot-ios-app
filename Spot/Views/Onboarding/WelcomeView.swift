//
//  WelcomeView.swift
//  Spot
//
//  Created by Edward Wynman on 7/10/25.
//

import SwiftUI

struct WelcomeHeroMotionConfiguration: Equatable {
    let oneTimeEntranceEnabled: Bool
    let continuousAnimationsEnabled: Bool
    let pinPulseEnabled: Bool

    static func resolved(reduceMotionEnabled: Bool) -> WelcomeHeroMotionConfiguration {
        WelcomeHeroMotionConfiguration(
            oneTimeEntranceEnabled: true,
            continuousAnimationsEnabled: !reduceMotionEnabled,
            pinPulseEnabled: !reduceMotionEnabled
        )
    }
}

struct OrbitingItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case tag(text: String, icon: String)
        case avatar(initials: String, palette: Int)
        case pin(isHighlighted: Bool)
        case card(title: String, subtitle: String, meta: String)
    }

    let id: String
    let kind: Kind
    let orbitRadiusXMultiplier: CGFloat
    let orbitRadiusYMultiplier: CGFloat
    let phaseOffset: Double
    let size: CGSize
}

enum WelcomeHeroContent {
    static let orbitingItems: [OrbitingItem] = [
        OrbitingItem(
            id: "tag-scenic",
            kind: .tag(text: tag(named: "Scenic View"), icon: systemImage(for: "Scenic View")),
            orbitRadiusXMultiplier: 1.00,
            orbitRadiusYMultiplier: 0.84,
            phaseOffset: -2.40,
            size: CGSize(width: 116, height: 36)
        ),
        OrbitingItem(
            id: "tag-foodie",
            kind: .tag(text: tag(named: "Foodie Heaven"), icon: systemImage(for: "Foodie Heaven")),
            orbitRadiusXMultiplier: 1.08,
            orbitRadiusYMultiplier: 0.90,
            phaseOffset: -0.45,
            size: CGSize(width: 132, height: 36)
        ),
        OrbitingItem(
            id: "tag-quiet",
            kind: .tag(text: tag(named: "Quiet Moment"), icon: systemImage(for: "Quiet Moment")),
            orbitRadiusXMultiplier: 1.02,
            orbitRadiusYMultiplier: 0.95,
            phaseOffset: 1.28,
            size: CGSize(width: 128, height: 36)
        ),
        OrbitingItem(
            id: "avatar-noah",
            kind: .avatar(initials: "N", palette: 0),
            orbitRadiusXMultiplier: 0.86,
            orbitRadiusYMultiplier: 0.78,
            phaseOffset: -1.25,
            size: CGSize(width: 42, height: 42)
        ),
        OrbitingItem(
            id: "avatar-jules",
            kind: .avatar(initials: "J", palette: 1),
            orbitRadiusXMultiplier: 0.92,
            orbitRadiusYMultiplier: 0.80,
            phaseOffset: 2.68,
            size: CGSize(width: 42, height: 42)
        ),
        OrbitingItem(
            id: "pin-primary",
            kind: .pin(isHighlighted: true),
            orbitRadiusXMultiplier: 0.72,
            orbitRadiusYMultiplier: 0.66,
            phaseOffset: 0.48,
            size: CGSize(width: 48, height: 48)
        ),
        OrbitingItem(
            id: "pin-secondary",
            kind: .pin(isHighlighted: false),
            orbitRadiusXMultiplier: 0.74,
            orbitRadiusYMultiplier: 0.70,
            phaseOffset: -3.05,
            size: CGSize(width: 34, height: 34)
        ),
        OrbitingItem(
            id: "card-romantic",
            kind: .card(
                title: tag(named: "Romantic"),
                subtitle: "Saved by Noah",
                meta: "\(tag(named: "Beach Day")) · \(tag(named: "Cozy Corner")) · 2.1 mi"
            ),
            orbitRadiusXMultiplier: 0.82,
            orbitRadiusYMultiplier: 1.02,
            phaseOffset: 1.92,
            size: CGSize(width: 210, height: 86)
        )
    ]

    static func tag(named fallback: String) -> String {
        Constants.VibeTags.defaultTags.first { $0.caseInsensitiveCompare(fallback) == .orderedSame } ?? fallback
    }

    static func systemImage(for title: String) -> String {
        let normalized = title.lowercased()

        if normalized.contains("coffee") || normalized.contains("foodie") || normalized.contains("brunch") {
            return "cup.and.saucer.fill"
        } else if normalized.contains("hidden") || normalized.contains("photo") {
            return "sparkles"
        } else if normalized.contains("romantic") || normalized.contains("date") {
            return "heart.fill"
        } else if normalized.contains("beach") || normalized.contains("waterfront") {
            return "water.waves"
        } else if normalized.contains("nature") || normalized.contains("pet") {
            return "leaf.fill"
        } else if normalized.contains("late") {
            return "moon.stars.fill"
        } else if normalized.contains("study") || normalized.contains("historical") {
            return "book.fill"
        } else if normalized.contains("scenic") || normalized.contains("adventure") {
            return "mountain.2.fill"
        } else if normalized.contains("family") || normalized.contains("people") {
            return "person.2.fill"
        }

        return "mappin.and.ellipse"
    }
}

struct WelcomeHeroSpin {
    static let ringSpinSpeed = (2 * Double.pi) / 32.0
    static let globeSpinCycleDuration: TimeInterval = 24.0

    struct Metrics: Equatable {
        let theta: Double
        let position: CGPoint
        let scale: Double
        let opacity: Double
        let zIndex: Double
    }

    static func position(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radiusX,
            y: center.y + sin(angle) * radiusY
        )
    }

    static func metrics(
        for item: OrbitingItem,
        center: CGPoint,
        baseRadiusX: CGFloat,
        baseRadiusY: CGFloat,
        elapsedTime: TimeInterval,
        ringSpinSpeed: Double = WelcomeHeroSpin.ringSpinSpeed
    ) -> Metrics {
        let theta = elapsedTime * ringSpinSpeed + item.phaseOffset
        let position = position(
            center: center,
            radiusX: baseRadiusX * item.orbitRadiusXMultiplier,
            radiusY: baseRadiusY * item.orbitRadiusYMultiplier,
            angle: CGFloat(theta)
        )

        return Metrics(
            theta: theta,
            position: position,
            scale: 1,
            opacity: 1,
            zIndex: 10
        )
    }
}

struct WelcomeView: View {
    private enum AuthDestination {
        case signup
        case login
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var permissionManager = PermissionManager.shared
    @State private var navigateToLocation = false
    @State private var navigateToNotifications = false
    @State private var navigateToPhoto = false
    @State private var navigateToCamera = false
    @State private var navigateToSignup = false
    @State private var navigateToLogin = false
    @State private var authDestination: AuthDestination = .signup
    @State private var appleErrorMessage: String?
    @State private var headerVisible = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    SpotWelcomeBackgroundView()

                    VStack(spacing: 0) {
                        SpotWelcomeHeaderView(isVisible: headerVisible, reduceMotion: reduceMotion)
                            .padding(.top, proxy.safeAreaInsets.top + topPadding(for: proxy.size))
                            .padding(.horizontal, 28)

                        Spacer(minLength: 10)

                        SpotWelcomeHeroView(configuration: .resolved(reduceMotionEnabled: reduceMotion))
                            .frame(height: heroHeight(for: proxy.size))
                            .padding(.horizontal, 18)
                            .layoutPriority(1)

                        Spacer(minLength: 10)

                        WelcomeAuthActionsView(
                            appleErrorMessage: appleErrorMessage,
                            onAppleRequest: {
                                appleErrorMessage = nil
                                SpotLogger.log(WelcomeViewLogs.appleSignInTapped)
                            },
                            onAppleSuccess: {
                                SpotLogger.log(WelcomeViewLogs.appleSignInSucceeded)
                                // Root auth gate will transition automatically from auth state.
                            },
                            onAppleError: { message in
                                appleErrorMessage = message
                                SpotLogger.log(WelcomeViewLogs.appleSignInFailed, details: ["error": message])
                            },
                            onGetStarted: {
                                appleErrorMessage = nil
                                SpotLogger.log(WelcomeViewLogs.getStartedTapped)
                                startOnboardingFlow(destination: .signup)
                            },
                            onLogin: {
                                appleErrorMessage = nil
                                SpotLogger.log(WelcomeViewLogs.loginTapped)
                                navigateToLogin = true
                            }
                        )
                        .padding(.horizontal, 26)
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom + 12, 28))
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .navigationDestination(isPresented: $navigateToLocation) {
                LocationPermissionView(authDestination: authDestination == .login ? .login : .signup)
                    .environmentObject(permissionManager)
            }
            .navigationDestination(isPresented: $navigateToNotifications) {
                NotificationPermissionView(authDestination: authDestination == .login ? .login : .signup)
                    .environmentObject(permissionManager)
            }
            .navigationDestination(isPresented: $navigateToPhoto) {
                PhotoPermissionView(authDestination: authDestination == .login ? .login : .signup)
                    .environmentObject(permissionManager)
            }
            .navigationDestination(isPresented: $navigateToCamera) {
                CameraPermissionView(authDestination: authDestination == .login ? .login : .signup)
                    .environmentObject(permissionManager)
            }
            .navigationDestination(isPresented: $navigateToSignup) {
                SignupView()
            }
            .navigationDestination(isPresented: $navigateToLogin) {
                LoginView()
            }
            .navigationBarBackButtonHidden(true)
            .accessibilityIdentifier("welcome.screen")
            .onAppear {
                SpotLogger.log(WelcomeViewLogs.screenViewed)
                if reduceMotion {
                    headerVisible = true
                } else {
                    withAnimation(.easeOut(duration: 0.55)) {
                        headerVisible = true
                    }
                }
            }
        }
    }

    private func topPadding(for size: CGSize) -> CGFloat {
        size.height < 700 ? 18 : 28
    }

    private func heroHeight(for size: CGSize) -> CGFloat {
        let proposed = size.height * (size.height < 700 ? 0.34 : 0.38)
        return min(max(proposed, 220), 340)
    }

    private func startOnboardingFlow(destination: AuthDestination) {
        authDestination = destination
        permissionManager.updatePermissionStatuses()
        let locationGranted = permissionManager.locationStatus == .authorizedWhenInUse || permissionManager.locationStatus == .authorizedAlways
        let notificationsGranted = permissionManager.notificationStatus == .authorized
        let photoGranted = permissionManager.photoStatus == .authorized || permissionManager.photoStatus == .limited
        let cameraGranted = permissionManager.cameraStatus == .authorized

        if locationGranted && notificationsGranted && photoGranted && cameraGranted {
            routeToDestination(destination)
        } else if locationGranted && notificationsGranted && photoGranted {
            navigateToCamera = true
            logNavigation(destination: destination, route: "camera_permission")
        } else if locationGranted && notificationsGranted {
            navigateToPhoto = true
            logNavigation(destination: destination, route: "photo_permission")
        } else if locationGranted {
            navigateToNotifications = true
            logNavigation(destination: destination, route: "notification_permission")
        } else {
            navigateToLocation = true
            logNavigation(destination: destination, route: "location_permission")
        }
    }

    private func routeToDestination(_ destination: AuthDestination) {
        switch destination {
        case .signup:
            navigateToSignup = true
            logNavigation(destination: destination, route: "signup")
        case .login:
            navigateToLogin = true
            logNavigation(destination: destination, route: "login")
        }
    }

    private func logNavigation(destination: AuthDestination, route: String) {
        SpotLogger.log(
            WelcomeViewLogs.navigationSucceeded,
            details: [
                "destination": destination == .login ? "login" : "signup",
                "route": route
            ]
        )
    }
}

private struct SpotWelcomeBackgroundView: View {
    var body: some View {
        ZStack {
            Constants.Colors.background.ignoresSafeArea()

            RadialGradient(
                colors: [
                    Constants.Colors.welcomeGlow.opacity(0.24),
                    Constants.Colors.welcomeGlow.opacity(0.08),
                    .clear
                ],
                center: .center,
                startRadius: 8,
                endRadius: 360
            )
            .ignoresSafeArea()

            TopographicLinesView()
                .stroke(Constants.Colors.primary.opacity(0.055), lineWidth: 1)
                .ignoresSafeArea()
        }
    }
}

private struct SpotWelcomeHeaderView: View {
    let isVisible: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("SPOT")
                .font(FontManager.logoTitle())
                .tracking(6)
                .foregroundColor(Constants.Colors.primary)
                .accessibilityLabel("Spot")

            VStack(spacing: 10) {
                Text("Find places worth sharing")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundColor(Constants.Colors.primary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.82)

                Text("Discover favorite spots, vibe tags, and saved recommendations from people you trust.")
                    .font(.callout.weight(.medium))
                    .foregroundColor(Constants.Colors.welcomeMutedText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 330)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible || reduceMotion ? 0 : 12)
    }
}

private struct WelcomeAuthActionsView: View {
    let appleErrorMessage: String?
    let onAppleRequest: () -> Void
    let onAppleSuccess: () -> Void
    let onAppleError: (String) -> Void
    let onGetStarted: () -> Void
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ThemedAppleSignInButton(
                onRequest: onAppleRequest,
                onSuccess: onAppleSuccess,
                onError: onAppleError,
                height: 56
            )
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Sign in with Apple")
            .accessibilityIdentifier("auth.signInWithAppleButton")

            AuthDividerView()

            Button(action: onGetStarted) {
                Text("Get Started")
                    .font(FontManager.buttonText())
                    .foregroundColor(Constants.Colors.buttonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Constants.Colors.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Get Started")
            .accessibilityIdentifier("onboarding.getStartedButton")

            HStack(spacing: 8) {
                Text("Already have an account?")
                    .font(.callout)
                    .foregroundColor(Constants.Colors.welcomeMutedText)

                Button(action: onLogin) {
                    Text("Log in")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(Constants.Colors.primary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Constants.Colors.welcomeSurface.opacity(0.82))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Constants.Colors.primary.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log in")
                .accessibilityIdentifier("auth.loginButton")
            }
            .padding(.top, 2)

            if let appleErrorMessage {
                Text(appleErrorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Authentication error: \(appleErrorMessage)")
            }
        }
    }
}

private struct AuthDividerView: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Constants.Colors.welcomeLine.opacity(0.55))
                .frame(height: 1)

            Text("or")
                .font(.footnote.weight(.medium))
                .foregroundColor(Constants.Colors.welcomeMutedText.opacity(0.82))

            Rectangle()
                .fill(Constants.Colors.welcomeLine.opacity(0.55))
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct SpotWelcomeHeroView: View {
    let configuration: WelcomeHeroMotionConfiguration

    @State private var entranceVisible = false
    @State private var pinPulse = false
    @State private var animationStartDate = Date()

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let center = CGPoint(x: width * 0.50, y: height * 0.52)
            let orbitRadiusX = width * 0.34
            let orbitRadiusY = height * 0.31
            let globeSize = min(width * 0.72, height * 0.72, 250)

            TimelineView(.animation) { timeline in
                let elapsedTime = configuration.continuousAnimationsEnabled
                    ? timeline.date.timeIntervalSince(animationStartDate)
                    : 0

                ZStack {
                    WelcomeGlobeBaseView(
                        elapsedTime: elapsedTime,
                        continuousAnimationsEnabled: configuration.continuousAnimationsEnabled
                    )
                    .frame(width: globeSize, height: globeSize)
                    .position(center)
                    .opacity(entranceVisible ? 1 : 0)
                    .scaleEffect(entranceVisible ? 1 : 0.95)
                    .zIndex(1)

                    ZStack {
                        ForEach(Array(WelcomeHeroContent.orbitingItems.enumerated()), id: \.element.id) { index, item in
                            let metrics = WelcomeHeroSpin.metrics(
                                for: item,
                                center: center,
                                baseRadiusX: orbitRadiusX,
                                baseRadiusY: orbitRadiusY,
                                elapsedTime: elapsedTime
                            )

                            OrbitingItemView(
                                item: item,
                                pulse: item.kind == .pin(isHighlighted: true) && configuration.pinPulseEnabled && pinPulse
                            )
                            .frame(width: item.size.width, height: item.size.height)
                            .position(metrics.position)
                            .scaleEffect(metrics.scale)
                            .opacity(entranceVisible ? 1 : 0)
                            .welcomeEntrance(entranceVisible, delay: 0.18 + Double(index) * 0.045)
                            .zIndex(10)
                        }
                    }
                    .zIndex(2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spot preview showing shared places, vibe tags, and saved recommendations.")
        .onAppear(perform: startAnimations)
    }

    private func startAnimations() {
        if configuration.oneTimeEntranceEnabled {
            withAnimation(.easeOut(duration: 0.58)) {
                entranceVisible = true
            }
        } else {
            entranceVisible = true
        }

        guard configuration.continuousAnimationsEnabled else {
            return
        }

        if configuration.pinPulseEnabled {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                pinPulse = true
            }
        }
    }
}

private struct WelcomeGlobeBaseView: View {
    let elapsedTime: TimeInterval
    let continuousAnimationsEnabled: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Constants.Colors.welcomeSurface)
                .overlay(
                    RadialGradient(
                        colors: [
                            Constants.Colors.welcomeGlow.opacity(0.20),
                            Constants.Colors.accent.opacity(0.14),
                            Constants.Colors.primary.opacity(0.04)
                        ],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: 180
                    )
                )

            WelcomeSpinningLandmassLayer(
                elapsedTime: elapsedTime,
                isAnimated: continuousAnimationsEnabled
            )
            .padding(22)

            WelcomeGlobeGridView()
                .stroke(Constants.Colors.primary.opacity(0.09), lineWidth: 1)
                .padding(18)
        }
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Constants.Colors.primary.opacity(0.08), lineWidth: 1)
        )
        .compositingGroup()
        .shadow(color: Constants.Colors.welcomeCardShadow, radius: 24, y: 14)
    }
}

private struct WelcomeSpinningLandmassLayer: View {
    let elapsedTime: TimeInterval
    let isAnimated: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let progress = isAnimated
                ? elapsedTime.truncatingRemainder(dividingBy: WelcomeHeroSpin.globeSpinCycleDuration) / WelcomeHeroSpin.globeSpinCycleDuration
                : 0
            let offset = CGFloat(progress) * width

            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    WelcomeWorldPatternView()
                        .fill(Constants.Colors.primary.opacity(0.18))
                        .frame(width: width, height: height)
                }
            }
            .offset(x: -offset)
        }
    }
}

private struct WelcomeGlobeGridView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        for multiplier in [CGFloat(-0.48), CGFloat(-0.22), CGFloat(0.22), CGFloat(0.48)] {
            let width = radius * 2 * (1 - abs(multiplier) * 0.8)
            path.addEllipse(
                in: CGRect(
                    x: center.x - width / 2,
                    y: center.y - radius,
                    width: width,
                    height: radius * 2
                )
            )
        }

        for multiplier in [CGFloat(-0.44), CGFloat(-0.18), CGFloat(0.18), CGFloat(0.44)] {
            let y = center.y + multiplier * radius * 2
            let latitudeWidth = radius * 2 * sqrt(max(CGFloat(0.12), 1 - multiplier * multiplier))
            path.move(to: CGPoint(x: center.x - latitudeWidth / 2, y: y))
            path.addQuadCurve(
                to: CGPoint(x: center.x + latitudeWidth / 2, y: y),
                control: CGPoint(x: center.x, y: y + multiplier * 16)
            )
        }

        return path
    }
}

private struct WelcomeWorldPatternView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        // North America
        path.move(to: point(0.12, 0.31))
        path.addCurve(to: point(0.27, 0.20), control1: point(0.14, 0.24), control2: point(0.21, 0.20))
        path.addCurve(to: point(0.43, 0.29), control1: point(0.35, 0.19), control2: point(0.41, 0.22))
        path.addCurve(to: point(0.34, 0.42), control1: point(0.45, 0.36), control2: point(0.39, 0.41))
        path.addCurve(to: point(0.23, 0.47), control1: point(0.30, 0.43), control2: point(0.28, 0.48))
        path.addCurve(to: point(0.12, 0.31), control1: point(0.15, 0.45), control2: point(0.10, 0.39))
        path.closeSubpath()

        // Central America bridge
        path.move(to: point(0.33, 0.46))
        path.addCurve(to: point(0.45, 0.51), control1: point(0.38, 0.45), control2: point(0.43, 0.47))
        path.addCurve(to: point(0.39, 0.56), control1: point(0.47, 0.54), control2: point(0.43, 0.57))
        path.addCurve(to: point(0.31, 0.50), control1: point(0.35, 0.55), control2: point(0.32, 0.53))
        path.closeSubpath()

        // South America
        path.move(to: point(0.43, 0.55))
        path.addCurve(to: point(0.52, 0.69), control1: point(0.51, 0.57), control2: point(0.54, 0.63))
        path.addCurve(to: point(0.45, 0.87), control1: point(0.51, 0.78), control2: point(0.46, 0.82))
        path.addCurve(to: point(0.34, 0.68), control1: point(0.36, 0.79), control2: point(0.34, 0.73))
        path.addCurve(to: point(0.43, 0.55), control1: point(0.34, 0.60), control2: point(0.38, 0.55))
        path.closeSubpath()

        // Europe and Africa
        path.move(to: point(0.52, 0.32))
        path.addCurve(to: point(0.65, 0.27), control1: point(0.55, 0.28), control2: point(0.60, 0.27))
        path.addCurve(to: point(0.72, 0.38), control1: point(0.70, 0.29), control2: point(0.73, 0.33))
        path.addCurve(to: point(0.65, 0.45), control1: point(0.70, 0.42), control2: point(0.68, 0.44))
        path.addCurve(to: point(0.71, 0.65), control1: point(0.73, 0.51), control2: point(0.75, 0.59))
        path.addCurve(to: point(0.61, 0.76), control1: point(0.68, 0.70), control2: point(0.64, 0.75))
        path.addCurve(to: point(0.52, 0.58), control1: point(0.55, 0.69), control2: point(0.51, 0.63))
        path.addCurve(to: point(0.52, 0.32), control1: point(0.53, 0.49), control2: point(0.47, 0.40))
        path.closeSubpath()

        // Asia
        path.move(to: point(0.68, 0.30))
        path.addCurve(to: point(0.91, 0.33), control1: point(0.74, 0.20), control2: point(0.87, 0.23))
        path.addCurve(to: point(0.84, 0.52), control1: point(0.96, 0.44), control2: point(0.90, 0.51))
        path.addCurve(to: point(0.72, 0.48), control1: point(0.79, 0.53), control2: point(0.76, 0.48))
        path.addCurve(to: point(0.68, 0.30), control1: point(0.66, 0.43), control2: point(0.63, 0.36))
        path.closeSubpath()

        // Australia
        path.move(to: point(0.78, 0.67))
        path.addCurve(to: point(0.91, 0.68), control1: point(0.82, 0.62), control2: point(0.88, 0.63))
        path.addCurve(to: point(0.86, 0.77), control1: point(0.94, 0.72), control2: point(0.91, 0.77))
        path.addCurve(to: point(0.76, 0.74), control1: point(0.82, 0.78), control2: point(0.78, 0.77))
        path.addCurve(to: point(0.78, 0.67), control1: point(0.74, 0.70), control2: point(0.75, 0.68))
        path.closeSubpath()

        return path
    }
}

private struct OrbitingItemView: View {
    let item: OrbitingItem
    let pulse: Bool

    var body: some View {
        switch item.kind {
        case .tag(let text, let icon):
            WelcomeVibeChipView(text: text, systemImage: icon)
        case .avatar(let initials, let palette):
            WelcomeAvatarBubbleView(initials: initials, colors: avatarColors(for: palette))
        case .pin(let isHighlighted):
            WelcomeSpotPinView(isHighlighted: isHighlighted, pulse: pulse)
        case .card(let title, let subtitle, let meta):
            WelcomeMiniSpotCardView(title: title, subtitle: subtitle, meta: meta)
        }
    }

    private func avatarColors(for palette: Int) -> [Color] {
        switch palette {
        case 1:
            return [Constants.Colors.welcomeGlow, Constants.Colors.accent]
        default:
            return [Constants.Colors.primary, Constants.Colors.welcomeGlow]
        }
    }
}

private struct WelcomeSpotPinView: View {
    let isHighlighted: Bool
    let pulse: Bool

    var body: some View {
        ZStack {
            if isHighlighted {
                Circle()
                    .fill(Constants.Colors.welcomeGlow.opacity(0.22))
                    .frame(width: 48, height: 48)
                    .scaleEffect(pulse ? 1.18 : 0.86)
                    .opacity(pulse ? 0.18 : 0.52)
            }

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: isHighlighted ? 34 : 28, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Constants.Colors.mapMarkerDot, Constants.Colors.mapMarkerGreen)
                .shadow(color: Constants.Colors.primary.opacity(0.16), radius: 8, y: 4)
        }
        .accessibilityHidden(true)
    }
}

private struct WelcomeAvatarBubbleView: View {
    let initials: String
    let colors: [Color]

    var body: some View {
        Text(initials)
            .font(.caption.weight(.bold))
            .foregroundColor(Constants.Colors.buttonText)
            .frame(width: 42, height: 42)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(Circle())
            .overlay(Circle().stroke(Constants.Colors.buttonText.opacity(0.9), lineWidth: 2))
            .shadow(color: Constants.Colors.welcomeCardShadow, radius: 12, y: 6)
            .accessibilityHidden(true)
    }
}

private struct WelcomeVibeChipView: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(Constants.Colors.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Constants.Colors.welcomeChipFill)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Constants.Colors.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: Constants.Colors.welcomeCardShadow, radius: 10, y: 5)
        .accessibilityHidden(true)
    }
}

private struct WelcomeMiniSpotCardView: View {
    let title: String
    let subtitle: String
    let meta: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundColor(Constants.Colors.primary)
                Spacer()
                Image(systemName: "bookmark.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(Constants.Colors.primary)
            }

            Text(subtitle)
                .font(.caption2.weight(.semibold))
                .foregroundColor(Constants.Colors.welcomeMutedText)

            Text(meta)
                .font(.caption2)
                .foregroundColor(Constants.Colors.welcomeMutedText.opacity(0.86))
        }
        .padding(14)
        .background(Constants.Colors.welcomeSurface.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Constants.Colors.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Constants.Colors.welcomeCardShadow, radius: 16, y: 8)
        .accessibilityHidden(true)
    }
}

private struct TopographicLinesView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let horizontalScale = rect.width / 390
        let verticalScale = rect.height / 844

        for index in 0..<6 {
            let y = CGFloat(index) * 112 * verticalScale + 34
            path.move(to: CGPoint(x: -30, y: y))
            path.addCurve(
                to: CGPoint(x: rect.width + 30, y: y + 44 * verticalScale),
                control1: CGPoint(x: 110 * horizontalScale, y: y - 42 * verticalScale),
                control2: CGPoint(x: 270 * horizontalScale, y: y + 88 * verticalScale)
            )
        }

        return path
    }
}

private extension View {
    func welcomeEntrance(_ isVisible: Bool, delay: Double) -> some View {
        opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.86)
            .animation(.easeOut(duration: 0.44).delay(delay), value: isVisible)
    }
}

#Preview {
    WelcomeView()
        .environmentObject(AuthViewModel())
}

#Preview("Compact Height") {
    WelcomeView()
        .environmentObject(AuthViewModel())
        .frame(height: 667)
}

#Preview("Large Dynamic Type") {
    WelcomeView()
        .environmentObject(AuthViewModel())
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Reduce Motion Static Hero") {
    SpotWelcomeHeroView(configuration: .resolved(reduceMotionEnabled: true))
        .frame(height: 300)
        .padding()
        .background(Constants.Colors.background)
}
