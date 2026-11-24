import CoreImage
import SwiftUI
import UIKit

enum D {
    static let bg = Color(red: 0.082, green: 0.106, blue: 0.133)
    static let card = Color(red: 0.114, green: 0.145, blue: 0.184)
    static let raised = Color(red: 0.149, green: 0.196, blue: 0.251)
    static let line = Color(red: 0.165, green: 0.208, blue: 0.259)
    static let ink = Color(red: 0.949, green: 0.961, blue: 0.973)
    static let muted = Color(red: 0.604, green: 0.655, blue: 0.714)
    static let amber = Color(red: 1.0, green: 0.773, blue: 0.2)
    static let green = Color(red: 0.243, green: 0.812, blue: 0.557)
    static let red = Color(red: 1.0, green: 0.365, blue: 0.365)
}

extension View {
    func panel(stroke: Color = D.line, width: CGFloat = 1) -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(D.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(stroke, lineWidth: width))
    }
}

struct BigButton: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(filled ? Color.black : D.ink)
            .background((filled ? D.amber : D.raised).opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct TruckDiagram: View {
    let move: Move?

    var body: some View {
        Canvas { ctx, size in
            let w = size.width / 360, h = size.height / 120
            func r(_ x: CGFloat, _ y: CGFloat, _ ww: CGFloat, _ hh: CGFloat) -> CGRect { CGRect(x: x * w, y: y * h, width: ww * w, height: hh * h) }
            func wheel(_ x: CGFloat, _ color: Color) {
                let c = Path(ellipseIn: r(x - 12, 76, 24, 24))
                ctx.fill(c, with: .color(.black))
                ctx.stroke(c, with: .color(color), lineWidth: 3)
            }
            let fifth = CGFloat(move?.notches ?? 0) * 3
            let slide = CGFloat(move?.holes ?? 0) * -5
            ctx.fill(Path(roundedRect: r(10, 30, 62, 52), cornerRadius: 8), with: .color(Color(red: 0.23, green: 0.27, blue: 0.33)))
            ctx.fill(Path(roundedRect: r(18, 38, 26, 20), cornerRadius: 3), with: .color(Color(red: 0.56, green: 0.70, blue: 0.85)))
            ctx.fill(Path(r(70, 64, 42, 10)), with: .color(Color(red: 0.23, green: 0.27, blue: 0.33)))
            ctx.fill(Path(roundedRect: r(100, 22, 250, 52), cornerRadius: 4), with: .color(Color(red: 0.17, green: 0.20, blue: 0.25)))
            ctx.stroke(Path(roundedRect: r(100, 22, 250, 52), cornerRadius: 4), with: .color(Color(red: 0.34, green: 0.40, blue: 0.48)), lineWidth: 1)
            ctx.fill(Path(r(92 + fifth, 70, 22, 6)), with: .color((move?.notches ?? 0) != 0 ? D.amber : D.muted))
            wheel(34, D.muted)
            wheel(84, D.muted)
            wheel(110, D.muted)
            let tandemColor = (move?.holes ?? 0) != 0 ? D.amber : D.muted
            wheel(290 + slide, tandemColor)
            wheel(316 + slide, tandemColor)
            if let holes = move?.holes, holes != 0 {
                var arrow = Path()
                let y = 112 * h
                let from = (holes > 0 ? 300 : 230) * w, to = (holes > 0 ? 230 : 300) * w
                arrow.move(to: CGPoint(x: from, y: y)); arrow.addLine(to: CGPoint(x: to, y: y))
                ctx.stroke(arrow, with: .color(D.amber), lineWidth: 4)
                var head = Path()
                let dir: CGFloat = holes > 0 ? -1 : 1
                head.move(to: CGPoint(x: to + dir * 10 * w, y: y))
                head.addLine(to: CGPoint(x: to - dir * 4 * w, y: y - 7 * h))
                head.addLine(to: CGPoint(x: to - dir * 4 * w, y: y + 7 * h))
                head.closeSubpath()
                ctx.fill(head, with: .color(D.amber))
            }
        }
        .frame(height: 120)
        .accessibilityHidden(true)
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

enum QR {
    static let link: String = {
        let id = (Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String ?? "").trimmingCharacters(in: .whitespaces)
        return id.isEmpty || id.hasPrefix("$") ? "https://hgsldswk-alt.github.io/tandemslide-support/" : "https://apps.apple.com/app/id\(id)"
    }()

    static func image() -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(link.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
