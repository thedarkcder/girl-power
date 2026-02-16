import SwiftUI

struct OnboardingCarouselView: View {
    let slides: [OnboardingSlide]
    @Binding var currentIndex: Int
    let onComplete: () -> Void

    private var lastIndex: Int { max(slides.count - 1, 0) }

    var body: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 20)
            TabView(selection: $currentIndex) {
                ForEach(slides) { slide in
                    VStack(spacing: 24) {
                        Image(systemName: slide.symbolName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .foregroundColor(.pink)
                            .padding()
                            .background(Circle().fill(Color.white.opacity(0.1)))
                            .accessibilityLabel(slide.accessibilityLabel)
                        Text(slide.title)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Text(slide.subtitle)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.horizontal, 16)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(slide.title). \(slide.subtitle)")
                    .tag(slide.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier("onboarding_tabview")
            .accessibilityLabel("Onboarding slides")
            .accessibilityValue("Slide \(min(currentIndex + 1, max(slides.count, 1))) of \(max(slides.count, 1))")
            VStack(spacing: 6) {
                Text(progressLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .accessibilityIdentifier("onboarding_progress_label")
                CarouselProgressIndicator(count: slides.count, currentIndex: currentIndex)
            }
            .padding(.top, 8)
            primaryButton
            Spacer(minLength: 20)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var primaryButton: some View {
        Button(action: advanceOrComplete) {
            Text(currentIndex == lastIndex ? "Continue" : "Next")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.pink)
                .clipShape(Capsule())
                .padding(.horizontal, 32)
        }
        .disabled(slides.isEmpty)
        .accessibilityIdentifier("onboarding_primary_button")
        .accessibilityHint(currentIndex == lastIndex ? "Completes onboarding and unlocks the demo CTA" : "Advances to the next onboarding slide")
    }

    private func advanceOrComplete() {
        guard !slides.isEmpty else { return }
        if currentIndex >= lastIndex {
            onComplete()
        } else {
            withAnimation {
                currentIndex += 1
            }
        }
    }
}

private extension OnboardingCarouselView {
    var progressLabel: String {
        guard !slides.isEmpty else { return "0/0" }
        let clampedIndex = min(max(currentIndex, 0), slides.count - 1) + 1
        return "\(clampedIndex)/\(slides.count)"
    }
}

private struct CarouselProgressIndicator: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.3))
                    .frame(width: index == currentIndex ? 32 : 12, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("onboarding_progress_indicator")
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue(progressAccessibilityValue)
    }

    private var progressAccessibilityValue: String {
        guard count > 0 else { return "No onboarding steps" }
        let clampedIndex = min(max(currentIndex, 0), count - 1) + 1
        return "Step \(clampedIndex) of \(count)"
    }
}

struct OnboardingCarouselView_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var index = 0

        var body: some View {
            OnboardingCarouselView(
                slides: OnboardingSlide.defaultSlides,
                currentIndex: $index,
                onComplete: {}
            )
            .background(Color.black)
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
