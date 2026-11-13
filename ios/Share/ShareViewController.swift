import SwiftUI
import UIKit
import UniformTypeIdentifiers
import MorphCore

/// Morph in the share sheet: the same actions as the app, in the card iOS opens over the app the share came from
/// (Photos, Files, Mail). Photos and videos it makes go straight back to the photo library, so Morph itself never
/// opens. iOS sizes that card itself; an extension can't make it smaller.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            let files = await incomingFiles()
            guard !files.isEmpty else { return close() }
            let host = UIHostingController(rootView: ActionsView(files: files) { [weak self] in self?.close() })
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }

    private func close() {
        try? FileManager.default.removeItem(at: Prefs.workFolder)
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Copies what was shared into the extension's own temporary folder; the system's copies vanish once read.
    private func incomingFiles() async -> [URL] {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let inbox = Prefs.workFolder.appendingPathComponent("inbox")
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        var files: [URL] = []
        for provider in providers {
            // The most specific type first ("public.heic" before "public.image"), so the file keeps its format.
            guard let type = provider.registeredTypeIdentifiers.first else { continue }
            let copy: URL? = await withCheckedContinuation { done in
                _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                    guard let url else { return done.resume(returning: nil) }
                    let name = url.deletingPathExtension().lastPathComponent
                    let destination = Output.unique(in: inbox, base: provider.suggestedName ?? name, ext: url.pathExtension)
                    done.resume(returning: (try? FileManager.default.copyItem(at: url, to: destination)) != nil ? destination : nil)
                }
            }
            if let copy { files.append(copy) }
        }
        return files
    }
}

/// The share sheet's settings. shortcut: the app's own settings (compression level, size limit) aren't read here,
/// since an extension has separate storage; share them through an App Group if people ask for it.
enum Prefs {
    static let haptics = true

    /// Everything the extension writes; removed when the sheet closes.
    static let workFolder = FileManager.default.temporaryDirectory.appendingPathComponent("share")

    static var options: Options {
        var options = Options()
        let results = workFolder.appendingPathComponent("results")
        try? FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
        options.outputDirectory = results
        return options
    }
}
