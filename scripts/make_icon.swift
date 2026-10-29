// Genera App/Icon/Biblia-1024.png (cruz latina crema sobre índigo) y Biblia.icns.
// Uso: swift scripts/make_icon.swift   (diseño original dibujado con CoreGraphics)
import AppKit
import Foundation

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Cuerpo "squircle" de 824 px con margen de 100 px (plantilla macOS).
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
func squircle(_ r: CGRect) -> CGPath {
    // Superelipse n=5 aproxima la curvatura continua de macOS.
    let p = CGMutablePath(); let n = 5.0
    let cx = r.midX, cy = r.midY, a = r.width / 2
    for i in 0...360 {
        let t = Double(i) * .pi / 180
        let c = cos(t), s = sin(t)
        let x = cx + a * CGFloat(copysign(pow(abs(c), 2 / n), c))
        let y = cy + a * CGFloat(copysign(pow(abs(s), 2 / n), s))
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath(); return p
}
let bodyPath = squircle(body)

// Sombra suave
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x2C3470)); ctx.fillPath()
ctx.restoreGState()

// Fondo: degradado índigo claro (arriba) -> oscuro (abajo)
ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
let grad = CGGradient(colorsSpace: cs, colors: [rgb(0x4A5DB8), rgb(0x2C3470)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// Cruz latina (crema). Medidas sobre el cuerpo de 824 px:
// altura 520, brazos 372 de ancho total, grosor 116 (14 %), travesaño con su centro a 1/3 de la altura,
// centrada ópticamente 14 px por encima del centro geométrico.
let H: CGFloat = 520, W: CGFloat = 372, t: CGFloat = 116
let top: CGFloat = 512 + H / 2 + 14, bot = top - H
let barY = top - H / 3                       // centro del travesaño
let vx0 = 512 - t / 2, vx1 = 512 + t / 2
let hx0 = 512 - W / 2, hx1 = 512 + W / 2
let hy1 = barY + t / 2, hy0 = barY - t / 2
let cross = CGMutablePath()
cross.addLines(between: [
    CGPoint(x: vx0, y: top), CGPoint(x: vx1, y: top), CGPoint(x: vx1, y: hy1), CGPoint(x: hx1, y: hy1),
    CGPoint(x: hx1, y: hy0), CGPoint(x: vx1, y: hy0), CGPoint(x: vx1, y: bot), CGPoint(x: vx0, y: bot),
    CGPoint(x: vx0, y: hy0), CGPoint(x: hx0, y: hy0), CGPoint(x: hx0, y: hy1), CGPoint(x: vx0, y: hy1)])
cross.closeSubpath()
let rounded = cross.copy(strokingWithWidth: 8, lineCap: .round, lineJoin: .round, miterLimit: 1)
// sombra muy suave
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: rgb(0x0B0F2E, 0.45))
ctx.addPath(cross); ctx.addPath(rounded); ctx.setFillColor(rgb(0xF4ECD8)); ctx.fillPath()
ctx.restoreGState()
// relleno con degradado sutil
ctx.saveGState()
ctx.addPath(cross); ctx.addPath(rounded); ctx.clip()
let cg = CGGradient(colorsSpace: cs, colors: [rgb(0xFFF9EA), rgb(0xEADFC0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(cg, start: CGPoint(x: 512, y: top), end: CGPoint(x: 512, y: bot), options: [])
ctx.restoreGState()
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/Icon/Biblia-1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
