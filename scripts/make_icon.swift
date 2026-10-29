// Genera App/Icon/Biblia-1024.png (concepto A "Dos voces, un texto") y Biblia.icns.
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

// Dos columnas que se solapan
let h: CGFloat = 480, w: CGFloat = 270, y0: CGFloat = 272, r: CGFloat = 44
let left = CGRect(x: 286, y: y0, width: w, height: h)
let right = CGRect(x: 468, y: y0, width: w, height: h)
let rp: (CGRect) -> CGPath = { CGPath(roundedRect: $0, cornerWidth: r, cornerHeight: r, transform: nil) }
ctx.addPath(rp(left)); ctx.setFillColor(rgb(0xF4ECD8)); ctx.fillPath()           // sepia
ctx.addPath(rp(right)); ctx.setFillColor(rgb(0x9DB0FF)); ctx.fillPath()          // índigo claro (tema oscuro)
// Zona de solape ámbar
let ov = left.intersection(right)
ctx.saveGState()
ctx.addPath(rp(left)); ctx.clip()
ctx.addPath(rp(right)); ctx.clip()
ctx.setFillColor(rgb(0xD9B24A)); ctx.fill(ov)
ctx.restoreGState()
// Punto (la palabra con Strong)
let dot = CGRect(x: ov.midX - 30, y: ov.midY - 30, width: 60, height: 60)
ctx.setFillColor(rgb(0x2C3470)); ctx.fillEllipse(in: dot)
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/Icon/Biblia-1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
