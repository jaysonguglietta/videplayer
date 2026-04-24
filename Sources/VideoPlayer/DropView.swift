import AppKit

protocol DropViewDelegate: AnyObject {
    func dropView(_ dropView: DropView, didReceive urls: [URL])
}

final class DropView: NSView {
    weak var dropDelegate: DropViewDelegate?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else {
            return false
        }

        dropDelegate?.dropView(self, didReceive: urls)
        return true
    }
}
