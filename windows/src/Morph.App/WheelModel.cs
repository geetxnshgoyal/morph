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
            if (Hovered is not null) return DropMode ? "Release to run" : "Click to run";
            return DropMode ? "Drop on an action" : Group.Label();
        }
    }

    public string? HoverTitle => Actions.FirstOrDefault(a => a.Id == Hovered) is { } action
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

    /// Highlights the petal under a point relative to the ring's centre.
    public void Hover(double x, double y)
    {
        var items = PageItems;
        SetHovered(WheelGeometry.Slot(x, y, items.Count) is int slot ? items[slot].Id : null);
    }

    public MorphAction? ActionAt(double x, double y)
    {
        var items = PageItems;
        return WheelGeometry.Slot(x, y, items.Count) is int slot ? items[slot] : null;
    }

    /// Moves the highlight around the ring, turning to the next page at the ends.
    public void Step(int delta)
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
        Turned?.Invoke();
        Changed?.Invoke();
    }

    public void RunHighlighted()
    {
        if (PageItems.FirstOrDefault(a => a.Id == Hovered) is { } action) Run(action);
    }

    // MARK: Running

    public async void Run(MorphAction action)
    {
        if (Phase != WheelPhase.Choosing) return;
        var files = Files;
        var prefs = Preferences.Shared;
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
        var result = await Task.Run(() => Runner.Run(action, files, prefs.Options, progress: (done, total) =>
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
