import Foundation
#if canImport(CoreGraphics)
@preconcurrency import CoreGraphics
#endif
#if canImport(ImageIO)
import ImageIO
#endif

/// PDF page renderer. Pages are rasterized to PNG at a configurable scale.
public struct PDFReader: DocumentReader {
    private let scale: CGFloat

    #if canImport(CoreGraphics)
    private let document: CGPDFDocument
    #endif

    public init(url: URL, scale: CGFloat = 2.0) throws {
        self.scale = scale
        #if canImport(CoreGraphics)
        guard let doc = CGPDFDocument(url as CFURL) else { throw ZipError.notAZip }
        self.document = doc
        #else
        throw ZipError.unsupportedCompression(0)
        #endif
    }

    public static func canOpen(url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    public func pageCount() throws -> Int {
        #if canImport(CoreGraphics)
        return document.numberOfPages
        #else
        return 0
        #endif
    }

    public func pageData(at index: Int) throws -> Data {
        #if canImport(CoreGraphics)
        // CoreGraphics pages are 1-based.
        guard let page = document.page(at: index + 1) else { throw ZipError.corruptEntry }
        let box = page.getBoxRect(.mediaBox)
        let width = max(1, Int(box.width * scale))
        let height = max(1, Int(box.height * scale))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw ZipError.corruptEntry }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)

        guard let image = context.makeImage() else { throw ZipError.corruptEntry }
        #if canImport(ImageIO)
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else {
            throw ZipError.corruptEntry
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ZipError.corruptEntry }
        return out as Data
        #else
        throw ZipError.unsupportedCompression(0)
        #endif
        #else
        throw ZipError.unsupportedCompression(0)
        #endif
    }
}
