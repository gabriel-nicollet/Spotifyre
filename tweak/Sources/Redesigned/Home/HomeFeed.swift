// Home redesign: every section's shelf heading from the model behind Home's list, for the sections whose cells
// are not built yet. Spotify builds a section's views only as it nears the screen, so a heading a shelf further
// down has is not there to read (HomeShelves.m); the list's content snapshot holds every section's props.
//
// The path, from the page's controller (Home_EvoPageImpl.EvoLoadableResourceViewController, the list's
// delegate), by the stored properties' names (in the 9.1.78, 9.1.88 and 9.1.90 binaries' reflection strings):
//   collectionViewRenderer: Element_List.CollectionViewRenderer
//   .contentDataSource: Element_List.ContentDataSource (not the list's own dataSource, which is UIKit's diffable one)
//   .contentSnapshot: .sections, one per section of the list, each with .items (ItemIdentifier),
//                     and .items, ItemIdentifier -> Section.Item
//   Section.Item .item.configuration.props: Home_EvoPageImpl.HomeStructure, one case per kind (shelf: ShelfData,
//                                       recents: RecentsData, ...), its payload's .heading: HomeHeading?
//   HomeHeading                         .withText(text:...) or .enrichedHeading(text:..., enrichedTextRange:),
//                                       the range being the large part ("Chief Keef" in "More like Chief Keef")
// On 9.1.90: section 11 is .shelf, heading .withText("Your favorite artists"); section 12 .enrichedHeading("More
// like Alexis Weissenberg"), which SGRHomeShelfIdentity reads off the view as "More like …".
//
// The two objects on the way (the renderer, the data source) are read by ivar: Mirror on a class loads every
// stored property up to the one asked for, and a dangling unowned one among them traps. The data source's own
// stored properties (two subscriptions, the content, the previous snapshot) are read that way once more for the
// snapshot, a struct no ivar read gives. Mirror reads what is there and nothing else, so a version that names
// these otherwise gives nil and Top picks goes by the headings on screen as before. Main thread only.
import UIKit

@objc(SGRHomeFeed)
final class SGRHomeFeed: NSObject {
    private static func ivar(_ object: AnyObject, _ name: String) -> AnyObject? {
        guard let ivar = class_getInstanceVariable(type(of: object), name) else { return nil }
        return object_getIvar(object, ivar) as AnyObject?
    }

    private static func child(_ value: Any, _ label: String) -> Any? {
        var mirror: Mirror? = Mirror(reflecting: value)
        while let current = mirror {
            if let found = current.children.first(where: { $0.label == label }) { return found.value }
            mirror = current.superclassMirror
        }
        return nil
    }

    private static func some(_ value: Any?) -> Any? {
        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }

    // The heading's small line and its title, the way the view shows them: the large part is the title, the rest
    // the line over it ("More like" over "Chief Keef"); with no large part the whole text is the title. A range
    // past the text's end is not this text's, and the whole text is the title.
    static func parts(text: String, large: Range<String.Index>?) -> [String] {
        guard let large, large.upperBound <= text.endIndex else { return ["", text.trimmingCharacters(in: .whitespaces)] }
        let small = (text[..<large.lowerBound] + text[large.upperBound...]).trimmingCharacters(in: .whitespaces)
        return [small, text[large].trimmingCharacters(in: .whitespaces)]
    }

    private static func parts(props: Any) -> [String]? {
        guard let payload = Mirror(reflecting: props).children.first?.value,
              let heading = some(child(payload, "heading")),
              let fields = Mirror(reflecting: heading).children.first?.value,
              let text = child(fields, "text") as? String else { return nil }
        return parts(text: text, large: some(child(fields, "enrichedTextRange")) as? Range<String.Index>)
    }

    // One entry per section of the list: [small line, title] of its heading, or NSNull where it has none. nil when
    // the model is not where it was found. About 0.6 ms on 9.1.90 (30 sections).
    @objc(headingsOf:) static func headings(of page: AnyObject?) -> NSArray? {
        guard let page, let renderer = ivar(page, "collectionViewRenderer"), let source = ivar(renderer, "contentDataSource"),
              let snapshot = child(source, "contentSnapshot"),
              let sections = child(snapshot, "sections"),
              let items = child(snapshot, "items") else { return nil }
        var byItem: [AnyHashable: Any] = [:]
        for pair in Mirror(reflecting: items).children {
            let both = Mirror(reflecting: pair.value).children.map(\.value)
            if both.count == 2, let item = both[0] as? AnyHashable { byItem[item] = both[1] }
        }
        let headings = Mirror(reflecting: sections).children.map { section -> Any in
            guard let first = child(section.value, "items").flatMap({ Mirror(reflecting: $0).children.first?.value as? AnyHashable }),
                  let entry = byItem[first], let item = child(entry, "item"),
                  let configuration = child(item, "configuration"), let props = child(configuration, "props") else { return NSNull() }
            return parts(props: props) ?? NSNull()
        }
        return headings as NSArray
    }
}
