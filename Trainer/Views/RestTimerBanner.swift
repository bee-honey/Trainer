import SwiftUI

struct RestTimerBanner: View {
    @Environment(RestTimer.self) private var restTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = max(0, Int((restTimer.endDate?.timeIntervalSince(context.date) ?? 0).rounded(.up)))
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(remaining) / CGFloat(max(restTimer.total, 1)))
                        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: remaining)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 0) {
                    Text("REST").font(.caption2.bold()).opacity(0.8)
                    Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .font(.title2.bold().monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                }
                Spacer()
                Button("+15s") { restTimer.add(seconds: 15) }
                    .buttonStyle(.bordered).tint(.white)
                Button("Skip") { restTimer.skip() }
                    .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.accentColor.gradient, in: .rect(cornerRadius: 18))
            .shadow(radius: 8, y: 4)
        }
    }
}
