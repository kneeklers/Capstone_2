//
//  BoundingBoxOverlay.swift
//  SerialNumberScanner
//
//  Draws bounding box around detected serial plate
//

import SwiftUI

struct BoundingBoxOverlay: View {
    /// Observe detector directly so the overlay re-renders on every feedback change (fixes
    /// "box only updates on toggle" on some devices where parent view observation is inconsistent).
    @ObservedObject var detector: YOLODetector
    let showBox: Bool

    private var feedback: DetectionFeedback { detector.feedback }

    // Box styling
    private let cornerRadius: CGFloat = 8
    private let lineWidth: CGFloat = 3
    private let cornerLength: CGFloat = 25
    private let cornerLineWidth: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            if showBox && feedback.detected {
                let box = convertBoundingBox(feedback.boundingBox, in: geometry.size)
                
                ZStack {
                    // Main bounding box
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(boxColor, lineWidth: lineWidth)
                        .frame(width: box.width, height: box.height)
                        .position(x: box.midX, y: box.midY)
                    
                    // Corner accents for better visibility
                    CornersView(rect: box, color: boxColor, cornerLength: cornerLength, lineWidth: cornerLineWidth)
                    
                    // Confidence label
                    ConfidenceLabel(confidence: feedback.confidence, color: boxColor)
                        .position(x: box.midX, y: box.minY - 20)
                }
                .animation(.easeInOut(duration: 0.1), value: feedback.boundingBox)
            }
        }
        .allowsHitTesting(false)
    }
    
    // Convert Vision coordinates (0-1, bottom-left origin) to UIKit coordinates
    private func convertBoundingBox(_ box: CGRect, in size: CGSize) -> CGRect {
        // Vision uses bottom-left origin, UIKit uses top-left
        let x = box.origin.x * size.width
        let y = (1 - box.origin.y - box.height) * size.height  // Flip Y
        let width = box.width * size.width
        let height = box.height * size.height
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    // Color based on detection quality
    private var boxColor: Color {
        switch feedback.quality {
        case .perfect:
            return .green
        case .adjust:
            return .orange
        case .warning:
            return .yellow
        case .bad, .searching:
            return .red
        }
    }
}

// MARK: - Corner Accents
struct CornersView: View {
    let rect: CGRect
    let color: Color
    let cornerLength: CGFloat
    let lineWidth: CGFloat
    
    var body: some View {
        Canvas { context, size in
            let path = createCornersPath()
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }
    
    private func createCornersPath() -> Path {
        var path = Path()
        
        // Top-left corner
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
        
        // Top-right corner
        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
        
        // Bottom-left corner
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
        
        // Bottom-right corner
        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
        
        return path
    }
}

// MARK: - Confidence Label
struct ConfidenceLabel: View {
    let confidence: Float
    let color: Color
    
    var body: some View {
        Text("\(Int(confidence * 100))%")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            )
    }
}

#Preview {
    ZStack {
        Color.gray
        BoundingBoxOverlay(
            detector: YOLODetector(),
            showBox: true
        )
    }
}
