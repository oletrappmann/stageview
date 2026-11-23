import SwiftUI

/// Zeitleiste des Players: dünne Spur, wird beim Anfassen dicker. Kommentare als Marken (offen hell, erledigt blass).
/// Ziehen spult, darüber steht eine Blase mit Zeit und Standbild der Stelle, jede überfahrene Marke gibt einen leichten Tick.
struct Scrubber: View {
    let time: Double
    let duration: Double
    let markers: [(time: Double, open: Bool)]
    let video: Video
    let seek: (Double, Bool) -> Void
    var scrubbing: Binding<Bool>
    /// Senkrecht gewischt: das gehört dem Blatt (Weg, Tempo, losgelassen), wie im Web (blatt-kopf schließt die Zeitleiste ein)
    var vertical: ((CGFloat, CGFloat, Bool) -> Void)?

    @State private var dragTime: Double?
    @State private var lastMarker: Int?
    @State private var mode: Mode?
    private enum Mode { case scrub, vertical }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let shown = dragTime ?? time
            let fraction = duration > 0 ? min(max(shown / duration, 0), 1) : 0
            let active = dragTime != nil
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18)).frame(height: active ? 8 : 4)
                Capsule().fill(Color.white).frame(width: max(active ? 8 : 4, width * fraction), height: active ? 8 : 4)
                ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
                    let x = duration > 0 ? width * min(max(marker.time / duration, 0), 1) : 0
                    Circle()
                        .fill(marker.open ? Palette.pending : Color.white.opacity(0.35))
                        .frame(width: active ? 9 : 7, height: active ? 9 : 7)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                        .offset(x: x - (active ? 4.5 : 3.5))
                }
                Circle()
                    .fill(Color.white)
                    .frame(width: active ? 20 : 12, height: active ? 20 : 12)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .offset(x: width * fraction - (active ? 10 : 6))
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) {
                if let dragTime {
                    ScrubBubble(video: video, time: dragTime)
                        .offset(x: min(max(width * fraction - 56, 0), width - 112), y: -132)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        if mode == nil {
                            // Erst klar seitlich wird gespult, klar senkrecht zieht das Blatt, ein Tipper springt beim Loslassen
                            let dx = abs(value.translation.width), dy = abs(value.translation.height)
                            if vertical != nil && dy > 8 && dy > dx { mode = .vertical }
                            else if dx > 4 { mode = .scrub; scrubbing.wrappedValue = true; Haptics.select() }
                            else { return }
                        }
                        if mode == .vertical { vertical?(value.translation.height, value.velocity.height, false); return }
                        let t = min(max(value.location.x / width, 0), 1) * duration
                        withAnimation(.easeOut(duration: 0.12)) { dragTime = t }
                        tickMarkers(near: t, width: width)
                        seek(t, false)
                    }
                    .onEnded { value in
                        defer { mode = nil; lastMarker = nil }
                        if mode == .vertical { vertical?(value.translation.height, value.velocity.height, true); return }
                        guard duration > 0 else { return }
                        let t = min(max(value.location.x / width, 0), 1) * duration
                        seek(t, true)
                        withAnimation(.easeOut(duration: 0.18)) { dragTime = nil }
                        scrubbing.wrappedValue = false
                    }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: active)
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityLabel("Zeitleiste")
        .accessibilityValue("\(Clock.text(time)) von \(Clock.text(duration))")
        .accessibilityAdjustableAction { direction in
            seek(direction == .increment ? min(duration, time + 5) : max(0, time - 5), true)
        }
        .accessibilityIdentifier("zeitleiste")
    }

    /// Tick, sobald der Finger über eine Marke läuft (6 pt Fangbereich)
    private func tickMarkers(near t: Double, width: CGFloat) {
        guard duration > 0 else { return }
        let hit = markers.firstIndex { abs(($0.time - t) / duration * width) < 6 }
        if let hit, hit != lastMarker { Haptics.marker() }
        lastMarker = hit
    }
}

/// Blase beim Spulen: Standbild der Stelle von Mux und die Zeit
private struct ScrubBubble: View {
    let video: Video
    let time: Double

    var body: some View {
        VStack(spacing: 6) {
            RemoteImage(url: video.thumbnail(width: 240, at: (time / 2).rounded() * 2), placeholder: Color.white.opacity(0.08))
                .frame(width: 112, height: video.portrait ? 92 : 63)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(Clock.text(time))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .glassEffect(.regular, in: .capsule)
        }
        .frame(width: 112)
        .allowsHitTesting(false)
    }
}
