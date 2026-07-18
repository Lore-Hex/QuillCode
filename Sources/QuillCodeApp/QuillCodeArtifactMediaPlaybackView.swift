import AVKit
import SwiftUI

struct QuillCodeArtifactMediaPlaybackView: View {
    let preview: ToolArtifactMediaPreview
    let url: URL

    @StateObject private var playerModel: QuillCodeArtifactMediaPlayerModel

    init(preview: ToolArtifactMediaPreview, url: URL) {
        self.preview = preview
        self.url = url
        _playerModel = StateObject(wrappedValue: QuillCodeArtifactMediaPlayerModel(url: url))
    }

    var body: some View {
        Group {
            if preview.kind == .video {
                videoPlayer
            } else {
                audioPlayer
            }
        }
        .onDisappear {
            playerModel.pause()
        }
    }

    private var videoPlayer: some View {
        VideoPlayer(player: playerModel.player)
            .frame(maxWidth: .infinity, minHeight: 148, maxHeight: 180)
            .background(Color.black.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .accessibilityLabel("Video player")
    }

    private var audioPlayer: some View {
        HStack(alignment: .center, spacing: QuillCodeMetrics.controlClusterSpacing) {
            Button(action: playerModel.togglePlayback) {
                Image(systemName: playerModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.headline.weight(.semibold))
                    .frame(width: 18)
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .quillCodeIconButtonTarget(size: 44, radius: 14)
            .accessibilityLabel(playerModel.isPlaying ? "Pause audio" : "Play audio")

            VStack(alignment: .leading, spacing: 3) {
                Text(preview.title ?? url.deletingPathExtension().lastPathComponent)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.text)
                    .lineLimit(1)
                Text(playerModel.isPlaying ? "Playing" : "Ready to play")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(playerModel.isPlaying ? QuillCodePalette.green : QuillCodePalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "waveform")
                .font(.title3.weight(.semibold))
                .foregroundStyle(QuillCodePalette.blue)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

@MainActor
private final class QuillCodeArtifactMediaPlayerModel: ObservableObject {
    let player: AVPlayer
    @Published private(set) var isPlaying = false

    init(url: URL) {
        player = AVPlayer(url: url)
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }
}
