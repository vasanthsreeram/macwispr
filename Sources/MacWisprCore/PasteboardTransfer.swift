import AppKit

/// Writes a transcript to a pasteboard and later puts the user's previous
/// contents back (every item, every type), per `ClipboardPolicy`.
public enum PasteboardTransfer {
    public static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    public static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// Previous contents plus the change count our transcript write produced.
    public struct Session {
        let items: [[(NSPasteboard.PasteboardType, Data)]]
        public let changeCount: Int
    }

    /// Writes `text`. Returns a session to `finish` when the plan restores.
    /// Pass a still-pending session so back-to-back pastes keep the user's
    /// original clipboard rather than the previous transcript.
    @discardableResult
    public static func begin(
        text: String, plan: ClipboardWrite, on pasteboard: NSPasteboard, pending: Session? = nil
    ) -> Session? {
        var previous: [[(NSPasteboard.PasteboardType, Data)]]?
        if plan.restoreAfterPaste {
            if let pending, ClipboardPolicy.shouldRestore(
                changeCountAfterWrite: pending.changeCount, currentChangeCount: pasteboard.changeCount) {
                previous = pending.items
            } else {
                previous = capture(pasteboard)
            }
        }

        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if plan.transient { item.setData(Data(), forType: transientType) }
        if plan.concealed { item.setData(Data(), forType: concealedType) }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        guard let previous else { return nil }
        return Session(items: previous, changeCount: pasteboard.changeCount)
    }

    /// Restores the previous contents if the pasteboard still holds our write.
    @discardableResult
    public static func finish(_ session: Session, on pasteboard: NSPasteboard) -> Bool {
        guard ClipboardPolicy.shouldRestore(
            changeCountAfterWrite: session.changeCount, currentChangeCount: pasteboard.changeCount) else { return false }
        pasteboard.clearContents()
        let items = session.items.map { pairs -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in pairs { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
        return true
    }

    private static func capture(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }
}
