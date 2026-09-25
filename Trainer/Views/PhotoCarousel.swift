import SwiftData
import SwiftUI

/// An exercise's reference photos: swipe between them, tap for full screen.
struct PhotoCarousel: View {
    let photos: [PhotoRef]
    let title: String

    @Environment(\.modelContext) private var modelContext
    @State private var images: [UIImage] = []
    @State private var page = 0
    @State private var fullScreen: FullScreenPhoto?

    private struct FullScreenPhoto: Identifiable {
        let id: Int
        let image: UIImage
    }

    /// Height follows the first photo's shape, within sensible bounds.
    private var aspect: CGFloat {
        guard let first = images.first, first.size.height > 0 else { return 1.9 }
        return min(max(first.size.width / first.size.height, 0.8), 2.2)
    }

    var body: some View {
        TabView(selection: $page) {
            ForEach(images.indices, id: \.self) { i in
                Button { fullScreen = FullScreenPhoto(id: i, image: images[i]) } label: {
                    Image(uiImage: images[i])
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
        .aspectRatio(aspect, contentMode: .fit)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption.bold())
                .padding(6)
                .background(.ultraThinMaterial, in: .circle)
                .padding(8)
                .allowsHitTesting(false)
        }
        .fullScreenCover(item: $fullScreen) { PhotoViewer(image: $0.image, title: title) }
        .task(id: photos) {
            images = photos.compactMap { PhotoLoader.image($0, in: modelContext) }
            page = min(page, max(images.count - 1, 0))
        }
    }
}

/// Full-screen reference photo with pinch-to-zoom and double-tap to reset.
struct PhotoViewer: View {
    let image: UIImage
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .gesture(
                    MagnifyGesture()
                        .onChanged { scale = max(1, baseScale * $0.magnification) }
                        .onEnded { _ in baseScale = scale }
                        .simultaneously(with: DragGesture()
                            .onChanged { v in
                                guard scale > 1 else { return }
                                offset = CGSize(width: baseOffset.width + v.translation.width,
                                                height: baseOffset.height + v.translation.height)
                            }
                            .onEnded { _ in baseOffset = offset })
                )
                .onTapGesture(count: 2) {
                    withAnimation { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    Button("Done") { dismiss() }
                }
        }
    }
}
