using System.IO;

namespace Morph.App;

public enum WheelPhase { Choosing, Running, Finished }

/// What the wheel shows and does: the files, the actions that fit them, which wheel and page is up, the
/// highlighted petal, and a job's progress and result. Raises `Changed` after every change; the window redraws.
public sealed class WheelModel
{
    public const int PerPage = WheelGeometry.PerPage;

    public IReadOnlyList<string> Files { get; private set; } = [];
    public IReadOnlyList<MorphAction> Actions { get; private set; } = [];
    /// Summoned mid-drag: waits for a drop rather than a click, and leaves focus alone. Until the drag reaches the
    /// wheel it doesn't know which files they are.
    public bool DropMode { get; }
    public ActionGroup Group { get; private set; }
    public int Page { get; private set; }
    public string? Hovered { get; private set; }
    public WheelPhase Phase { get; private set; } = WheelPhase.Choosing;
    public MorphAction? Running { get; private set; }
    public int Done { get; private set; }
    public int Total { get; private set; }
    public RunResult? Result { get; private set; }

    /// One size on the ring Compress and Resize fan out. Custom has no setting of its own: it asks.
    public sealed record SizeChoice(string Id, string Label, string Name, Func<Options, Options>? Adjust);

    /// The size ring showing around the wheel, for the petal the pointer is on.
    public (MorphAction Action, IReadOnlyList<SizeChoice> Choices)? Sizing { get; private set; }

    /// Asks for a size of one's own; the window supplies the dialog.
    public Func<MorphAction, Func<Options, Options>?>? AskCustomSize;

    public event Action? Changed;
    /// The page or wheel turned: the petals bloom again.
    public event Action? Turned;
    public Action Dismiss = () => { };

    public WheelModel(IReadOnlyList<string> files, bool dropMode, ActionGroup? group)
    {
        DropMode = dropMode;
        Group = group ?? ActionGroup.Convert;
        if (files.Count > 0) SetFiles(files, group);
    }

    public bool KnowsFiles => Files.Count > 0;

    /// The files arrive with the drag in drop mode; the asked-for wheel stays up if these files have it.
    public void SetFiles(IReadOnlyList<string> files, ActionGroup? wanted = null)
    {
        var paths = files.Select(Path.GetFullPath).ToList();
        if (paths.SequenceEqual(Files, StringComparer.OrdinalIgnoreCase)) return;
        Files = paths;
        Actions = [.. Library.ActionsFor(paths).Where(a => a.Group != ActionGroup.File), .. FileActions.For(paths)];
        var want = wanted ?? Group;
        Group = Groups.Contains(want) ? want : Actions.Any(a => a.Group == ActionGroup.Convert) ? ActionGroup.Convert : ActionGroup.Tool;
        Page = 0;
        Hovered = null;
        Sizing = null;
        Turned?.Invoke();
        Changed?.Invoke();
    }

    public IReadOnlyList<ActionGroup> Groups =>
        KnowsFiles ? WheelKeyMap.Wheels.Where(g => Actions.Any(a => a.Group == g)).ToList() : WheelKeyMap.Wheels;

    public IReadOnlyList<MorphAction> Visible => Actions.Where(a => a.Group == Group).ToList();
    public int Pages => Math.Max(1, (Visible.Count + PerPage - 1) / PerPage);
    public IReadOnlyList<MorphAction> PageItems => Visible.Skip(Page * PerPage).Take(PerPage).ToList();

    public string Summary
    {
        get
        {
            if (Files.Count == 0) return "Morph";
            if (Files.Count == 1) return Path.GetFileName(Path.TrimEndingDirectorySeparator(Files[0]));
            var kinds = Files.Select(FileKinds.Of).Distinct().ToList();
            var noun = kinds.Count == 1 ? kinds[0].ToString().ToLowerInvariant() : "file";
            return $"{Files.Count} {noun}s";
        }
    }

    public string Caption
    {
        get
        {
            if (!KnowsFiles) return "Drop on the wheel";
            if (Actions.Count == 0) return "Nothing fits these files";
            if (Hovered is not null && Hovered == Sizing?.Action.Id) return "Or pick a size";
            if (Hovered is not null) return DropMode ? "Release to run" : "Click to run";
            return DropMode ? "Drop on an action" : Group.Label();
        }
    }

    public string? HoverTitle =>
        Sizing?.Choices.FirstOrDefault(c => c.Id == Hovered) is { } choice ? choice.Name
        : Actions.FirstOrDefault(a => a.Id == Hovered) is { } action
            ? action.Group == ActionGroup.Convert ? $"Convert to {action.Title}" : action.Title
            : null;

    // MARK: Navigation

    void SetHovered(string? id)
    {
        if (id == Hovered) return;
        Hovered = id;
        if (id is not null) Feedback.Shared.Tick();
        Changed?.Invoke();
    }

    public void ClearHover() => SetHovered(null);

    public void Select(ActionGroup group)
    {
        if (group == Group || !Groups.Contains(group)) return;
        Group = group;
        Page = 0;
        Hovered = null;
        Sizing = null;
        Feedback.Shared.Tick();
        Turned?.Invoke();
        Changed?.Invoke();
    }

    public void CycleGroup(int delta)
    {
        var groups = Groups;
        var i = groups.ToList().IndexOf(Group);
        if (i < 0 || groups.Count < 2) return;
        Select(groups[(i + delta + groups.Count) % groups.Count]);
    }

    /// Highlights the petal or size under a point relative to the ring's centre. Resting on Compress or Resize
    /// fans out its sizes; any other petal folds them away.
    public void Hover(double x, double y)
    {
        if (SizeAt(x, y) is { } choice) { SetHovered(choice.Id); return; }
        var items = PageItems;
        if (WheelGeometry.Slot(x, y, items.Count) is not int slot) { SetHovered(null); return; }
        ShowSizes(items[slot]);
        SetHovered(items[slot].Id);
    }

    public MorphAction? ActionAt(double x, double y)
    {
        var items = PageItems;
        return WheelGeometry.Slot(x, y, items.Count) is int slot ? items[slot] : null;
    }

    public bool CanDrop(double x, double y) => SizeAt(x, y) is not null || ActionAt(x, y) is not null;

    /// A click or a drop at a point: a size runs its action at that size, a petal runs as set in Settings.
    public bool Pick(double x, double y)
    {
        if (SizeAt(x, y) is { } choice) { Choose(choice); return true; }
        if (ActionAt(x, y) is { } action) { Run(action); return true; }
        return false;
    }

    /// Where the size ring sits, for the drawing.
    public (double Start, double Step)? SizeArc
    {
        get
        {
            if (Sizing is not { } sizing) return null;
            var items = PageItems.ToList();
            var index = items.FindIndex(a => a.Id == sizing.Action.Id);
            return index < 0 ? null : WheelGeometry.SizeArc(index, items.Count, sizing.Choices.Count);
        }
    }

    SizeChoice? SizeAt(double x, double y) =>
        Sizing is { } sizing && SizeArc is { } arc && WheelGeometry.SizeSlot(x, y, arc, sizing.Choices.Count) is int i ? sizing.Choices[i] : null;

    void ShowSizes(MorphAction action)
    {
        if (Sizing?.Action.Id == action.Id) return;
        var choices = SizesFor(action);
        if (choices is null && Sizing is null) return;
        Sizing = choices is null ? null : (action, choices);
        Changed?.Invoke();
    }

    /// The sizes Compress (on photos, the only files a size limit applies to) and Resize fan out, or null.
    IReadOnlyList<SizeChoice>? SizesFor(MorphAction action)
    {
        var custom = new SizeChoice("size.custom", "Custom…", "A size of your own", null);
        if (action.Id == "tool.compress" && Files.Count > 0 && Files.All(f => FileKinds.Of(f) == FileKind.Image))
            return [.. new long[] { 0 }.Concat(SizeLimit.Presets).Select(bytes => new SizeChoice($"size.{bytes}",
                bytes == 0 ? "Smallest" : SizeLimit.Label(bytes), bytes == 0 ? "Smallest that looks the same" : $"Under {SizeLimit.Label(bytes)}",
                o => o with { TargetBytes = bytes == 0 ? null : bytes })), custom];
        if (action.Id == "tool.resize")
            return [new SizeChoice("size.fit", "Keep shape", "Keep shape, 2048 px", o => o with { ExactSize = null }),
                .. PixelSize.Presets.SelectMany(g => g.Items).DistinctBy(i => i.Size)
                    .Select(i => new SizeChoice($"size.{i.Size.Key}", i.Size.Label, i.Name, o => o with { ExactSize = i.Size })), custom];
        return null;
    }

    /// Runs the size ring's action at `choice`, or asks for a size of one's own.
    public void Choose(SizeChoice choice)
    {
        if (Sizing is not { } sizing) return;
        if ((choice.Adjust ?? AskCustomSize?.Invoke(sizing.Action)) is { } adjust) Run(sizing.Action, adjust);
    }

    /// Folds the size ring away; false if it wasn't showing.
    public bool LeaveSizes()
    {
        if (Sizing is not { } sizing) return false;
        if (Hovered?.StartsWith("size.") == true) Hovered = sizing.Action.Id;
        Sizing = null;
        Changed?.Invoke();
        return true;
    }

    /// Up arrow: from Compress or Resize into its sizes, starting on the one saved in Settings.
    public bool StepOut()
    {
        if (Sizing is not { } sizing || Hovered != sizing.Action.Id) return false;
        var prefs = Preferences.Shared;
        var saved = sizing.Action.Id == "tool.compress" ? $"size.{prefs.SizeLimit}" : prefs.PhotoSize is { } size ? $"size.{size.Key}" : "size.fit";
        SetHovered(sizing.Choices.Any(c => c.Id == saved) ? saved : sizing.Choices[0].Id);
        return true;
    }

    /// Down arrow: from a size back to its petal.
    public bool StepIn()
    {
        if (Sizing is not { } sizing || !sizing.Choices.Any(c => c.Id == Hovered)) return false;
        SetHovered(sizing.Action.Id);
        return true;
    }

    /// Moves the highlight around the ring, turning to the next page at the ends; among sizes, along the sizes.
    public void Step(int delta)
    {
        if (Sizing is { } sizing)
        {
            var at = sizing.Choices.ToList().FindIndex(c => c.Id == Hovered);
            if (at >= 0)
            {
                SetHovered(sizing.Choices[(at + delta + sizing.Choices.Count) % sizing.Choices.Count].Id);
                return;
            }
        }
        StepPetals(delta);
        if (PageItems.FirstOrDefault(a => a.Id == Hovered) is { } hovered) ShowSizes(hovered);
    }

    void StepPetals(int delta)
    {
        var items = PageItems;
        if (items.Count == 0) return;
        var i = items.ToList().FindIndex(a => a.Id == Hovered);
        if (i < 0) { SetHovered((delta >= 0 ? items[0] : items[^1]).Id); return; }
        var j = i + delta;
        if (j >= items.Count || j < 0)
        {
            if (Pages > 1)
            {
                TurnPage(j < 0 ? -1 : 1);
                var page = PageItems;
                SetHovered((j < 0 ? page[^1] : page[0]).Id);
            }
            else SetHovered(items[(j + items.Count) % items.Count].Id);
            return;
        }
        SetHovered(items[j].Id);
    }

    public void TurnPage(int delta)
    {
        if (Pages < 2) return;
        Page = (Page + delta + Pages) % Pages;
        Hovered = null;
        Sizing = null;
        Turned?.Invoke();
        Changed?.Invoke();
    }

    public void RunHighlighted()
    {
        if (Sizing?.Choices.FirstOrDefault(c => c.Id == Hovered) is { } choice) Choose(choice);
        else if (PageItems.FirstOrDefault(a => a.Id == Hovered) is { } action) Run(action);
    }

    // MARK: Running

    public async void Run(MorphAction action, Func<Options, Options>? adjust = null)
    {
        if (Phase != WheelPhase.Choosing) return;
        var files = Files;
        var prefs = Preferences.Shared;
        var options = adjust is null ? prefs.Options : adjust(prefs.Options);
        if (action.Group == ActionGroup.File)
        {
            // Acts on the files themselves and may open its own window, so get out of the way first.
            Dismiss();
            try { await action.Run(files, prefs.Options, CancellationToken.None); }
            catch (Exception e) when (e is not OperationCanceledException) { FileActions.Report(e); }
            return;
        }
        Phase = WheelPhase.Running;
        Running = action;
        (Done, Total) = (0, files.Count);
        Changed?.Invoke();
        var dispatcher = System.Windows.Threading.Dispatcher.CurrentDispatcher;
        var result = await Task.Run(() => Runner.Run(action, files, options, progress: (done, total) =>
            dispatcher.BeginInvoke(() =>
            {
                if (Phase != WheelPhase.Running) return;
                (Done, Total) = (done, total);
                Changed?.Invoke();
            })));
        Result = result;
        Phase = WheelPhase.Finished;
        Changed?.Invoke();
        Feedback.Done(failed: result.Failures.Count > 0);
        if (result.Failures.Count > 0) return;
        if (prefs.RevealWhenDone && result.Outputs.Count > 0) { Reveal(); return; }
        // Long enough to read "171 KB → 144 KB".
        await Task.Delay(3500);
        if (Phase == WheelPhase.Finished) Dismiss();
    }

    public void Reveal()
    {
        if (Result is { Outputs.Count: > 0 } result) Shell.Reveal(result.Outputs);
        Dismiss();
    }
}
