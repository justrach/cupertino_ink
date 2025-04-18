import SwiftUI
import MetalKit

// MARK: - Metal View Representable

struct MetalViewRepresentable: NSViewRepresentable {
    // Get the current color scheme
    @Environment(\.colorScheme) var colorScheme

    func makeCoordinator() -> MetalRenderer {
        MetalRenderer(self, colorScheme: colorScheme)
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60 // Can be lower for static bg if needed
        mtkView.enableSetNeedsDisplay = false // Doesn't need constant redraws
        mtkView.isPaused = false // Draw once

        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        mtkView.device = metalDevice

        // --- EDR Configuration ---
        mtkView.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        // Try using a float format suitable for HDR
        mtkView.colorPixelFormat = .rgba16Float
        // Request EDR capabilities via the layer
        // Ensure layer exists (MTKView usually creates one automatically)
        mtkView.layer?.wantsExtendedDynamicRangeContent = true
        // --- End EDR Configuration ---

        mtkView.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0) // Clear to black initially
        mtkView.drawableSize = mtkView.frame.size

        // Ensure it's opaque - it's the background
        mtkView.layer?.isOpaque = true

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // Update the color scheme if it changes
        context.coordinator.setColorScheme(colorScheme)
        // Trigger a redraw if the scheme changes (though it's static now, good practice)
        if context.coordinator.needsRedrawForColorScheme { // Add flag in coordinator
             nsView.isPaused = false // Allow redraw
             context.coordinator.needsRedrawForColorScheme = false
        }
    }
}

// MARK: - Metal Renderer (MTKViewDelegate)

class MetalRenderer: NSObject, MTKViewDelegate {
    var parent: MetalViewRepresentable
    var metalDevice: MTLDevice!
    var metalCommandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    var currentColorScheme: ColorScheme // Store the scheme
    var needsRedrawForColorScheme: Bool = false // Flag for updateNSView

    // Uniform buffer for color scheme (0 = light, 1 = dark)
    struct Uniforms {
        var colorScheme: Int32
    }

    init(_ parent: MetalViewRepresentable, colorScheme: ColorScheme) {
        self.parent = parent
        self.currentColorScheme = colorScheme
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.metalDevice = metalDevice
        } else {
            fatalError("Metal is not supported on this device")
        }
        self.metalCommandQueue = metalDevice.makeCommandQueue()!
        super.init()
        setupPipeline()
    }

    func setColorScheme(_ newScheme: ColorScheme) {
        if newScheme != currentColorScheme {
            currentColorScheme = newScheme
            needsRedrawForColorScheme = true
        }
    }

    func setupPipeline() {
        guard let library = metalDevice.makeDefaultLibrary() else {
             fatalError("Failed to load default Metal library")
        }
        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_hdr_background") // New shader name

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba16Float // Match view's format

        // Background should be opaque, disable blending
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = false

        do {
            pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle view resizing if necessary
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else { return }

        // Don't clear, just draw over
        renderPassDescriptor.colorAttachments[0].loadAction = .dontCare

        let commandBuffer = metalCommandQueue.makeCommandBuffer()!
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        renderEncoder.setRenderPipelineState(pipelineState)

        // Pass color scheme uniform to fragment shader
        var uniforms = Uniforms(colorScheme: Int32(currentColorScheme == .dark ? 1 : 0))
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        // Since it's static, pause the view after the first draw
        view.isPaused = true
    }
} 