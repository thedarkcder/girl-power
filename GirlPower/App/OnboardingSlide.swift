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
            title: "Celebrate Every Win",
            subtitle: "Girl Power spotlights progress with encouraging nudges to keep the momentum going.",
            symbolName: "sparkles"
        ),
        OnboardingSlide(
            id: 1,
            title: "Set Bold Goals",
            subtitle: "Plan big moves with focused missions, milestones, and transparent accountability.",
            symbolName: "target"
        ),
        OnboardingSlide(
            id: 2,
            title: "Rally Your Crew",
            subtitle: "Invite teammates, share updates, and stay aligned with collaborative rituals.",
            symbolName: "person.3.fill"
        )
    ]
}
