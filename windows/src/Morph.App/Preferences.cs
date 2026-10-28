using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Morph.App;

/// User settings, saved as JSON next to Morph's history and shared by the tray, Settings, Welcome and the wheel.
public sealed class Preferences : INotifyPropertyChanged
{
    public static readonly Preferences Shared = Load();

    public event PropertyChangedEventHandler? PropertyChanged;

    /// What's written to settings.json; the keys match the Mac app's where there is one.
    sealed class Stored
    {
        public bool HasSeenWelcome { get; set; }
        public bool PlaySounds { get; set; } = true;
        public bool RevealWhenDone { get; set; }
        public CompressionLevel Compression { get; set; } = CompressionLevel.Balanced;
        public long SizeLimit { get; set; }
        public string? PhotoSize { get; set; }
        public string? PhotoCaption { get; set; }
        public string? OutputFolder { get; set; }
        public string Palette { get; set; } = "teal";
        public Dictionary<ActionGroup, DragKeys>? Keys { get; set; }
    }

    Stored stored = new();
    WheelKeyMap keys = new();

    static string FilePath => Path.Combine(Paths.Support, "settings.json");

    static readonly JsonSerializerOptions json = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    static Preferences Load()
    {
        var prefs = new Preferences();
        try
        {
            if (File.Exists(FilePath) && JsonSerializer.Deserialize<Stored>(File.ReadAllText(FilePath), json) is { } stored)
            {
                prefs.stored = stored;
                prefs.keys = new WheelKeyMap(stored.Keys);
            }
        }
        catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException) { }
        return prefs;
    }

    void Save([CallerMemberName] string? name = null)
    {
        stored.Keys = new Dictionary<ActionGroup, DragKeys>(keys.All);
        try
        {
            var tmp = FilePath + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(stored, json));
            File.Move(tmp, FilePath, overwrite: true);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    public bool HasSeenWelcome { get => stored.HasSeenWelcome; set { stored.HasSeenWelcome = value; Save(); } }
    public bool PlaySounds { get => stored.PlaySounds; set { stored.PlaySounds = value; Save(); } }
    public bool RevealWhenDone { get => stored.RevealWhenDone; set { stored.RevealWhenDone = value; Save(); } }
    public CompressionLevel Compression { get => stored.Compression; set { stored.Compression = value; Save(); } }
    /// Bytes Compress must fit under, for upload forms; 0 is no limit.
    public long SizeLimit { get => stored.SizeLimit; set { stored.SizeLimit = value; Save(); } }
    /// Exact size Resize makes for forms; null keeps Resize's usual fit to 2048 px.
    public PixelSize? PhotoSize { get => PixelSize.Parse(stored.PhotoSize); set { stored.PhotoSize = value?.Key; Save(); } }
    /// Printed with the date under the photo at that size; empty prints nothing.
    public string PhotoCaption { get => stored.PhotoCaption ?? ""; set { stored.PhotoCaption = value; Save(); } }
    /// Null saves results next to the original.
    public string? OutputFolder { get => stored.OutputFolder; set { stored.OutputFolder = value; Save(); } }

    public Palette Palette
    {
        get => Palette.Named(stored.Palette);
        set { stored.Palette = value.Id; Save(); }
    }

    public DragKeys DragKeys(ActionGroup group) => keys[group];

    /// The wheel whose keys are exactly `pressed`.
    public ActionGroup? Group(DragKeys pressed) => keys.Match(pressed);

    /// Assigns keys to a wheel; a wheel that already used them takes this one's old keys, so wheels never clash.
    public void SetDragKeys(ActionGroup group, DragKeys value)
    {
        keys.Set(group, value);
        Save(nameof(DragKeys));
    }

    /// Options for a run from the wheel.
    public Options Options
    {
        get
        {
            string? folder = null;
            if (OutputFolder is { Length: > 0 } chosen)
            {
                try { Directory.CreateDirectory(chosen); folder = chosen; }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
            }
            return new Options
            {
                Compression = Compression, TargetBytes = SizeLimit > 0 ? SizeLimit : null, OutputDirectory = folder,
                ExactSize = PhotoSize, Caption = PhotoCaption.Trim() is { Length: > 0 } caption ? caption : null,
            };
        }
    }
}
