namespace Morph.Tests;

public class WheelShortcutTests
{
    static readonly WheelKeyMap map = new();

    static ActionGroup? Step(WheelShortcutState state, DragKeys keys, bool dragging = true, bool escape = false)
    {
        state.Update(keys, dragging, escape, map.Match);
        return state.Group;
    }

    [Fact]
    public void TapOpensAndReleaseKeepsTheWheel()
    {
        var state = new WheelShortcutState();
        Assert.Null(Step(state, DragKeys.Off));
        Assert.Equal(ActionGroup.Convert, Step(state, DragKeys.Shift));
        Assert.Equal(ActionGroup.Convert, Step(state, DragKeys.Off));
    }

    [Fact]
    public void AnotherWheelsKeysSwitch()
    {
        var state = new WheelShortcutState();
        Step(state, DragKeys.Off);
        Step(state, DragKeys.Shift);
        Step(state, DragKeys.Off);
        Assert.Equal(ActionGroup.Tool, Step(state, DragKeys.Ctrl));
        Assert.Equal(ActionGroup.Tool, Step(state, DragKeys.Off));
        Assert.Equal(ActionGroup.File, Step(state, DragKeys.Alt));
    }

    [Fact]
    public void CombinationsNeedTheExactKeys()
    {
        var state = new WheelShortcutState();
        Step(state, DragKeys.Off);
        // Ctrl goes down first and opens Tools; Shift joining it makes Ctrl+Shift, which is Recipes.
        Assert.Equal(ActionGroup.Tool, Step(state, DragKeys.Ctrl));
        Assert.Equal(ActionGroup.Recipe, Step(state, DragKeys.Ctrl | DragKeys.Shift));
        // Letting go of Shift leaves Ctrl held, but nothing new went down, so Recipes stays.
        Assert.Equal(ActionGroup.Recipe, Step(state, DragKeys.Ctrl));
        // Keys that match no wheel change nothing.
        Assert.Equal(ActionGroup.Recipe, Step(state, DragKeys.Ctrl | DragKeys.Alt | DragKeys.Win));
    }

    [Fact]
    public void EscapeAndDragEndClear()
    {
        var state = new WheelShortcutState();
        Step(state, DragKeys.Off);
        Step(state, DragKeys.Shift);
        Assert.Null(Step(state, DragKeys.Off, escape: true));
        // Still dragging after Escape: the same keys can open it again.
        Assert.Equal(ActionGroup.Convert, Step(state, DragKeys.Shift));
        Assert.Null(Step(state, DragKeys.Off, dragging: false));
        Assert.Null(Step(state, DragKeys.Off, dragging: false));
    }

    [Fact]
    public void KeysHeldWhenTheDragStartsCount()
    {
        var state = new WheelShortcutState();
        Assert.Equal(ActionGroup.Tool, Step(state, DragKeys.Ctrl));
    }

    [Fact]
    public void AssigningUsedKeysSwapsThem()
    {
        var keys = new WheelKeyMap();
        keys.Set(ActionGroup.Tool, DragKeys.Shift);
        Assert.Equal(DragKeys.Shift, keys[ActionGroup.Tool]);
        Assert.Equal(DragKeys.Ctrl, keys[ActionGroup.Convert]);
        keys.Set(ActionGroup.Recipe, DragKeys.Off);
        Assert.Null(keys.Match(DragKeys.Ctrl | DragKeys.Shift));
        Assert.Null(keys.Match(DragKeys.Off));
    }

    [Fact]
    public void Labels()
    {
        Assert.Equal("Ctrl+Shift", (DragKeys.Shift | DragKeys.Ctrl).Label());
        Assert.Equal("Win+Ctrl+Alt+Shift", (DragKeys.Ctrl | DragKeys.Alt | DragKeys.Shift | DragKeys.Win).Label());
        Assert.Equal("Tab", DragKeys.Tab.Label());
        Assert.Equal(11, DragKeyInfo.Combinations.Count);
    }

    [Fact]
    public void PetalsAreFoundByPosition()
    {
        Assert.Equal(0, WheelGeometry.Slot(0, -130, 8));
        Assert.Equal(2, WheelGeometry.Slot(130, 0, 8));
        Assert.Equal(4, WheelGeometry.Slot(0, 130, 8));
        Assert.Equal(6, WheelGeometry.Slot(-130, 0, 8));
        Assert.Equal(1, WheelGeometry.Slot(95, -95, 8));
        Assert.Null(WheelGeometry.Slot(10, 10, 8));
        Assert.Null(WheelGeometry.Slot(400, 0, 8));
        Assert.Equal(-90, WheelGeometry.Angle(0, 5));
    }
}
