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
                    Label(context.state.paused ? "已暂停" : "录音中", systemImage: "mic.fill")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(Recording.timeText(context.state.elapsed))
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.title)
                        .font(.caption2)
                        .lineLimit(1)
                    Text(context.state.snippet)
                        .font(.footnote)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.paused ? "pause.fill" : "waveform")
            } compactTrailing: {
                Text(Recording.timeText(context.state.elapsed))
                    .font(.caption2.monospacedDigit())
                    .frame(width: 56)
            } minimal: {
                Image(systemName: "mic.fill")
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(context.state.paused ? "已暂停" : "正在录音", systemImage: "mic.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(Recording.timeText(context.state.elapsed))
                    .font(.subheadline.monospacedDigit())
            }
            Text(context.attributes.title).font(.caption).lineLimit(1)
            Text(context.state.snippet).font(.footnote).lineLimit(2)
        }
        .padding()
        .activityBackgroundTint(.black)
        .activitySystemActionForegroundColor(.white)
    }
}

@main
struct RecordingActivityBundle: WidgetBundle {
    var body: some Widget { RecordingLiveActivity() }
}
