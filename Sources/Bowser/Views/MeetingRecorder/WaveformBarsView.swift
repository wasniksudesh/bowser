// WaveformBarsView.swift - Simple pulsing recording indicator
// Replaces the multi-bar waveform to avoid a layout-phase crash.

import SwiftUI

struct WaveformBarsView: View {

    var isAnimating: Bool
    var isPaused: Bool = false
    var color: Color = .red
    var barCount: Int = 5
    var audioLevel: Float = 0.0

    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(pulse && isAnimating && !isPaused ? 1.4 : 1.0)
            .opacity(isPaused ? 0.4 : 1.0)
            .animation(
                isAnimating && !isPaused
                    ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                    : .default,
                value: pulse
            )
            .onAppear { pulse = true }
            .onChange(of: isAnimating) { _, on in pulse = on }
    }
}
