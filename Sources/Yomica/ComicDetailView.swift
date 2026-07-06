import SwiftUI

struct ComicDetailView: View {
    let comic: ComicBook
    
    let columns = [
        GridItem(.adaptive(minimum: 100))
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(comic.pages.enumerated()), id: \.element.id) { index, page in
                    NavigationLink(destination: ReaderView(comic: comic, initialIndex: index)) {
                        VStack {
                            LocalAsyncImage(url: page.imageURL, targetSize: CGSize(width: 100, height: 140)) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 100, height: 140)
                                    .cornerRadius(4)
                            }
                            .scaledToFill()
                            .frame(width: 100, height: 140)
                            .clipped()
                            .cornerRadius(4)
                            
                            Text("\(index + 1)")
                                .font(.caption2)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(comic.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
