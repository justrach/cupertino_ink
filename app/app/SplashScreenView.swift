import SwiftUI
import Combine // For Timer

struct SplashScreenView: View {
    // State to control the overall visibility and animation progress
    @State private var isActive: Bool = false
    @State private var showText: Bool = false
    @State private var startDissolve: Bool = false
    @State private var animationTime: Float = 0.0 // Drives the Metal shader

    // Callback to notify the main app when the splash is finished
    var onFinished: () -> Void

    // Animation timings
    let textFadeInDuration: Double = 0.5
    let textDisplayDuration: Double = 1.5
    let dissolveDuration: Double = 1.5 // Duration for the dissolve effect (0.0 to 1.0)
    let totalDurationBeforeFinish: Double = 0.5 // Extra time after dissolve finishes

    var body: some View {
        ZStack {
            // Background color for the whole splash screen
            Color.black.edgesIgnoringSafeArea(.all)

            // Text Overlay - Mask will be applied here
            VStack(spacing: 0) {
                Text("welcome to")
                    .font(.system(size: 24, weight: .light))
                    .textCase(.lowercase)
                    .foregroundColor(.white.opacity(0.8))

                Text("cupertino.ink")
                    .font(.system(size: 48, weight: .bold))
                    .textCase(.lowercase)
                    .foregroundColor(.white)
            }
            .opacity(showText ? 1.0 : 0.0)
            // Apply the Metal view as a mask when dissolve starts
            .mask {
                 if startDissolve {
                     MetalViewRepresentable(time: $animationTime)
                         .edgesIgnoringSafeArea(.all)
                 }
                 // else - if no mask is applied, the text is fully visible (default behavior)
             }

            /* // Old BlendMode approach - REMOVED
            // Metal View - now renders the MASK and sits ON TOP
            if startDissolve {
                MetalViewRepresentable(time: $animationTime)
                    .edgesIgnoringSafeArea(.all)
                    // Use the mask's luminance to control the destination (text) alpha
                    .blendMode(.destinationIn) // <<< ERROR HERE
                    .transition(.opacity) // Optional fade for the mask view itself if needed
            }
            */

        }
        // .background(Color.black) // Background moved to ZStack
        .onAppear {
            // Sequence the animation
            // 1. Fade in text (instantly, or with short fade)
            withAnimation(.easeIn(duration: textFadeInDuration)) {
                showText = true
            }

            // 2. Wait, then start dissolve
            DispatchQueue.main.asyncAfter(deadline: .now() + textFadeInDuration + textDisplayDuration) {
                withAnimation(.easeIn(duration: 0.1)) { // Quickly enable metal view
                     startDissolve = true
                }
                // Start animating the time uniform for the shader
                 withAnimation(.linear(duration: dissolveDuration)) {
                    animationTime = 1.0
                 }
            }

            // 3. Wait for dissolve to finish, then call onFinished
            let totalDuration = textFadeInDuration + textDisplayDuration + dissolveDuration + totalDurationBeforeFinish
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
                 onFinished()
            }
        }
    }
}

#Preview {
    SplashScreenView(onFinished: { print("Splash finished!") })
} 