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
                    LevelBars(levels: context.state.levels, paused: context.state.paused, height: 28)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(Recording.compactTime(context.state.elapsed))
                        .font(.headline.monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.paused ? "已暂停" : "录音中")
                            .font(.caption.weight(.semibold))
                        Text(context.attributes.title)
                            .font(.caption)
                            .lineLimit(1)
                        Text(context.state.snippet)
                            .font(.footnote)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            } compactLeading: {
                LevelBars(levels: context.state.levels, paused: context.state.paused, height: 16)
                    .frame(width: 28)
            } compactTrailing: {
                Text(Recording.compactTime(context.state.elapsed))
                    .font(.caption2.monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            } minimal: {
                LevelBars(levels: context.state.levels, paused: context.state.paused, height: 12)
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                LevelBars(levels: context.state.levels, paused: context.state.paused, height: 18)
                Text(context.state.paused ? "已暂停" : "正在录音")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(Recording.timeText(context.state.elapsed))
                    .font(.subheadline.monospacedDigit())
            }
            Text(context.attributes.title).font(.caption).lineLimit(1)
            Text(context.state.snippet).font(.footnote).lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(.black)
        .activitySystemActionForegroundColor(.white)
    }
}

private struct LevelBars: View {
    let levels: [Double]
    let paused: Bool
    let height: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: paused)) { timeline in
            let samples = levels.isEmpty ? [0.2, 0.2, 0.2, 0.2, 0.2] : levels
            let shift = Int(timeline.date.timeIntervalSinceReferenceDate * 10)
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    let level = samples[(shift + index) % samples.count]
                    Capsule()
                        .fill(.white)
                        .frame(width: 3, height: max(3, height * CGFloat(min(1, max(0.12, level)))))
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
