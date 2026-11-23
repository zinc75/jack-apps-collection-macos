// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import JConvolverKit

extension AppModel {
    /// Whether there is something to put together: at least one response is read from a file.
    var canExportPortable: Bool {
        guard let document, isOpen else { return false }
        return document.content.impulses.values.contains { list in list.contains { if case .file = $0.source { true } else { false } } }
    }

    /// The name that a portable version takes first: the name of the configuration file, with `-portable`.
    var portableDefaultName: String {
        let base = (fileURL?.deletingPathExtension().lastPathComponent).flatMap { $0.isEmpty ? nil : $0 } ?? defaultFileName.replacingOccurrences(of: ".conf", with: "")
        return base + "-portable"
    }

    /// What a portable version of the configuration would be, with these choices.
    func portablePlan(_ options: PortableOptions) -> PortablePlan? {
        guard let document else { return nil }
        let catalog = catalog
        return PortablePlan.make(document: document, options: options, configDirectory: configDirectory, automatic: automaticHeader, fileInfo: { catalog.info(at: $0) })
    }

    /// Writes the portable version in `folder`. The configuration that is open is not changed.
    func exportPortable(_ options: PortableOptions, to folder: URL) async throws -> PortableResult {
        guard let document, let plan = portablePlan(options) else { throw PortableError.blocked }
        let catalog = catalog, directory = configDirectory, header = automaticHeader
        return try await Task.detached(priority: .userInitiated) {
            try PortableExporter.export(document: document, plan: plan, options: options, configDirectory: directory, automatic: header,
                                        fileInfo: { catalog.info(at: $0) }, to: folder)
        }.value
    }
}
