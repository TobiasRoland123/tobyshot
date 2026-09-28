import AppKit

/// The canvas editor and exported text use the same unwrapped TextKit layout.
final class AnnotationTextLayout {
    let storage: NSTextStorage
    let manager = NSLayoutManager()
    let container = NSTextContainer(containerSize: CGSize(width: 1_000_000, height: 1_000_000))

    static func fontSize(for annotation: EditorAnnotation) -> CGFloat {
        annotation.textSize ?? max(20, annotation.width * 5)
    }

    static func attributes(for annotation: EditorAnnotation) -> [NSAttributedString.Key: Any] {
        [.font: annotation.font.font(ofSize: fontSize(for: annotation)),
         .foregroundColor: annotation.color]
    }

    init(_ annotation: EditorAnnotation) {
        storage = NSTextStorage(string: annotation.text, attributes: Self.attributes(for: annotation))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
    }

    var bounds: CGRect {
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(for: container)
        var bounds = manager.usedRect(for: container)
        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, range, _ in
            var visible = range
            // A newline's selection bounds extend to the unwrapped container's edge.
            while visible.length > 0, self.manager.propertyForGlyph(at: NSMaxRange(visible) - 1).contains(.controlCharacter) {
                visible.length -= 1
            }
            if visible.length > 0 {
                bounds = bounds.union(self.manager.boundingRect(forGlyphRange: visible, in: self.container))
            }
        }
        return bounds
    }

    var selectionSize: CGSize {
        let rect = bounds.union(manager.extraLineFragmentUsedRect)
        return CGSize(width: max(1, ceil(rect.maxX)), height: max(1, ceil(rect.maxY)))
    }

    var editingSize: CGSize {
        let size = selectionSize
        return CGSize(width: max(40, size.width + 4), height: max(24, size.height))
    }

    func draw(at point: CGPoint, in context: CGContext) {
        manager.ensureLayout(for: container)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        manager.drawGlyphs(forGlyphRange: manager.glyphRange(for: container), at: point)
        NSGraphicsContext.restoreGraphicsState()
    }
}
