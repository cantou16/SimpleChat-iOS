import SwiftUI

/// iOS 端的玻璃质感表面。
///
/// 对齐 iOS 26 的 Liquid Glass 观感：半透明材质 + 顶部高光描边 + 柔和投影。
/// 不依赖 iOS 26 的新 API（`.glassEffect`），因此 iOS 16+ 都能编译与运行；
/// 真机上会跟随系统材质与深浅色自动变化。
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 20
    var tint: Color = .clear
    var strong: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if tint != .clear {
                        shape.fill(tint.opacity(strong ? 0.22 : 0.10))
                    }
                    shape.stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.70), Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
                }
                .compositingGroup()
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = 20, tint: Color = .clear, strong: Bool = false) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint, strong: strong))
    }
}
