import SwiftUI
import ReaCore
#if canImport(UIKit)
import UIKit
#endif

/// A single rendered page. Decodes async and falls back to a placeholder while
/// the bytes stream in.
struct ReaderPageCell: View {
    let index: Int
    let fitWidth: Bool
    let bubbles: [TranslatedBubble]
    var showOriginal: Bool = false
    @ObservedObject var model: ReaderViewModel

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: fitWidth ? .fit : .fill)
                        .frame(width: fitWidth ? geo.size.width : nil,
                               height: fitWidth ? nil : geo.size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if failed {
                    brokenPlaceholder
                } else {
                    loadPlaceholder
                }
            }
            .overlay(alignment: .topLeading) {
                if image != nil, !bubbles.isEmpty {
                    TranslationOverlayLayer(
                        bubbles: bubbles,
                        containerSize: CGSize(
                            width: geo.size.width,
                            height: image.map { renderHeight(for: $0, width: geo.size.width) } ?? geo.size.height
                        ),
                        showOriginal: showOriginal
                    )
                }
            }
        }
        .task(id: index) { await load() }
    }

    private var loadPlaceholder: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.04))
            ProgressView()
        }
    }

    private var brokenPlaceholder: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.04))
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.exclamationmark").font(.title2)
                Text("Page \(index + 1) failed")
                    .font(.caption)
                Button("Retry") {
                    failed = false
                    Task { await load() }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        guard image == nil else { return }
        guard let data = await model.data(for: index), let decoded = UIImage(data: data) else {
            failed = true
            return
        }
        image = decoded
    }

    private func renderHeight(for image: UIImage, width: CGFloat) -> CGFloat {
        guard image.size.width > 0 else { return width * 1.5 }
        return width * (image.size.height / image.size.width)
    }
}

/// Continuous vertical scroll, the webtoon / long-strip layout.
struct VerticalPager: View {
    @ObservedObject var model: ReaderViewModel
    let fitWidth: Bool
    var showOriginal: Bool = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.pages.enumerated()), id: \.offset) { index, _ in
                        ReaderPageCell(
                            index: index,
                            fitWidth: fitWidth,
                            bubbles: model.bubbles[index] ?? [],
                            showOriginal: showOriginal,
                            model: model
                        )
                        .id(index)
                        .onAppear {
                            if abs(index - model.currentPage) <= 1 {
                                Task { await model.pageChanged(index) }
                            }
                        }
                    }
                }
            }
            .onAppear {
                proxy.scrollTo(model.currentPage, anchor: .top)
            }
            .onChange(of: model.currentPage) { _, newValue in
                // Only jump when the change came from elsewhere (resume/settings).
                proxy.scrollTo(newValue, anchor: .top)
            }
        }
    }
}

/// Paged horizontal reader, with optional right-to-left order for manga.
struct HorizontalPager: View {
    @ObservedObject var model: ReaderViewModel
    let rtl: Bool
    var showOriginal: Bool = false

    private var orderedIndices: [Int] {
        let indices = Array(0..<model.pages.count)
        return rtl ? indices.reversed() : indices
    }

    var body: some View {
        TabView(selection: Binding(
            get: { model.currentPage },
            set: { newValue in Task { await model.pageChanged(newValue) } }
        )) {
            ForEach(orderedIndices, id: \.self) { index in
                ReaderPageCell(
                    index: index,
                    fitWidth: false,
                    bubbles: model.bubbles[index] ?? [],
                    showOriginal: showOriginal,
                    model: model
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }
}
