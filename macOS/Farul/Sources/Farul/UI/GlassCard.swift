import SwiftUI
import AppKit

/// Sticla mată de sub panouri. SwiftUI-ul nativ acoperă aproape tot, dar nu
/// poate cere un material de FEREASTRĂ (`.underWindowBackground`) — de aceea
/// rămâne acest wrapper peste `NSVisualEffectView`.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // `.active`, nu `.followsWindowActiveState`: altfel panoul devine
        // gri mort în clipa în care fereastra pierde focusul — adică exact
        // când te uiți la altceva și vrei să vezi metricile din colț.
        view.state = .active
        view.material = material
        view.blendingMode = blending
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// Cardul standard: sticlă, contur subțire, colț rotund. Toate panourile îl
/// folosesc, ca să nu apară trei raze de colț diferite pe același ecran.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
    }
}

/// Antetul unui card: pictogramă, titlu tradus, valoare mare în dreapta.
struct CardHeader: View {
    let icon: String
    let title: K
    var value: String?
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(L.t(title))
                .font(.subheadline.weight(.medium))
            Spacer()
            if let value {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
        }
    }
}

/// Bară de progres proprie. `ProgressView` nativ nu poate fi colorat
/// semantic per prag fără să-i schimbi stilul complet, iar aici culoarea
/// chiar poartă informație: verde/galben/roșu în funcție de cât de plin e.
struct MeterBar: View {
    let fraction: Double
    var tint: Color?

    private var color: Color {
        if let tint { return tint }
        switch fraction {
        case ..<0.70: return .green
        case ..<0.90: return .yellow
        default: return .red
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
                    .animation(.easeOut(duration: 0.35), value: fraction)
            }
        }
        .frame(height: 6)
        .accessibilityValue(Format.percent(fraction))
    }
}

/// Graficul mic din carduri. Desenat cu `Path`, nu cu Charts: e o linie de
/// 60 de puncte redesenată la fiecare eșantion, iar un framework întreg
/// pentru asta ar fi mai scump decât metrica pe care o arată.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = .accentColor
    /// Maximul impus. Pentru procente e 1; pentru rețea, `nil`, ca scara
    /// să urmărească traficul real — altfel un grafic de 0…100 MB/s ar fi
    /// o linie plată pentru cineva pe o conexiune obișnuită.
    var ceiling: Double?

    var body: some View {
        GeometryReader { geometry in
            let top = max(ceiling ?? values.max() ?? 1, 0.0001)
            let width = geometry.size.width
            let height = geometry.size.height
            let step = values.count > 1 ? width / CGFloat(values.count - 1) : width

            ZStack {
                if values.count > 1 {
                    let points = values.enumerated().map { index, value in
                        CGPoint(x: CGFloat(index) * step,
                                y: height - CGFloat(min(value / top, 1)) * height)
                    }

                    Path { path in
                        path.move(to: CGPoint(x: 0, y: height))
                        path.addLine(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))

                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
        }
    }
}
