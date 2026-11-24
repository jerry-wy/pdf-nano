import AppKit

enum NanoIcons {
    static func symbol(_ name: String, label: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
    }

    static func title(in bundle: Bundle = .main) -> NSImage? {
        bitmap(named: "TitleIcon", points: 16, in: bundle)
    }

    static func application(in bundle: Bundle = .main) -> NSImage? {
        bitmap(named: "ApplicationIcon", points: 512, in: bundle)
    }

    static func tabTitle(_ title: String, in bundle: Bundle = .main) -> NSAttributedString {
        guard let image = self.title(in: bundle) else { return NSAttributedString(string: title) }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -3, width: 16, height: 16)
        let text = NSMutableAttributedString(attachment: attachment)
        text.append(NSAttributedString(string: "  " + title))
        return text
    }

    private static func bitmap(named name: String, points: CGFloat, in bundle: Bundle) -> NSImage? {
        guard let url = bundle.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let representation = NSBitmapImageRep(data: data) else { return nil }
        // Construct an image with one decoded bitmap. AppKit must not choose a
        // cached Icon Services / ICNS representation for the document button.
        let size = NSSize(width: points, height: points)
        representation.size = size
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        image.isTemplate = false
        return image
    }
}
