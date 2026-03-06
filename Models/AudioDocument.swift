import SwiftUI
import UniformTypeIdentifiers

struct AudioDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.audio] }

    var url: URL?

    init(url: URL?) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        url = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        return try FileWrapper(url: url)
    }
}
