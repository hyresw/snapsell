import SwiftUI

struct AnalyzingView: View {
    @State private var currentStep = 0
    @State private var progress: CGFloat = 0

    private let steps = AnalysisStep.allCases.filter { $0 != .complete }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Animated item thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(.systemGray6).opacity(0.1))
                        .frame(width: 200, height: 200)

                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 72))
                        .foregroundStyle(Color("AccentYellow").opacity(0.8))

                    // Scanning line
                    ScanLineView()
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                }
                .padding(.bottom, 40)

                // Title
                Text("Analyzing Item")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)

                Text(steps[safe: currentStep]?.label ?? "Processing…")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.45))
                    .animation(.easeInOut, value: currentStep)
                    .padding(.bottom, 32)

                // Progress bar
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.1))
                        .frame(width: 200, height: 3)
                    Capsule()
                        .fill(Color("AccentYellow"))
                        .frame(width: 200 * progress, height: 3)
                        .animation(.easeInOut(duration: 0.6), value: progress)
                }
                .padding(.bottom, 40)

                // Step list
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(stepBackground(for: index))
                                    .frame(width: 22, height: 22)

                                if index < currentStep {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.black)
                                } else if index == currentStep {
                                    ProgressView()
                                        .tint(.black)
                                        .scaleEffect(0.7)
                                } else {
                                    Circle()
                                        .fill(.white.opacity(0.2))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .animation(.easeInOut, value: currentStep)

                            Text(step.label)
                                .font(.system(size: 14))
                                .foregroundStyle(stepTextColor(for: index))
                                .animation(.easeInOut, value: currentStep)
                        }
                    }
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            animateSteps()
        }
    }

    private func stepBackground(for index: Int) -> Color {
        if index < currentStep {
            return Color("AccentYellow")
        } else if index == currentStep {
            return Color("AccentYellow").opacity(0.9)
        } else {
            return .white.opacity(0.08)
        }
    }

    private func stepTextColor(for index: Int) -> Color {
        if index <= currentStep {
            return .white.opacity(0.85)
        } else {
            return .white.opacity(0.3)
        }
    }

    private func animateSteps() {
        let stepDurations: [Double] = [0.8, 1.4, 2.0]
        let progressValues: [CGFloat] = [0.3, 0.65, 0.9]

        for (i, delay) in stepDurations.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentStep = min(i + 1, steps.count - 1)
                    progress = progressValues[i]
                }
            }
        }
    }
}

// MARK: - Scanning Line Animation

struct ScanLineView: View {
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color("AccentYellow").opacity(0.8), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .offset(y: offset)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.8)
                        .repeatForever(autoreverses: true)
                    ) {
                        offset = geo.size.height
                    }
                }
        }
    }
}

// MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
