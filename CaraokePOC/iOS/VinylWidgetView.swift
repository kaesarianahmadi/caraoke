import SwiftUI
import WidgetKit
import AppIntents

/// Vinyl record widget with rotating animation and tap-to-refresh
/// Matches competitor design from IMG_5103 and IMG_5105
struct VinylWidgetView: View {
    let entry: CaraokeWidgetEntry
    @State private var rotationAngle: Double = 0
    @Environment(\.widgetFamily) private var family
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left side: Lyrics
                lyricsSection
                    .frame(width: geometry.size.width * 0.6)
                
                // Right side: Vinyl record
                vinylSection
                    .frame(width: geometry.size.width * 0.4)
            }
        }
        .containerBackground(for: .widget) {
            backgroundGradient
        }
        .widgetURL(URL(string: "caraoke://lyrics"))
    }
    
    // MARK: - Lyrics Section
    
    private var lyricsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(entry.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            Spacer()
            
            // Current lyric (active, bold, larger)
            Text(entry.currentLine)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 16)
            
            // Next lyric (dimmed)
            if let nextLine = entry.nextLine {
                Text(nextLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                    .padding(.horizontal, 16)
            }
            
            Spacer()
            
            // Transport controls
            HStack(spacing: 20) {
                Button(intent: PreviousTrackIntent()) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                
                Button(intent: PlayPauseIntent()) {
                    Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Button(intent: NextTrackIntent()) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Vinyl Section
    
    private var vinylSection: some View {
        ZStack {
            // Vinyl record
            vinylRecord
                .rotationEffect(.degrees(entry.isPlaying ? rotationAngle : 0))
                .onAppear {
                    if entry.isPlaying {
                        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                            rotationAngle = 360
                        }
                    }
                }
                .onChange(of: entry.isPlaying) { _, isPlaying in
                    if isPlaying {
                        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                            rotationAngle = 360
                        }
                    } else {
                        withAnimation(.default) {
                            rotationAngle = 0
                        }
                    }
                }
            
            // Refresh button overlay (tap to resync)
            Button(intent: ResyncWidgetIntent()) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var vinylRecord: some View {
        ZStack {
            // Outer vinyl disc
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black,
                            Color(white: 0.15),
                            Color.black
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 100
                    )
                )
                .frame(width: 120, height: 120)
            
            // Vinyl grooves
            ForEach(0..<8) { i in
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    .frame(width: CGFloat(100 - i * 10), height: CGFloat(100 - i * 10))
            }
            
            // Album art center
            if let artworkData = entry.artworkData,
               let uiImage = UIImage(data: artworkData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.5))
                    )
            }
            
            // Center spindle
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 8, height: 8)
        }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        // Extract colors from album art or use default
        if let artworkData = entry.artworkData,
           let uiImage = UIImage(data: artworkData),
           let avgColor = uiImage.averageColor {
            return LinearGradient(
                colors: [
                    Color(avgColor).opacity(0.8),
                    Color(avgColor).opacity(0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.15),
                    Color(red: 0.05, green: 0.05, blue: 0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - UIImage Extension for Average Color

extension UIImage {
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extentVector = CIVector(x: inputImage.extent.origin.x,
                                    y: inputImage.extent.origin.y,
                                    z: inputImage.extent.size.width,
                                    w: inputImage.extent.size.height)
        
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: inputImage,
                                                 kCIInputExtentKey: extentVector]) else { return nil }
        guard let outputImage = filter.outputImage else { return nil }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(outputImage,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: nil)
        
        return UIColor(red: CGFloat(bitmap[0]) / 255,
                       green: CGFloat(bitmap[1]) / 255,
                       blue: CGFloat(bitmap[2]) / 255,
                       alpha: CGFloat(bitmap[3]) / 255)
    }
}

// MARK: - Preview

#if DEBUG
struct VinylWidgetView_Previews: PreviewProvider {
    static var previews: some View {
        VinylWidgetView(entry: CaraokeWidgetEntry(
            title: "Hati-Hati di Jalan",
            artist: "Tulus",
            currentLine: "Kukira kita akan bersama",
            nextLine: "Tak seindah itu",
            isPlaying: true,
            progress: 0.45,
            status: .playing
        ))
        .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}
#endif
