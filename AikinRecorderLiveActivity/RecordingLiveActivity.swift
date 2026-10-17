import ActivityKit
import SwiftUI
import WidgetKit

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            lockScreen(context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WaveLines(levels: context.state.levels, paused: context.state.paused)
                        .frame(width: 54, height: 28)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(Recording.compactTime(context.state.elapsed))
                        .font(.headline.monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.snippet)
                        .font(.footnote)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .topLeading)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                }
            } compactLeading: {
                WaveLines(levels: context.state.levels, paused: context.state.paused)
                    .frame(width: 28, height: 16)
            } compactTrailing: {
                Text(Recording.compactTime(context.state.elapsed))
                    .font(.caption2.monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            } minimal: {
                WaveLines(levels: context.state.levels, paused: context.state.paused)
                    .frame(width: 18, height: 12)
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                WaveLines(levels: context.state.levels, paused: context.state.paused)
                    .frame(width: 46, height: 18)
                Text(context.state.paused ? "已暂停" : "正在录音")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(Recording.timeText(context.state.elapsed))
                    .font(.subheadline.monospacedDigit())
            }
            Text(context.state.snippet)
                .font(.footnote)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .topLeading)
            Button(intent: AddMarkIntent()) {
                Text("标记").font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .frame(height: 112)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .activityBackgroundTint(.black)
        .activitySystemActionForegroundColor(.white)
    }
}

private struct WaveLines: View {
    let levels: [Double]
    let paused: Bool
    @Environment(\.isLuminanceReduced) private var reduced

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: paused || reduced)) { timeline in
            Canvas { context, size in
                let energy = levels.isEmpty ? 0.2 : levels.reduce(0, +) / Double(levels.count)
                let amplitude = max(2, size.height * 0.46 * CGFloat(min(1, energy * 1.8)))
                let time = timeline.date.timeIntervalSinceReferenceDate * (paused ? 0 : 1)
                for index in 0..<3 {
                    var path = Path()
                    let speed = 2.4 + Double(index) * 0.7
                    let phase = Double(index) * 1.2
                    stride(from: 0, through: size.width, by: 2).forEach { x in
                        let y = size.height / 2 + sin(x / max(size.width, 1) * .pi * 2 * CGFloat(1.2 + Double(index) * 0.4) + CGFloat(time * speed + phase)) * amplitude
                        let point = CGPoint(x: x, y: y)
                        if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path, with: .color(.white.opacity(0.95 - Double(index) * 0.25)), lineWidth: 1.6)
                }
            }
        }
        .accessibilityLabel(paused ? "录音已暂停" : "正在收录声音")
    }
}

@main
struct RecordingActivityBundle: WidgetBundle {
    var body: some Widget { RecordingLiveActivity() }
}
