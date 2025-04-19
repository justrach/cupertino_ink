import SwiftUI
import Combine

// Define the custom color
// let hdrCoralBlue = Color(red: 0.1, green: 0.7, blue: 0.9)

struct SplashScreenView: View {
    // State to control the text visibility/animation
    @State private var showText: Bool = false
    @State private var fadeOutText: Bool = false

    // Callback to notify the main app when the splash is finished
    var onFinished: () -> Void

    // Animation timings
    let textFadeInDuration: Double = 0.6
    let textDisplayDuration: Double = 1.5
    let textFadeOutDuration: Double = 0.6
    let totalDurationBeforeFinish: Double = 0.2 // Short pause after fade out

    var body: some View {
        ZStack {
            // Orange background
            Color.nuevoOrange
                .edgesIgnoringSafeArea(.all)

            // Text Overlay
            // VStack(spacing: 0) { // Removed VStack
                // Text("welcome to")
                //     .font(.system(size: 24, weight: .light))
                //     .textCase(.lowercase)
                //     .foregroundColor(.white.opacity(0.8))

                Text("cupertino.ink")
                    .font(.system(size: 60, weight: .heavy)) // Use heavy weight and larger size
                    .textCase(.lowercase)
                    .foregroundColor(.white) // Use solid white for better contrast
            // }
            // Animate opacity based on state
            .opacity(showText ? (fadeOutText ? 0.0 : 1.0) : 0.0)
            // Optional: add a slight scale effect on fade out
            // .scaleEffect(fadeOutText ? 0.95 : 1.0)

        }
        .onAppear {
            // Sequence the animation
            // 1. Fade in text
            withAnimation(.easeIn(duration: textFadeInDuration)) {
                showText = true
            }

            // 2. Wait, then start fade out
            let fadeOutStartTime = textFadeInDuration + textDisplayDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeOutStartTime) {
                 withAnimation(.easeOut(duration: textFadeOutDuration)) {
                    fadeOutText = true
                 }
            }

            // 3. Wait for fade out to finish, then call onFinished
            let totalDuration = fadeOutStartTime + textFadeOutDuration + totalDurationBeforeFinish
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
                 onFinished()
            }
        }
    }
}

#Preview {
    SplashScreenView(onFinished: { print("Splash finished!") })
        .preferredColorScheme(.dark) // Preview with dark scheme to match orange background intent
} 