import AppKit
import CoreGraphics
import Foundation

// Original CLIP mark: luminous capture brackets around a playback symbol.
let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Assets/CLIPLogo.png")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let size = 1024
guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let graphics = NSGraphicsContext(bitmapImageRep: image) else { fatalError("bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let c = graphics.cgContext
let space = CGColorSpaceCreateDeviceRGB()
func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat,_ a:CGFloat=1)->CGColor {
    CGColor(colorSpace:space,components:[r,g,b,a])!
}
func grad(_ values:[CGColor])->CGGradient {
    CGGradient(colorsSpace:space,colors:values as CFArray, locations:nil)!
}
let rect=CGRect(x:91,y:91,width:842,height:842)
let shape=CGPath(roundedRect:rect,cornerWidth:203,cornerHeight:203,transform:nil)
c.saveGState()
c.setShadow(offset:CGSize(width:0,height:-20),blur:55,color:color(0.07,0.13,0.40,0.53))
c.addPath(shape);c.setFillColor(color(0.07,0.12,0.31));c.fillPath()
c.restoreGState()
c.saveGState()
c.addPath(shape);c.clip()
c.drawLinearGradient(grad([color(0.10,0.36,0.70),color(0.19,0.13,0.46),
    color(0.065,0.085,0.23)]), start:CGPoint(x:120,y:920),
    end:CGPoint(x:940,y:90), options:[])
c.drawRadialGradient(grad([color(0.57,0.83,1,0.54),color(0.57,0.83,1,0)]),
    startCenter:CGPoint(x:206,y:866),startRadius:10,
    endCenter:CGPoint(x:206,y:866),endRadius:590,options:[])
c.drawRadialGradient(grad([color(0.72,0.43,1,0.38),color(0.72,0.43,1,0)]),
    startCenter:CGPoint(x:846,y:867),startRadius:10,
    endCenter:CGPoint(x:846,y:867),endRadius:570,options:[])
c.drawRadialGradient(grad([color(0.33,0.51,0.98,0.30),color(0.33,0.51,0.98,0)]),
    startCenter:CGPoint(x:792,y:160),startRadius:0,
    endCenter:CGPoint(x:792,y:160),endRadius:485,options:[])
c.restoreGState()
c.addPath(shape);c.setStrokeColor(color(0.48,0.66,1,0.80));c.setLineWidth(15);c.strokePath()
c.addPath(CGPath(roundedRect:rect.insetBy(dx:16,dy:16),cornerWidth:187,cornerHeight:187,transform:nil))
c.setStrokeColor(color(0.9,0.95,1,0.23));c.setLineWidth(5);c.strokePath()

func bracket(_ points:[CGPoint],_ ink:CGColor){
    let p=CGMutablePath();p.addLines(between:points)
    c.saveGState();c.addPath(p)
    c.setLineWidth(35);c.setLineJoin(.round);c.setLineCap(.round)
    c.setShadow(offset:.zero,blur:25,color:ink);c.setStrokeColor(ink);c.strokePath()
    c.restoreGState()
    c.addPath(p);c.setLineWidth(29);c.setLineCap(.round);c.setLineJoin(.round)
    c.setStrokeColor(ink);c.strokePath()
}
bracket([CGPoint(x:282,y:710),CGPoint(x:282,y:772),CGPoint(x:349,y:772)],color(0.88,0.97,1))
bracket([CGPoint(x:676,y:772),CGPoint(x:745,y:772),CGPoint(x:745,y:712)],color(0.79,0.60,1))
bracket([CGPoint(x:282,y:313),CGPoint(x:282,y:251),CGPoint(x:351,y:251)],color(0.92,0.96,1))
bracket([CGPoint(x:677,y:251),CGPoint(x:745,y:251),CGPoint(x:745,y:313)],color(0.55,0.72,1))
let play=CGMutablePath()
play.move(to:CGPoint(x:436,y:387))
play.addQuadCurve(to:CGPoint(x:476,y:374),control:CGPoint(x:442,y:358))
play.addLine(to:CGPoint(x:661,y:490))
play.addQuadCurve(to:CGPoint(x:661,y:530),control:CGPoint(x:687,y:510))
play.addLine(to:CGPoint(x:476,y:647))
play.addQuadCurve(to:CGPoint(x:436,y:628),control:CGPoint(x:443,y:665))
play.closeSubpath()
c.saveGState();c.setShadow(offset:CGSize(width:0,height:-5),blur:42,color:color(0.55,0.70,1,0.70))
c.addPath(play);c.setFillColor(color(0.95,0.97,1));c.fillPath();c.restoreGState()
NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let data=image.representation(using:.png,properties:[:]) else {fatalError("png")}
try data.write(to:output)
print("Generated \(output.path) (\(data.count) bytes)")
