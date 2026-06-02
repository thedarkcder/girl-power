import Foundation

struct OnboardingSlide: Identifiable, Equatable {
    let id: Int
    let title: String
    let subtitle: String
    let symbolName: String

    var accessibilityLabel: String {
        "\(title) illustration"
    }

    static let defaultSlides: [OnboardingSlide] = [
        OnboardingSlide(
            id: 0,
            title: "Meet Your Live Squat Coach",
            subtitle: "Get real-time cues while you squat so every rep feels safer, stronger, and more confident.",
            symbolName: "figure.strengthtraining.traditional"
        ),
        OnboardingSlide(
            id: 1,
            title: "Track Form In Every Set",
            subtitle: "See tempo, depth, and coaching notes after each attempt to understand where to improve next.",
            symbolName: "target"
        ),
        OnboardingSlide(
            id: 2,
            title: "Start Your Free Demo",
            subtitle: "Complete onboarding, tap Start Free Demo, and jump straight into the guided squat flow.",
            symbolName: "play.circle.fill"
        )
    ]
}
