import SwiftUI

struct ScrollingText: View {
    let text: String
    let width: CGFloat
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    
    private var shouldScroll: Bool {
        textWidth > width
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: shouldScroll ? 50 : 0) {
                Text(text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { textGeometry in
                            Color.clear
                                .onAppear {
                                    textWidth = textGeometry.size.width
                                }
                        }
                    )
                
                if shouldScroll {
                    Text(text)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .offset(x: shouldScroll ? offset : 0)
            .animation(shouldScroll ? .linear(duration: Double(textWidth) / 30).repeatForever(autoreverses: false) : .none, value: offset)
            .onAppear {
                if shouldScroll {
                    offset = -textWidth - 50
                }
            }
            .frame(width: width, alignment: .leading)
            .clipped()
        }
        .frame(height: 20)
    }
}

struct MarqueeText: View {
    let text: String
    @State private var animate = false
    
    var body: some View {
        GeometryReader { geometry in
            let textWidth = text.widthOfString(usingFont: .systemFont(ofSize: 13))
            let shouldScroll = textWidth > geometry.size.width
            
            if shouldScroll {
                HStack(spacing: 50) {
                    Text(text)
                        .font(.system(size: 13))
                    Text(text)
                        .font(.system(size: 13))
                }
                .offset(x: animate ? -textWidth - 50 : 0)
                .onAppear {
                    withAnimation(.linear(duration: Double(textWidth) / 40).repeatForever(autoreverses: false)) {
                        animate = true
                    }
                }
            } else {
                Text(text)
                    .font(.system(size: 13))
                    .frame(width: geometry.size.width, alignment: .leading)
            }
        }
        .clipped()
    }
}

extension String {
    func widthOfString(usingFont font: NSFont) -> CGFloat {
        let attributes = [NSAttributedString.Key.font: font]
        let size = (self as NSString).size(withAttributes: attributes)
        return size.width
    }
}