import SwiftUI
import ReaCore

/// Renders translated bubbles on top of a page, positioned from normalized
/// bounding boxes produced by OCR.
struct TranslationOverlayLayer: View {
    let bubbles: [TranslatedBubble]
    let containerSize: CGSize
    var showOriginal: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(bubbles) { bubble in
                bubbleView(bubble)
                    .position(
                        x: bubble.boundingBox.midX * containerSize.width,
                        y: bubble.boundingBox.midY * containerSize.height
                    )
            }
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func bubbleView(_ bubble: TranslatedBubble) -> some View {
        let width = max(40, bubble.boundingBox.width * containerSize.width)
        return VStack(alignment: .leading, spacing: 2) {
            Text(bubble.translated)
                .font(.system(size: fontSize(for: bubble), weight: .semibold, design: .rounded))
                .foregroundStyle(.black)
            if showOriginal {
                Text(bubble.original)
                    .font(.system(size: fontSize(for: bubble) * 0.7))
                    .foregroundStyle(.black.opacity(0.55))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: width, alignment: .leading)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
    }

    private func fontSize(for bubble: TranslatedBubble) -> CGFloat {
        let base = bubble.boundingBox.height * containerSize.height
        return min(22, max(9, base * 0.42))
    }
}
