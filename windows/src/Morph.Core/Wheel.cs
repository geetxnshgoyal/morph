namespace Morph;

/// The keys that summon one wheel while files are being dragged: any combination of Ctrl, Alt, Shift and Win,
/// or Tab alone. Bits follow the Mac app's (⌘ 1, ⌥ 2, ⌃ 4, ⇧ 8, Tab 16) with Ctrl standing in for ⌘, Alt for ⌥ and
/// Win for ⌃. No keys means off.
[Flags]
public enum DragKeys
{
    Off = 0,
    Ctrl = 1,
    Alt = 2,
    Win = 4,
    Shift = 8,
    Tab = 16,
}

public static class DragKeyInfo
{
    /// Windows' own order for shortcut names: Win+Ctrl+Alt+Shift.
    static readonly (DragKeys Key, string Name)[] modifiers = [(DragKeys.Win, "Win"), (DragKeys.Ctrl, "Ctrl"), (DragKeys.Alt, "Alt"), (DragKeys.Shift, "Shift")];

    /// Single keys first, in the order people reach for them.
    public static readonly IReadOnlyList<DragKeys> Singles = [DragKeys.Shift, DragKeys.Ctrl, DragKeys.Alt, DragKeys.Win, DragKeys.Tab];

    /// Every two-, three- and four-modifier combination, fewest keys first.
    public static readonly IReadOnlyList<DragKeys> Combinations = Enumerable.Range(1, 15).Select(v => (DragKeys)v)
        .Where(k => k.Count() > 1).OrderBy(k => k.Count()).ThenBy(k => (int)k).ToList();

    public static int Count(this DragKeys keys) => System.Numerics.BitOperations.PopCount((uint)keys);

    /// "Ctrl+Shift", "Tab", or "Off".
    public static string Label(this DragKeys keys)
    {
        if (keys == DragKeys.Off) return "Off";
        if (keys == DragKeys.Tab) return "Tab";
        return string.Join("+", modifiers.Where(m => keys.HasFlag(m.Key)).Select(m => m.Name));
    }
}

/// Which wheel the keyboard asks for during one drag. A wheel is chosen the moment its exact keys go down and
/// stays chosen once they are released, so a tap is enough; pressing another wheel's keys switches to it, and
/// keys that match no wheel change nothing. Escape, or the end of the drag, clears the choice.
public sealed class WheelShortcutState
{
    DragKeys previous;
    bool wasDragging;

    public ActionGroup? Group { get; private set; }

    public void Update(DragKeys keys, bool dragging, bool escape, Func<DragKeys, ActionGroup?> match)
    {
        if (dragging && !escape)
        {
            // Only a key going down can choose; on the drag's first frame, keys already held count too.
            var newlyPressed = keys & ~previous;
            if ((!wasDragging || newlyPressed != DragKeys.Off) && match(keys) is { } chosen) Group = chosen;
        }
        else Group = null;
        previous = keys;
        wasDragging = dragging;
    }
}

/// Which keys open which wheel. Assigning keys another wheel already uses swaps the two, so wheels never clash.
public sealed class WheelKeyMap
{
    public static readonly IReadOnlyList<ActionGroup> Wheels = [ActionGroup.Convert, ActionGroup.Tool, ActionGroup.Recipe, ActionGroup.File];

    /// Shift for Convert as on the Mac, Ctrl for ⌘ and Alt for ⌥. Recipes take Ctrl+Shift rather than Win, which
    /// on its own opens Start. All of these are taps: Explorer only reads them as copy/move/link while held at the
    /// moment of a drop, and Morph's wheel takes every drop as a copy.
    public static readonly IReadOnlyDictionary<ActionGroup, DragKeys> Defaults = new Dictionary<ActionGroup, DragKeys>
    {
        [ActionGroup.Convert] = DragKeys.Shift,
        [ActionGroup.Tool] = DragKeys.Ctrl,
        [ActionGroup.Recipe] = DragKeys.Ctrl | DragKeys.Shift,
        [ActionGroup.File] = DragKeys.Alt,
    };

    readonly Dictionary<ActionGroup, DragKeys> keys;

    public WheelKeyMap(IReadOnlyDictionary<ActionGroup, DragKeys>? saved = null)
    {
        keys = new Dictionary<ActionGroup, DragKeys>(Defaults);
        if (saved is null) return;
        foreach (var (group, value) in saved) keys[group] = value;
    }

    public DragKeys this[ActionGroup group] => keys.GetValueOrDefault(group);

    public IReadOnlyDictionary<ActionGroup, DragKeys> All => keys;

    /// The wheel whose keys are exactly `pressed`. Holding extra keys matches nothing, so Ctrl+Shift never opens Ctrl's wheel.
    public ActionGroup? Match(DragKeys pressed) =>
        pressed == DragKeys.Off ? null : Wheels.Cast<ActionGroup?>().FirstOrDefault(g => keys[g!.Value] == pressed);

    public void Set(ActionGroup group, DragKeys value)
    {
        var old = keys[group];
        if (value != DragKeys.Off)
            foreach (var other in Wheels)
                if (other != group && keys[other] == value) keys[other] = old;
        keys[group] = value;
    }

    public bool Uses(DragKeys key) => keys.Values.Any(k => k.HasFlag(key));
}

public static class Wheels
{
    public static string Label(this ActionGroup group) => group switch
    {
        ActionGroup.Convert => "Convert",
        ActionGroup.Tool => "Tools",
        ActionGroup.Recipe => "Recipes",
        _ => "Actions",
    };
}

/// The wheel's measurements and hit testing, shared by the window, the drawing and the tests.
public static class WheelGeometry
{
    public const double Width = 440;
    public const double Height = 496;
    /// Centre of the ring from the window's top-left; the wheel bar hangs below the ring.
    public const double CenterX = 220, CenterY = 220;
    public const double OuterRadius = 168;
    public const double InnerRadius = 88;
    public const double HubRadius = 76;
    /// Neighbouring petals are this far apart all the way out.
    public const double GapWidth = 7;
    /// How far a highlighted petal grows outward.
    public const double Lift = 12;
    /// Square the ring is drawn in, with room for a lifted petal and its glow.
    public const double Side = (OuterRadius + Lift + 12) * 2;
    public const double LabelRadius = (InnerRadius + OuterRadius) / 2 + 2;
    /// Petals per ring; more actions than this page around with a turn of the wheel.
    public const int PerPage = 8;

    /// Centre of petal `index`, in degrees clockwise from three o'clock: the first points straight up.
    public static double Angle(int index, int count) => (double)index / Math.Max(count, 1) * 360 - 90;

    /// The petal under a point relative to the ring's centre (y down), or null over the hub or far outside the ring.
    public static int? Slot(double x, double y, int count)
    {
        var distance = Math.Sqrt(x * x + y * y);
        if (count <= 0 || distance < HubRadius || distance > OuterRadius + Lift + 24) return null;
        var sector = 360.0 / count;
        var degrees = (Math.Atan2(y, x) * 180 / Math.PI + 90) % 360;
        if (degrees < 0) degrees += 360;
        return (int)((degrees + sector / 2) / sector) % count;
    }
}
