//
//  GuidelineOverlay.swift
//  SerialNumberScanner
//
//  Green guideline box overlay for camera view
//

import SwiftUI

struct GuidelineOverlay: View {
    // Guide box is 70% width, 60% height
    private let widthRatio: CGFloat = 0.7
    private let heightRatio: CGFloat = 0.6
    private let cornerLength: CGFloat = 40
    private let lineWidth: CGFloat = 4
    private let cornerWidth: CGFloat = 6
    private let guideColor = Color.green
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * widthRatio
            let height = geometry.size.height * heightRatio
            let x = (geometry.size.width - width) / 2
            let y = (geometry.size.height - height) / 2
            
            ZStack {
                // Semi-transparent overlay outside the box
                DimmingOverlay(
                    boxX: x,
                    boxY: y,
                    boxWidth: width,
                    boxHeight: height
                )
                
                // Main guideline rectangle
                Rectangle()
                    .stroke(guideColor, lineWidth: lineWidth)
                    .frame(width: width, height: height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Corner markers
                CornerMarkers(
                    x: x,
                    y: y,
                    width: width,
                    height: height,
                    cornerLength: cornerLength,
                    cornerWidth: cornerWidth,
                    color: guideColor
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Dimming Overlay
struct DimmingOverlay: View {
    let boxX: CGFloat
    let boxY: CGFloat
    let boxWidth: CGFloat
    let boxHeight: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                // Full screen rectangle
                path.addRect(CGRect(x: 0, y: 0, width: geometry.size.width, height: geometry.size.height))
                
                // Cutout for the guide box
                path.addRect(CGRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight))
            }
            .fill(Color.black.opacity(0.3), style: FillStyle(eoFill: true))
        }
    }
}

// MARK: - Corner Markers
struct CornerMarkers: View {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let cornerLength: CGFloat
    let cornerWidth: CGFloat
    let color: Color
    
    var body: some View {
        Canvas { context, size in
            // Top Left
            drawCorner(context: context, 
                      x: x, y: y,
                      horizontal: 1, vertical: 1)
            
            // Top Right
            drawCorner(context: context,
                      x: x + width, y: y,
                      horizontal: -1, vertical: 1)
            
            // Bottom Left
            drawCorner(context: context,
                      x: x, y: y + height,
                      horizontal: 1, vertical: -1)
            
            // Bottom Right
            drawCorner(context: context,
                      x: x + width, y: y + height,
                      horizontal: -1, vertical: -1)
        }
    }
    
    private func drawCorner(context: GraphicsContext, x: CGFloat, y: CGFloat, horizontal: CGFloat, vertical: CGFloat) {
        var path = Path()
        
        // Horizontal line
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x + cornerLength * horizontal, y: y))
        
        // Vertical line
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x, y: y + cornerLength * vertical))
        
        context.stroke(path, with: .color(color), lineWidth: cornerWidth)
    }
}

#Preview {
    ZStack {
        Color.gray
        GuidelineOverlay()
    }
}
