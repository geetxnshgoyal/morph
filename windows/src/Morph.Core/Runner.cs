using System.Text.Json;
using System.Text.Json.Serialization;

namespace Morph;

public sealed class RunResult
{
    public List<string> Outputs { get; } = [];
    public List<string> Failures { get; } = [];
    /// Files left alone on purpose, with why (say, already as small as they can get).
    public List<string> Notes { get; } = [];
    /// Combined size of the inputs that produced something, and of what they produced.
    public long InputBytes { get; set; }
    public long OutputBytes { get; set; }

    /// "171 KB → 139 KB", when there's a before and after to compare.
    public string? SizeSummary => InputBytes > 0 && OutputBytes > 0 ? $"{Bytes.Format(InputBytes)} → {Bytes.Format(OutputBytes)}" : null;

    /// "19% smaller", "12% larger" or "Same size".
    public string? SizeChange
    {
        get
        {
            if (InputBytes <= 0 || OutputBytes <= 0) return null;
            var percent = (int)Math.Round((double)(InputBytes - OutputBytes) / InputBytes * 100, MidpointRounding.AwayFromZero);
            return percent > 0 ? $"{percent}% smaller" : percent < 0 ? $"{-percent}% larger" : "Same size";
        }
    }

    /// Nothing made and nothing failed: every file was already as small as it can usefully get.
    public bool Unchanged => Outputs.Count == 0 && Failures.Count == 0 && Notes.Count > 0;
}

public static class Runner
{
    /// Runs an action over every input, per-file actions in parallel, and records the job in history.
    public static async Task<RunResult> Run(MorphAction action, IReadOnlyList<string> inputs, Options? options = null,
                                            bool record = true, Action<int, int>? progress = null, CancellationToken cancel = default)
    {
        options ??= new Options();
        var result = new RunResult();
        if (action.CombinesInputs)
        {
            try
            {
                result.Outputs.AddRange(await action.Run(inputs, options, cancel));
                if (result.Outputs.Count > 0)
                {
                    result.InputBytes = inputs.Sum(Bytes.Of);
                    result.OutputBytes = result.Outputs.Sum(Bytes.Of);
                }
            }
            catch (MorphNote note) { result.Notes.Add(note.Message); }
            catch (Exception e) when (e is not OperationCanceledException) { result.Failures.Add(Describe(e)); }
            progress?.Invoke(1, 1);
        }
        else
        {
            var ordered = new IReadOnlyList<string>?[inputs.Count];
            var failures = new string?[inputs.Count];
            var notes = new string?[inputs.Count];
            var done = 0;
            using var limit = new SemaphoreSlim(Math.Max(Environment.ProcessorCount / 2, 2));
            await Task.WhenAll(inputs.Select(async (input, index) =>
            {
                await limit.WaitAsync(cancel);
                try { ordered[index] = await action.Run([input], options, cancel); }
                catch (MorphNote note) { notes[index] = note.Message; }
                catch (Exception e) when (e is not OperationCanceledException) { failures[index] = $"{Path.GetFileName(input)}: {Describe(e)}"; }
                finally
                {
                    limit.Release();
                    progress?.Invoke(Interlocked.Increment(ref done), inputs.Count);
                }
            }));
            for (var i = 0; i < inputs.Count; i++)
            {
                if (ordered[i] is not { Count: > 0 } made) continue;
                result.Outputs.AddRange(made);
                result.InputBytes += Bytes.Of(inputs[i]);
                result.OutputBytes += made.Sum(Bytes.Of);
            }
            result.Failures.AddRange(failures.Where(f => f is not null)!);
            result.Notes.AddRange(notes.Where(n => n is not null)!);
        }
        if (record && (result.Outputs.Count > 0 || result.Failures.Count > 0))
            History.Shared.Append(new HistoryEntry { Title = action.Title, Inputs = [.. inputs], Outputs = [.. result.Outputs], Failures = [.. result.Failures] });
        return result;
    }

    static string Describe(Exception e) => e is MorphException ? e.Message : e.GetBaseException().Message;
}

// MARK: - Recipes

/// A saved chain of actions, e.g. "Remove Metadata → Resize → WebP", that shows up as one petal.
public sealed record Recipe
{
    public sealed record Step(string Action, int? MaxPixel = null, double? Quality = null, long? TargetBytes = null);

    public required string Name { get; init; }
    public string Symbol { get; init; } = "wand.and.stars";
    public required IReadOnlyList<Step> Steps { get; init; }

    [JsonIgnore]
    public MorphAction Action
    {
        get
        {
            var first = Steps.Count > 0 ? Library.Action(Steps[0].Action) : null;
            return new MorphAction
            {
                Id = $"recipe.{Name}", Title = Name, Symbol = Symbol, Group = ActionGroup.Recipe,
                Kinds = first?.Kinds ?? new HashSet<FileKind>(), CombinesInputs = first?.CombinesInputs ?? false,
                MinimumInputs = first?.MinimumInputs ?? 1, KindRequires = first?.KindRequires,
                Requires = Steps.Select(s => Library.Action(s.Action)?.Requires ?? Requirement.FFmpeg).Max(),
                Run = (inputs, options, cancel) => Execute(inputs, options, cancel),
            };
        }
    }

    /// Intermediate files live in a temp folder; only the last step writes next to the originals.
    async Task<IReadOnlyList<string>> Execute(IReadOnlyList<string> inputs, Options options, CancellationToken cancel)
    {
        var scratch = Output.TemporaryDirectory();
        try
        {
            IReadOnlyList<string> current = inputs;
            for (var i = 0; i < Steps.Count; i++)
            {
                var step = Steps[i];
                if (step.Action.StartsWith("recipe.") || Library.Action(step.Action) is not { } action)
                    throw new MorphException($"Recipe \"{Name}\" uses unknown step {step.Action}");
                var isLast = i == Steps.Count - 1;
                var o = options with
                {
                    MaxPixel = step.MaxPixel ?? options.MaxPixel,
                    Quality = step.Quality ?? options.Quality,
                    TargetBytes = step.TargetBytes ?? options.TargetBytes,
                    OutputDirectory = !isLast ? scratch : options.OutputDirectory ?? Output.FolderOf(inputs[0]),
                };
                var result = await Runner.Run(action, current, o, record: false, cancel: cancel);
                if (result.Failures.Count > 0) throw new MorphException($"{action.Title}: {result.Failures[0]}");
                current = result.Outputs;
            }
            return current;
        }
        finally
        {
            try { Directory.Delete(scratch, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}

public sealed class RecipeStore
{
    public static readonly RecipeStore Shared = new();
    readonly Lock gate = new();
    List<Recipe> userRecipes = [];

    static string FilePath => Path.Combine(Paths.Support, "recipes.json");

    public static IReadOnlyList<Recipe> BuiltIn =>
    [
        new() { Name = "Share-Safe Photo", Symbol = "lock.shield", Steps = [new("tool.strip-metadata"), new("tool.resize", MaxPixel: 2048)] },
        new() { Name = "Web Image", Symbol = "globe", Steps = [new("tool.resize", MaxPixel: 1600), new(ImageFormat.Webp.IsAvailable() ? "convert.webp" : "convert.jpg", Quality: 0.8)] },
        new() { Name = "Under 1 MB", Symbol = "envelope", Steps = [new("tool.compress", TargetBytes: 1_000_000)] },
    ];

    RecipeStore() => Reload();

    public void Reload()
    {
        try
        {
            if (File.Exists(FilePath))
                userRecipes = JsonSerializer.Deserialize<List<Recipe>>(File.ReadAllText(FilePath), Json.Options) ?? [];
        }
        catch (JsonException) { userRecipes = []; }
    }

    public IReadOnlyList<Recipe> Recipes
    {
        get
        {
            lock (gate) return [.. BuiltIn.Where(b => !userRecipes.Any(u => u.Name == b.Name)), .. userRecipes];
        }
    }

    public Recipe? Recipe(string name) => Recipes.FirstOrDefault(r => string.Equals(r.Name, name, StringComparison.OrdinalIgnoreCase));

    public void Save(Recipe recipe)
    {
        lock (gate)
        {
            userRecipes.RemoveAll(r => r.Name == recipe.Name);
            userRecipes.Add(recipe);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(userRecipes, Json.Options));
        }
    }

    public void Delete(string name)
    {
        lock (gate)
        {
            userRecipes.RemoveAll(r => r.Name == name);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(userRecipes, Json.Options));
        }
    }
}

// MARK: - History

public sealed record HistoryEntry
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public DateTimeOffset Date { get; init; } = DateTimeOffset.Now;
    public required string Title { get; init; }
    public required List<string> Inputs { get; init; }
    public required List<string> Outputs { get; init; }
    public List<string> Failures { get; init; } = [];
    public bool Undone { get; set; }
}

/// Every job is logged; undo moves its outputs to the Recycle Bin (originals are never touched).
public sealed class History
{
    public static readonly History Shared = new();
    readonly Lock gate = new();

    public event Action? Changed;

    static string FilePath => Path.Combine(Paths.Support, "history.json");

    public IReadOnlyList<HistoryEntry> Entries
    {
        get { lock (gate) return Load(); }
    }

    static List<HistoryEntry> Load()
    {
        try { return File.Exists(FilePath) ? JsonSerializer.Deserialize<List<HistoryEntry>>(File.ReadAllText(FilePath), Json.Options) ?? [] : []; }
        catch (JsonException) { return []; }
        catch (IOException) { return []; }
    }

    static void Store(List<HistoryEntry> entries)
    {
        var tmp = FilePath + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(entries.TakeLast(200), Json.Options));
        File.Move(tmp, FilePath, overwrite: true);
    }

    internal void Append(HistoryEntry entry)
    {
        lock (gate) Store([.. Load(), entry]);
        Changed?.Invoke();
    }

    /// Recycles the outputs of `id` (or of the most recent job that isn't undone yet).
    public HistoryEntry? Undo(Guid? id = null)
    {
        HistoryEntry? undone;
        lock (gate)
        {
            var all = Load();
            var index = id is null ? all.FindLastIndex(e => !e.Undone) : all.FindIndex(e => e.Id == id);
            if (index < 0 || all[index].Undone) return null;
            foreach (var output in all[index].Outputs) Trash.Move(output);
            all[index].Undone = true;
            Store(all);
            undone = all[index];
        }
        Changed?.Invoke();
        return undone;
    }
}

static class Json
{
    public static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };
}
