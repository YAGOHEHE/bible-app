// Genera App/Icon/Biblia-1024.png: concepto «Códice» (v1.2).
// Libro abierto crema sobre squircle color tinta; la cruz latina es el hueco entre las páginas
// (pliegue vertical + travesaño calado) y una cinta roja de marcapáginas cae del lomo.
// Uso: swift scripts/make_icon.swift [salida.png]   (lo llama scripts/make_icon.sh)
import AppKit
import Foundation

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    // srgbRed: los hex de la paleta son sRGB (CGColor(red:…) usa Generic RGB y se aclaraban al convertir).
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
let S = 1024
// sRGB explícito: con DeviceRGB los hex de la paleta se convertían al guardar y el icono salía más claro.
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Coordenadas con origen arriba a la izquierda (como el diseño en replica/design/app-icon-brief.md).
// Las sombras se expresan en el espacio base: dy negativo = hacia abajo.
ctx.translateBy(x: 0, y: CGFloat(S)); ctx.scaleBy(x: 1, y: -1)

// Cuerpo "squircle" de 824 px con margen de 100 px (plantilla macOS), superelipse n=5.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath(); let n = 5.0
    let cx = r.midX, cy = r.midY, a = r.width / 2
    for i in 0...720 {
        let t = Double(i) * .pi / 360
        let c = cos(t), s = sin(t)
        let x = cx + a * CGFloat(copysign(pow(abs(c), 2 / n), c))
        let y = cy + a * CGFloat(copysign(pow(abs(s), 2 / n), s))
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath(); return p
}
let bodyPath = squircle(body)

// Paleta (tokens «Códice»)
let inkTop: UInt32 = 0x2C3C46, inkBottom: UInt32 = 0x131B21
let pageLeft: UInt32 = 0xEFE7D6, pageRight: UInt32 = 0xFBF6EA
let ribbonTop: UInt32 = 0xD8543B, ribbonBottom: UInt32 = 0xB23A24

let inkGradient = CGGradient(colorsSpace: cs, colors: [rgb(inkTop), rgb(inkBottom)] as CFArray, locations: [0, 1])!
func fillInk() {   // mismo degradado en coordenadas absolutas: lo calado coincide exactamente con el fondo
    ctx.drawLinearGradient(inkGradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
}

// 1. Sombra del cuerpo
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(bodyPath); ctx.setFillColor(rgb(inkBottom)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
fillInk()

// 2. Páginas (curva superior e inferior suaves). Hueco central de 56 px = palo de la cruz.
func page(left: Bool) -> CGPath {
    let p = CGMutablePath()
    func X(_ x: CGFloat) -> CGFloat { left ? x : 1024 - x }
    p.move(to: CGPoint(x: X(484), y: 318))
    p.addCurve(to: CGPoint(x: X(236), y: 300), control1: CGPoint(x: X(410), y: 282), control2: CGPoint(x: X(312), y: 278))
    p.addLine(to: CGPoint(x: X(236), y: 728))
    p.addCurve(to: CGPoint(x: X(484), y: 746), control1: CGPoint(x: X(312), y: 706), control2: CGPoint(x: X(410), y: 710))
    p.closeSubpath(); return p
}
let pages = CGMutablePath(); pages.addPath(page(left: true)); pages.addPath(page(left: false))
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: rgb(0x05090C, 0.45))
ctx.addPath(pages); ctx.setFillColor(rgb(pageRight)); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(page(left: true)); ctx.setFillColor(rgb(pageLeft)); ctx.fillPath()
ctx.addPath(page(left: false)); ctx.setFillColor(rgb(pageRight)); ctx.fillPath()
// Sombreado muy leve hacia el pliegue para dar volumen
for left in [true, false] {
    ctx.saveGState()
    ctx.addPath(page(left: left)); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: [rgb(0x8C7B5E, 0), rgb(0x8C7B5E, 0.18)] as CFArray, locations: [0, 1])!
    let edge: CGFloat = left ? 236 : 788, fold: CGFloat = left ? 484 : 540
    ctx.drawLinearGradient(g, start: CGPoint(x: edge + (fold - edge) * 0.55, y: 0), end: CGPoint(x: fold, y: 0), options: [])
    ctx.restoreGState()
}

// 3. Travesaño calado (centro a ~1/3 de la altura de la cruz): se rellena con el mismo degradado del fondo.
ctx.saveGState()
ctx.clip(to: CGRect(x: 372, y: 430, width: 280, height: 56))
fillInk()
ctx.restoreGState()

// 4. Cinta de marcapáginas con cola en V
let ribbon = CGMutablePath()
ribbon.addLines(between: [CGPoint(x: 496, y: 690), CGPoint(x: 528, y: 690), CGPoint(x: 528, y: 866),
                          CGPoint(x: 512, y: 850), CGPoint(x: 496, y: 866)])
ribbon.closeSubpath()
ctx.saveGState()
ctx.addPath(ribbon); ctx.clip()
let rg = CGGradient(colorsSpace: cs, colors: [rgb(ribbonTop), rgb(ribbonBottom)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(rg, start: CGPoint(x: 512, y: 690), end: CGPoint(x: 512, y: 866), options: [])
ctx.restoreGState()

ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/Icon/Biblia-1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
