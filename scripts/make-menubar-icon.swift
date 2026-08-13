// Делает монохромные иконки статус-бара из Resources/AppIcon.png.
//
//   swift scripts/make-menubar-icon.swift [--preview <каталог>]
//
// Логика: фон в исходнике плоский и тёмный, эмблема светлее, труба и глобус —
// белые. Берём эмблему целиком и вычитаем из неё расширенные белые элементы —
// получается залитый щит с прорезью на месте трубы. На 18 точках сплошная
// фигура читается, а тонкие контуры исходника — нет, поэтому силуэт, а не обводка.
//
// Результат — template-изображения (чёрный + альфа): цвет им подбирает macOS,
// поэтому они правильно смотрятся и в светлой, и в тёмной строке меню.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Картинки

func load(_ path: String) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        FileHandle.standardError.write("не читается: \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    return img
}

func save(_ img: CGImage, _ path: String) {
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                              UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
}

func lumaMap(_ img: CGImage) -> (luma: [Double], w: Int, h: Int) {
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    var luma = [Double](repeating: 0, count: w * h)
    for i in 0..<(w * h) {
        luma[i] = 0.2126 * Double(px[i*4]) / 255
                + 0.7152 * Double(px[i*4+1]) / 255
                + 0.0722 * Double(px[i*4+2]) / 255
    }
    return (luma, w, h)
}

// MARK: - Морфология

/// Раздельные проходы по осям: O(w*h*r) вместо O(w*h*r²).
/// dilate — расширение маски, erode — сжатие (то же самое для инверсии).
func morph(_ mask: [Bool], _ w: Int, _ h: Int, radius: Int, dilate: Bool) -> [Bool] {
    let want = dilate
    func pass(_ src: [Bool], horizontal: Bool) -> [Bool] {
        var out = src
        let outer = horizontal ? h : w, inner = horizontal ? w : h
        for a in 0..<outer {
            // окно длиной 2r+1: считаем в нём количество «нужных» пикселей
            var count = 0
            func idx(_ b: Int) -> Int { horizontal ? (b + a * w) : (a + b * w) }
            for b in 0..<min(radius, inner) where src[idx(b)] == want { count += 1 }
            for b in 0..<inner {
                let add = b + radius, drop = b - radius - 1
                if add < inner, src[idx(add)] == want { count += 1 }
                if drop >= 0, src[idx(drop)] == want { count -= 1 }
                if count > 0 { out[idx(b)] = want }
            }
        }
        return out
    }
    return pass(pass(mask, horizontal: true), horizontal: false)
}

// MARK: - Сборка глифа

/// Обрезает маску по содержимому и вписывает в квадрат стороной side.
func glyph(_ mask: [Bool], _ w: Int, _ h: Int, side: Int, pad: Double) -> CGImage {
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w where mask[x + y * w] {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX else { FileHandle.standardError.write("пустая маска\n".data(using: .utf8)!); exit(1) }

    let bw = maxX - minX + 1, bh = maxY - minY + 1
    var buf = [UInt8](repeating: 0, count: bw * bh * 4)
    for y in 0..<bh {
        for x in 0..<bw where mask[(minX + x) + (minY + y) * w] {
            buf[(x + y * bw) * 4 + 3] = 255      // чёрный, непрозрачный
        }
    }
    let cropped = CGContext(data: &buf, width: bw, height: bh, bitsPerComponent: 8, bytesPerRow: bw * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!

    let out = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    out.interpolationQuality = .high
    let avail = Double(side) * (1 - 2 * pad)
    let k = min(avail / Double(bw), avail / Double(bh))
    let dw = Double(bw) * k, dh = Double(bh) * k
    out.draw(cropped, in: CGRect(x: (Double(side) - dw) / 2, y: (Double(side) - dh) / 2, width: dw, height: dh))
    return out.makeImage()!
}

/// Предпросмотр: глиф на белом фоне, увеличенный без сглаживания.
func preview(_ img: CGImage, _ side: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    ctx.interpolationQuality = .none
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: side, height: side))
    return ctx.makeImage()!
}

// MARK: -

let args = CommandLine.arguments
let previewDir = args.firstIndex(of: "--preview").map { args[$0 + 1] }

let (luma, w, h) = lumaMap(load("Resources/AppIcon.png"))
let background = luma[0]                       // угол исходника — заведомо фон
let emblem = luma.map { $0 > background + 0.05 }
let white  = luma.map { $0 > 0.60 }

// прорезь делаем шире самой трубы, иначе она пропадёт при уменьшении до 18 точек
let widened = morph(white, w, h, radius: max(1, w / 85), dilate: true)
let solid = (0..<(w * h)).map { emblem[$0] && !widened[$0] }
// Обводка = фигура минус её сжатая копия. Радиус берём щедрый: на 18 точках
// штрих тоньше пикселя выцветает в серую кашу, нужно около двух точек.
let shrunk = morph(solid, w, h, radius: max(1, w / 20), dilate: false)
let outline = (0..<(w * h)).map { solid[$0] && !shrunk[$0] }

let pct = { (m: [Bool]) in m.filter { $0 }.count * 100 / (w * h) }
print("фон \(String(format: "%.2f", background)); эмблема \(pct(emblem))%, белое \(pct(white))%, "
      + "силуэт \(pct(solid))%, обводка \(pct(outline))%")

for (name, mask) in [("MenuIcon", solid), ("MenuIconOutline", outline)] {
    save(glyph(mask, w, h, side: 18, pad: 0.05), "Resources/\(name).png")
    save(glyph(mask, w, h, side: 36, pad: 0.05), "Resources/\(name)@2x.png")
    if let dir = previewDir {
        save(preview(glyph(mask, w, h, side: 18, pad: 0.05), 288), "\(dir)/\(name)-18.png")
    }
    print("готово: Resources/\(name).png + @2x")
}
