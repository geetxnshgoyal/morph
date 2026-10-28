import Foundation
import MorphCore

let usage = """
morph — free file converter & toolbox

  morph actions [files…]                 list actions (only those that fit the files, if given)
  morph run <action> [flags] <files…>    run an action or recipe ("recipe.Web Image")
  morph info <file>                      size, format, private metadata
  morph recipes                          list recipes
  morph recipe add <name> <a,b,c>        save a recipe from action ids
  morph recipe rm <name>
  morph watch <folder> <action>          process new files as they arrive (Ctrl-C to stop)
  morph history                          recent jobs
  morph undo                             move the last job's outputs to the Trash

flags: --quality 0.8  --max 1600  --target 500KB  --level light|balanced|strong
       --size 600x600 (exact size for resize, cropped to fill)  --caption "Name" (name and date below)
       --out <dir>    --style pixelate|solid  --colors 8 (palette when tracing to SVG)
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("morph: \(message)\n".utf8))
    exit(1)
}

/// Lets `fail` stand in for a value after `??`, which `Never` alone no longer does.
func fail<T>(_ message: String) -> T { fail(message) as Never }

func parseRun(_ args: ArraySlice<String>) -> (Options, [URL]) {
    var options = Options()
    var files: [URL] = []
    var it = args.makeIterator()
    while let arg = it.next() {
        func value() -> String { it.next() ?? fail("\(arg) needs a value") }
        switch arg {
        case "--quality", "-q": options.quality = Double(value()) ?? fail("bad --quality")
        case "--max", "-m": options.maxPixel = Int(value()) ?? fail("bad --max")
        case "--target", "-t": options.targetBytes = Options.parseSize(value()) ?? fail("bad --target")
        case "--level": options.compression = CompressionLevel(rawValue: value()) ?? fail("level is light|balanced|strong")
        case "--colors": options.colors = Int(value()) ?? fail("bad --colors")
        case "--size": options.exactSize = PixelSize(value()) ?? fail("size is like 600x600")
        case "--caption": options.caption = value()
        case "--style": options.redactStyle = RedactStyle(rawValue: value()) ?? fail("style is pixelate|solid")
        case "--out", "-o":
            let dir = URL(fileURLWithPath: (value() as NSString).expandingTildeInPath)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            options.outputDirectory = dir
        default:
            let url = URL(fileURLWithPath: (arg as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else { fail("no such file: \(arg)") }
            files.append(url.standardizedFileURL)
        }
    }
    return (options, files)
}

func display(_ url: URL) -> String {
    let cwd = FileManager.default.currentDirectoryPath + "/"
    return url.path.hasPrefix(cwd) ? String(url.path.dropFirst(cwd.count)) : url.path
}

let args = CommandLine.arguments.dropFirst()
guard let command = args.first else { print(usage); exit(0) }

switch command {
case "actions":
    let (_, files) = parseRun(args.dropFirst())
    let list = files.isEmpty ? Library.actions + RecipeStore.shared.recipes.map(\.action) : Library.actions(for: files)
    for group in [Action.Group.convert, .tool, .recipe] {
        let items = list.filter { $0.group == group }
        guard !items.isEmpty else { continue }
        print("\n\(group.rawValue.uppercased())")
        for a in items {
            let note = a.isAvailable ? "" : "  (needs ffmpeg)"
            print("  \(a.id.padding(toLength: 28, withPad: " ", startingAt: 0)) \(a.title)\(note)")
        }
    }
    if ExternalTool.ffmpeg == nil { print("\nTip: brew install ffmpeg unlocks MP3/WebM/FLAC/loudness tools.") }

case "run":
    guard let id = args.dropFirst().first else { fail("usage: morph run <action> <files…>") }
    guard let action = Library.action(id) ?? Library.action("recipe." + id) else { fail("unknown action \(id) — see `morph actions`") }
    let (options, files) = parseRun(args.dropFirst(2))
    guard !files.isEmpty else { fail("no input files") }
    guard action.accepts(files) else { fail("\(action.title) doesn't accept these files") }
    let start = Date()
    let result = await Runner.run(action, inputs: files, options: options) { done, total in
        if total > 1 { FileHandle.standardError.write(Data("\r\(done)/\(total)".utf8)) }
    }
    if files.count > 1 { FileHandle.standardError.write(Data("\n".utf8)) }
    for out in result.outputs {
        let size = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        print("✓ \(display(out))\(size.map { "  (\($0))" } ?? "")")
    }
    if action.reportsSize, let sizes = result.sizeSummary, let change = result.sizeChange { print("  \(sizes)  (\(change))") }
    for note in result.notes { print("– \(note)") }
    for f in result.failures { FileHandle.standardError.write(Data("✗ \(f)\n".utf8)) }
    FileHandle.standardError.write(Data(String(format: "%.1fs\n", Date().timeIntervalSince(start)).utf8))
    exit(result.failures.isEmpty ? 0 : 1)

case "info":
    let (_, files) = parseRun(args.dropFirst())
    for url in files {
        print(display(url))
        var info: [String: String] = ["Kind": FileKind(url: url).rawValue]
        do {
            switch FileKind(url: url) {
            case .image: info.merge(try ImageOps.summary(url)) { $1 }
            case .video, .audio: info.merge(try await MediaOps.summary(url)) { $1 }
            default: break
            }
        } catch { info["Error"] = error.localizedDescription }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            info["Bytes"] = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }
        for (k, v) in info.sorted(by: { $0.key < $1.key }) { print("  \(k): \(v)") }
    }

case "recipes":
    for r in RecipeStore.shared.recipes { print("\(r.name): " + r.steps.map(\.action).joined(separator: " → ")) }

case "recipe":
    let rest = Array(args.dropFirst())
    switch rest.first {
    case "add" where rest.count == 3:
        let steps = rest[2].split(separator: ",").map { Recipe.Step(String($0).trimmingCharacters(in: .whitespaces)) }
        for s in steps where Library.action(s.action) == nil { fail("unknown action \(s.action)") }
        try RecipeStore.shared.save(Recipe(name: rest[1], steps: steps))
        print("Saved recipe \"\(rest[1])\" — run it with: morph run \"recipe.\(rest[1])\" <files>")
    case "rm" where rest.count == 2:
        try RecipeStore.shared.delete(rest[1])
    default: fail("usage: morph recipe add <name> <a,b,c> | morph recipe rm <name>")
    }

case "watch":
    let rest = Array(args.dropFirst())
    guard rest.count == 2 else { fail("usage: morph watch <folder> <action>") }
    let folder = URL(fileURLWithPath: (rest[0] as NSString).expandingTildeInPath)
    guard Library.action(rest[1]) ?? Library.action("recipe." + rest[1]) != nil else { fail("unknown action \(rest[1])") }
    let actionID = Library.action(rest[1]) != nil ? rest[1] : "recipe." + rest[1]
    let watcher = WatchFolder(.init(folder: folder, actionID: actionID))
    watcher.onResult = { url, result in
        for out in result.outputs { print("✓ \(url.lastPathComponent) → \(display(out))") }
        for f in result.failures { print("✗ \(f)") }
    }
    try watcher.start()
    print("Watching \(folder.path) — outputs go to Morphed/. Ctrl-C to stop.")
    while true { try await Task.sleep(for: .seconds(3600)) }

case "history":
    let f = DateFormatter()
    f.dateStyle = .short; f.timeStyle = .short
    for e in History.shared.entries.suffix(20) {
        print("\(f.string(from: e.date))  \(e.title)  \(e.inputs.count) in → \(e.outputs.count) out\(e.undone ? "  (undone)" : "")\(e.failures.isEmpty ? "" : "  \(e.failures.count) failed")")
    }

case "undo":
    if let e = try History.shared.undo() { print("Moved \(e.outputs.count) output(s) of \"\(e.title)\" to the Trash") }
    else { print("Nothing to undo") }

case "-h", "--help", "help":
    print(usage)

default:
    fail("unknown command \(command)\n\n\(usage)")
}
