import SwiftUI
import MetalKit

// MARK: - Metal View Representable

struct MetalViewRepresentable: NSViewRepresentable {
    @Binding var time: Float // To control the animation

    func makeCoordinator() -> MetalRenderer {
        MetalRenderer(self)
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = true

        if let metalDevice = MTLCreateSystemDefaultDevice() {
            mtkView.device = metalDevice
        } else {
            print("Metal is not supported on this device")
        }

        mtkView.framebufferOnly = true // Let's try true - might simplify transparency handling
        mtkView.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0) // Transparent background
        mtkView.drawableSize = mtkView.frame.size

        // Explicitly make the underlying CALayer transparent
        // mtkView.wantsLayer = true // Ensure it has a layer
        // mtkView.layer?.isOpaque = false
        // mtkView.layer?.backgroundColor = NSColor.clear.cgColor

        mtkView.isPaused = false // Start rendering immediately

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // Update the renderer's time uniform
        context.coordinator.setTime(time)
        // Request a redraw when the time binding changes
        nsView.needsDisplay = true
    }
}

// MARK: - Metal Renderer (MTKViewDelegate)

class MetalRenderer: NSObject, MTKViewDelegate {
    var parent: MetalViewRepresentable
    var metalDevice: MTLDevice!
    var metalCommandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    var time: Float = 0.0

    // We'll likely need a noise texture for the dissolve effect later
    // var noiseTexture: MTLTexture?

    init(_ parent: MetalViewRepresentable) {
        self.parent = parent
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.metalDevice = metalDevice
        } else {
            fatalError("Metal is not supported on this device")
        }
        self.metalCommandQueue = metalDevice.makeCommandQueue()!

        super.init()

        setupPipeline()
        // loadNoiseTexture() // We'll add this later
    }

    func setupPipeline() {
        let library = metalDevice.makeDefaultLibrary()!
        let vertexFunction = library.makeFunction(name: "vertex_main")
        // Use the new dissolve fragment shader
        let fragmentFunction = library.makeFunction(name: "fragment_dissolve")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm // Common format
        // Re-enable standard alpha blending for mask
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }

    // func loadNoiseTexture() { ... } // TODO: Implement noise texture loading

    func setTime(_ newTime: Float) {
        self.time = newTime
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle view resizing if necessary
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        // Make background transparent
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        let commandBuffer = metalCommandQueue.makeCommandBuffer()!
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!

        renderEncoder.setRenderPipelineState(pipelineState)

        // Pass the current time uniform to the fragment shader
        var currentTime = self.time
        renderEncoder.setFragmentBytes(&currentTime, length: MemoryLayout<Float>.size, index: 0) // Buffer index 0 for Uniforms struct

        // Draw a full-screen quad (4 vertices, triangle strip)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        // commandBuffer.waitUntilCompleted() // Optional: wait if needed, usually not for display link
    }
} 