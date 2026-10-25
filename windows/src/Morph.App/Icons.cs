namespace Morph.App;

/// Segoe icon glyphs for the SF Symbols names the engine gives its actions (and the app's own symbols). Glyphs
/// come from Segoe Fluent Icons on Windows 11 and Segoe MDL2 Assets on Windows 10, which share code points.
public static class Icons
{
    public const string Settings = "", Check = "", Warning = "", Info = "", Undo = "",
        Folder = "", Download = "", Lock = "", Power = "", Palette = "", Keyboard = "",
        Hand = "", Volume = "", Video = "", Star = "", OpenFile = "", Pin = "",
        Convert = "", Compress = "", Clean = "", Chevron = "", Document = "";

    static readonly Dictionary<string, string> symbols = new()
    {
        ["scribble.variable"] = "",
        ["photo"] = "",
        ["photo.on.rectangle"] = "",
        ["doc.richtext"] = "",
        ["doc.text"] = "",
        ["film"] = "",
        ["sparkles.rectangle.stack"] = "",
        ["waveform"] = "",
        ["waveform.badge.minus"] = "",
        ["waveform.and.magnifyingglass"] = "",
        ["text.alignleft"] = "",
        ["captions.bubble"] = "",
        ["tablecells"] = "",
        ["arrow.down.right.and.arrow.up.left"] = "",
        ["arrow.up.left.and.down.right.magnifyingglass"] = "",
        ["eye.slash"] = "",
        ["person.crop.circle.badge.xmark"] = "",
        ["eye.trianglebadge.exclamationmark"] = "",
        ["text.viewfinder"] = "",
        ["qrcode.viewfinder"] = "",
        ["doc.on.doc"] = "",
        ["scissors"] = "",
        ["speaker.slash"] = "",
        ["camera.viewfinder"] = "",
        ["speaker.wave.3"] = "",
        ["doc.zipper"] = "",
        ["archivebox"] = "",
        ["shippingbox.and.arrow.backward"] = "",
        ["lock.shield"] = "",
        ["globe"] = "",
        ["envelope"] = "",
        ["wand.and.stars"] = "",
        // The Actions wheel.
        ["square.and.arrow.up"] = "",
        ["link"] = "",
        ["folder"] = "",
        ["plus.rectangle.on.folder"] = "",
        ["terminal"] = "",
    };

    public static string For(string symbol) => symbols.GetValueOrDefault(symbol, Document);
}
