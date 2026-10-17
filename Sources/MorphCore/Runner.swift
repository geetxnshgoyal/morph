import Foundation

public struct RunResult: Sendable {
    public var outputs: [URL] = []
    public var failures: [String] = []
    /// Files left alone on purpose, with why (say, already as small as they can get).
    public var notes: [String] = []
    /// Combined size of the inputs that produced something, and of what they produced.
    public var inputBytes: Int64 = 0
    public var outputBytes: Int64 = 0

    /// "171 KB → 139 KB", when there's a before and after to compare.
    public var sizeSummary: String? {
        guard inputBytes > 0, outputBytes > 0 else { return nil }
        return "\(Self.format(inputBytes)) → \(Self.format(outputBytes))"
    }

    /// "19% smaller", "12% larger" or "Same size".
    public var sizeChange: String? {
        guard inputBytes > 0, outputBytes > 0 else { return nil }
        let percent = Int((Double(inputBytes - outputBytes) / Double(inputBytes) * 100).rounded())
        return percent > 0 ? "\(percent)% smaller" : percent < 0 ? "\(-percent)% larger" : "Same size"
    }

    static func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

public enum Runner {
    /// Runs an action over every input, per-file actions in parallel, and records the job in history.
    public static func run(_ action: Action, inputs: [URL], options: Options = Options(), record: Bool = true,
                           progress: (@Sendable (Int, Int) -> Void)? = nil) async -> RunResult {
        var result = RunResult()
        if action.combinesInputs {
            do {
                result.outputs = try await action.run(inputs, options)
                if !result.outputs.isEmpty {
                    result.inputBytes = inputs.reduce(0) { $0 + size(of: $1) }
                    result.outputBytes = result.outputs.reduce(0) { $0 + size(of: $1) }
                }
            } catch let note as MorphNote {
                result.notes.append(note.message)
            } catch {
                result.failures.append(error.localizedDescription)
            }
            progress?(1, 1)
        } else {
            let limit = max(ProcessInfo.processInfo.activeProcessorCount / 2, 2)
            var done = 0
            await withTaskGroup(of: (Int, Outcome).self) { group in
                var next = 0
                func add() {
                    let index = next, url = inputs[index]
                    next += 1
                    group.addTask {
                        do { return (index, .made(try await action.run([url], options))) }
                        catch let note as MorphNote { return (index, .skipped(note.message)) }
                        catch { return (index, .failed("\(url.lastPathComponent): \(error.localizedDescription)")) }
                    }
                }
                while next < min(limit, inputs.count) { add() }
                var ordered: [Int: [URL]] = [:]
                for await (index, outcome) in group {
                    switch outcome {
                    case .made(let urls):
                        ordered[index] = urls
                        if !urls.isEmpty {
                            result.inputBytes += size(of: inputs[index])
                            result.outputBytes += urls.reduce(0) { $0 + size(of: $1) }
                        }
                    case .skipped(let message): result.notes.append(message)
                    case .failed(let message): result.failures.append(message)
                    }
                    done += 1
                    progress?(done, inputs.count)
                    if next < inputs.count { add() }
                }
                result.outputs = ordered.keys.sorted().flatMap { ordered[$0]! }
            }
        }
        if record, !result.outputs.isEmpty || !result.failures.isEmpty {
            History.shared.append(HistoryEntry(title: action.title, inputs: inputs, outputs: result.outputs, failures: result.failures))
        }
        return result
    }

    private enum Outcome: Sendable {
        case made([URL]), skipped(String), failed(String)
    }

    static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}

// MARK: - Recipes

/// A saved chain of actions, e.g. "Remove Metadata → Resize → WebP", that shows up as one petal.
public struct Recipe: Codable, Sendable, Identifiable, Hashable {
    public struct Step: Codable, Sendable, Hashable {
        public var action: String
        public var maxPixel: Int?
        public var quality: Double?
        public var targetBytes: Int?
        public init(_ action: String, maxPixel: Int? = nil, quality: Double? = nil, targetBytes: Int? = nil) {
            self.action = action; self.maxPixel = maxPixel; self.quality = quality; self.targetBytes = targetBytes
        }
    }

    public var name: String
    public var symbol: String
    public var steps: [Step]
    public var id: String { name }

    public init(name: String, symbol: String = "wand.and.stars", steps: [Step]) {
        self.name = name; self.symbol = symbol; self.steps = steps
    }

    public var action: Action {
        let recipe = self
        let first = steps.first.flatMap { Library.action($0.action) }
        return Action(id: "recipe.\(name)", title: name, symbol: symbol, group: .recipe, kinds: first?.kinds ?? [],
                      combinesInputs: first?.combinesInputs ?? false, minimumInputs: first?.minimumInputs ?? 1,
                      targetExtension: nil, needsFFmpeg: steps.contains { Library.action($0.action)?.needsFFmpeg ?? true }) { urls, options in
            try await recipe.run(urls, options: options)
        }
    }

    /// Intermediate files live in a temp folder; only the last step writes next to the originals.
    func run(_ inputs: [URL], options: Options) async throws -> [URL] {
        let scratch = try Output.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        var current = inputs
        for (i, step) in steps.enumerated() {
            guard let action = Library.action(step.action), !step.action.hasPrefix("recipe.") else {
                throw MorphError("Recipe \"\(name)\" uses unknown step \(step.action)")
            }
            var o = options
            if let v = step.maxPixel { o.maxPixel = v }
            if let v = step.quality { o.quality = v }
            if let v = step.targetBytes { o.targetBytes = v }
            let isLast = i == steps.count - 1
            if !isLast { o.outputDirectory = scratch }
            else if o.outputDirectory == nil { o.outputDirectory = inputs.first?.deletingLastPathComponent() }
            let result = await Runner.run(action, inputs: current, options: o, record: false)
            if let failure = result.failures.first { throw MorphError("\(action.title): \(failure)") }
            current = result.outputs
        }
        return current
    }
}

public final class RecipeStore: @unchecked Sendable {
    public static let shared = RecipeStore()
    private let lock = NSLock()
    private var userRecipes: [Recipe]
    private var file: URL { Paths.support.appendingPathComponent("recipes.json") }

    public static let builtIn: [Recipe] = [
        Recipe(name: "Share-Safe Photo", symbol: "lock.shield", steps: [.init("tool.strip-metadata"), .init("tool.resize", maxPixel: 2048)]),
        Recipe(name: "Web Image", symbol: "globe", steps: [.init("tool.resize", maxPixel: 1600), .init(ImageFormat.webp.isAvailable ? "convert.webp" : "convert.jpg", quality: 0.8)]),
        Recipe(name: "Under 1 MB", symbol: "envelope", steps: [.init("tool.compress", targetBytes: 1_000_000)]),
    ]

    init() {
        userRecipes = []
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Recipe].self, from: data) {
            userRecipes = saved
        }
    }

    public var recipes: [Recipe] {
        lock.lock(); defer { lock.unlock() }
        return Self.builtIn.filter { b in !userRecipes.contains { $0.name == b.name } } + userRecipes
    }

    public func recipe(named name: String) -> Recipe? { recipes.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }

    public func save(_ recipe: Recipe) throws {
        lock.lock()
        userRecipes.removeAll { $0.name == recipe.name }
        userRecipes.append(recipe)
        let snapshot = userRecipes
        lock.unlock()
        try JSONEncoder().encode(snapshot).write(to: file)
    }

    public func delete(_ name: String) throws {
        lock.lock()
        userRecipes.removeAll { $0.name == name }
        let snapshot = userRecipes
        lock.unlock()
        try JSONEncoder().encode(snapshot).write(to: file)
    }
}

// MARK: - History

public struct HistoryEntry: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var date = Date()
    public var title: String
    public var inputs: [URL]
    public var outputs: [URL]
    public var failures: [String]
    public var undone = false
}

/// Every job is logged; undo moves its outputs to the Trash (originals are never touched).
public final class History: @unchecked Sendable {
    public static let shared = History()
    private let lock = NSLock()
    private var file: URL { Paths.support.appendingPathComponent("history.json") }

    public var entries: [HistoryEntry] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    private func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func store(_ entries: [HistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(Array(entries.suffix(200))).write(to: file, options: .atomic)
    }

    func append(_ entry: HistoryEntry) {
        lock.lock(); defer { lock.unlock() }
        store(load() + [entry])
    }

    /// Trashes the outputs of `id` (or of the most recent job that isn't undone yet).
    @discardableResult
    public func undo(_ id: UUID? = nil) throws -> HistoryEntry? {
        lock.lock(); defer { lock.unlock() }
        var all = load()
        let index = id == nil ? all.lastIndex { !$0.undone } : all.firstIndex { $0.id == id }
        guard let i = index, !all[i].undone else { return nil }
        for url in all[i].outputs where FileManager.default.fileExists(atPath: url.path) {
            #if os(macOS)
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            #else
            try FileManager.default.removeItem(at: url)
            #endif
        }
        all[i].undone = true
        store(all)
        return all[i]
    }
}
