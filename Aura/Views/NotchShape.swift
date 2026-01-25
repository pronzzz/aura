import SwiftUI

/// Custom shape that creates the notch-like pill with rounded corners
struct NotchShape: Shape {
    var cornerRadius: CGFloat
    
    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
    }
}

// MARK: - Extended Notch Shape with Cutout

/// Alternative shape that can include a notch cutout at the top
struct NotchCutoutShape: Shape {
    var cornerRadius: CGFloat
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let notchX = (rect.width - notchWidth) / 2
        
        // Start from bottom-left
        path.move(to: CGPoint(x: 0, y: rect.height))
        
        // Left edge up to top
        path.addLine(to: CGPoint(x: 0, y: cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: cornerRadius, y: 0),
            control: CGPoint(x: 0, y: 0)
        )
        
        // Top edge to notch start
        path.addLine(to: CGPoint(x: notchX, y: 0))
        
        // Notch cutout (curved corners)
        path.addQuadCurve(
            to: CGPoint(x: notchX + 10, y: notchHeight),
            control: CGPoint(x: notchX, y: notchHeight)
        )
        path.addLine(to: CGPoint(x: notchX + notchWidth - 10, y: notchHeight))
        path.addQuadCurve(
            to: CGPoint(x: notchX + notchWidth, y: 0),
            control: CGPoint(x: notchX + notchWidth, y: notchHeight)
        )
        
        // Top edge from notch to right
        path.addLine(to: CGPoint(x: rect.width - cornerRadius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: cornerRadius),
            control: CGPoint(x: rect.width, y: 0)
        )
        
        // Right edge down
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.width - cornerRadius, y: rect.height),
            control: CGPoint(x: rect.width, y: rect.height)
        )
        
        // Bottom edge back to start
        path.addLine(to: CGPoint(x: cornerRadius, y: rect.height))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.height - cornerRadius),
            control: CGPoint(x: 0, y: rect.height)
        )
        
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Preview

#Preview("Notch Shape") {
    NotchShape(cornerRadius: 20)
        .fill(.black.opacity(0.9))
        .frame(width: 300, height: 140)
        .padding()
}

#Preview("Notch Cutout Shape") {
    NotchCutoutShape(cornerRadius: 20, notchWidth: 200, notchHeight: 32)
        .fill(.black.opacity(0.9))
        .frame(width: 350, height: 140)
        .padding()
}
