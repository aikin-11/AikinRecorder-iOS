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
                    Text("AR").font(.headline.weight(.bold)).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.progress >= 0 ? "\(Int(context.state.progress * 100))%" : Recording.compactTime(context.state.elapsed))
                        .font(.headline.monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.progress >= 0 {
                        ProgressView(value: context.state.progress)
                            .padding(.horizontal, 8)
                    } else {
                    SubtitleRoll(lines: context.state.captions)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                    }
                }
            } compactLeading: {
                Text("AR").font(.caption.weight(.bold))
            } compactTrailing: {
                Text(context.state.progress >= 0 ? "\(Int(context.state.progress * 100))%" : Recording.compactTime(context.state.elapsed))
                    .font(.caption2.monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            } minimal: {
                Text("AR").font(.caption2.weight(.bold))
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("AikinRec")
                        .font(.subheadline.weight(.semibold))
                    if context.state.progress >= 0 {
                        ProgressView(value: context.state.progress)
                    }
                }
                Text(context.state.snippet)
                    .font(.footnote)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .topLeading)
            }
            if context.state.progress < 0 {
            VStack(spacing: 6) {
                Text(Recording.compactTime(context.state.elapsed))
                    .font(.subheadline.monospacedDigit())
                    .frame(width: 44)
                Button(intent: AddMarkIntent()) {
                    TimelineView(.animation(minimumInterval: 0.2)) { timeline in
                        let lit = context.state.markedUntil > timeline.date
                        Image(systemName: "bookmark.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(lit ? Color.yellow : Color.white)
                            .frame(width: 44, height: 44)
                            .background((lit ? Color.yellow : Color.white).opacity(0.16), in: Circle())
                            .overlay(Circle().strokeBorder(lit ? Color.yellow : Color.white, lineWidth: 1.5))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("标记")
            }
            }
        }
        .frame(height: 96)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .activityBackgroundTint(.black)
        .activitySystemActionForegroundColor(.white)
    }
}

private struct SubtitleRoll: View {
    let lines: [String]
    var body: some View {
        let shown = lines.suffix(3)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(index == shown.count - 1 ? .footnote : .caption2)
                    .foregroundStyle(.white.opacity(index == shown.count - 1 ? 1 : 0.45))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 46, alignment: .bottom)
        .clipped()
        .animation(.easeOut(duration: 0.35), value: lines)
    }
}

private struct WaveLines: View {
    let levels: [Double]
    let paused: Bool
    @Environment(\.isLuminanceReduced) private var reduced

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused || reduced)) { timeline in
            Canvas { context, size in
                let energy = levels.isEmpty ? 0.2 : levels.reduce(0, +) / Double(levels.count)
                let amplitude = max(2, size.height * 0.46 * CGFloat(min(1, energy * 1.8)))
                let time = reduced || paused ? 0 : timeline.date.timeIntervalSinceReferenceDate
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
