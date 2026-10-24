// Draws Morph's Windows icons: the app and tray icon, and the MSIX tile images.
//   dotnet run windows/scripts/make-icon.cs
// Same mark as scripts/make-icon.swift: flat Teal Ink with Morph's seven white drops.
#:package Magick.NET-Q8-AnyCPU@14.17.2
using ImageMagick;
using ImageMagick.Drawing;

var root = Path.GetFullPath(Path.Combine(AppContext.GetData("EntryPointFileDirectoryPath") as string ?? "windows/scripts", ".."));
var appAssets = Path.Combine(root, "src", "Morph.App", "Assets");
var tiles = Path.Combine(root, "packaging", "Assets");
Directory.CreateDirectory(appAssets);
Directory.CreateDirectory(tiles);

// The icon on a transparent canvas of `canvas` pixels, its tile `size` pixels wide. Tiny sizes drop the corner
// rounding a little and the margin entirely, so the mark stays legible in the tray.
MagickImage Icon(int canvas, double size)
{
    var image = new MagickImage(MagickColors.Transparent, (uint)canvas, (uint)canvas);
    var inset = (canvas - size) / 2;
    var corner = size * 0.22;
    var drawables = new Drawables()
        .FillColor(new MagickColor("#0B6E69"))
        .RoundRectangle(inset, inset, inset + size, inset + size, corner, corner);
    var mark = size * 0.62;
    double reach = mark * 0.31, radius = mark * 0.12, c = canvas / 2.0;
    drawables.FillColor(MagickColors.White);
    for (var i = -1; i < 6; i++)
    {
        var angle = i * Math.PI / 3 - Math.PI / 2;
        double x = c + (i < 0 ? 0 : Math.Cos(angle) * reach), y = c + (i < 0 ? 0 : Math.Sin(angle) * reach);
        drawables.Ellipse(x, y, radius, radius, 0, 360);
    }
    image.Draw(drawables);
    return image;
}

// Draws big and shrinks, which antialiases far better than drawing small.
MagickImage Render(int width, int height, double fraction)
{
    const int scale = 4;
    var side = Math.Min(width, height) * scale;
    using var icon = Icon(side, side * fraction);
    var canvas = new MagickImage(MagickColors.Transparent, (uint)(width * scale), (uint)(height * scale));
    canvas.Composite(icon, Gravity.Center, CompositeOperator.Over);
    canvas.Resize((uint)width, (uint)height);
    return canvas;
}

void Save(MagickImage image, string path) { image.Write(path, MagickFormat.Png32); image.Dispose(); }

// App and tray icon.
using (var ico = new MagickImageCollection())
{
    foreach (var px in new[] { 16, 20, 24, 32, 40, 48, 64, 256 }) ico.Add(Render(px, px, px <= 24 ? 1.0 : 0.94));
    ico.Write(Path.Combine(appAssets, "Morph.ico"), MagickFormat.Ico);
}
Save(Render(256, 256, 0.94), Path.Combine(appAssets, "Morph.png"));

// MSIX images. The 44 px logo is the taskbar and Start icon; target sizes are drawn unplated, edge to edge.
foreach (var (scale, factor) in new[] { (100, 1.0), (125, 1.25), (150, 1.5), (200, 2.0), (400, 4.0) })
{
    int S(double v) => (int)Math.Round(v * factor);
    Save(Render(S(44), S(44), 0.94), Path.Combine(tiles, $"Square44x44Logo.scale-{scale}.png"));
    Save(Render(S(150), S(150), 0.5), Path.Combine(tiles, $"Square150x150Logo.scale-{scale}.png"));
    Save(Render(S(310), S(150), 0.5), Path.Combine(tiles, $"Wide310x150Logo.scale-{scale}.png"));
    Save(Render(S(71), S(71), 0.6), Path.Combine(tiles, $"SmallTile.scale-{scale}.png"));
    Save(Render(S(310), S(310), 0.5), Path.Combine(tiles, $"LargeTile.scale-{scale}.png"));
    Save(Render(S(50), S(50), 0.94), Path.Combine(tiles, $"StoreLogo.scale-{scale}.png"));
}
foreach (var px in new[] { 16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 256 })
{
    var fraction = px <= 24 ? 1.0 : 0.94;
    Save(Render(px, px, fraction), Path.Combine(tiles, $"Square44x44Logo.targetsize-{px}.png"));
    Save(Render(px, px, fraction), Path.Combine(tiles, $"Square44x44Logo.targetsize-{px}_altform-unplated.png"));
    Save(Render(px, px, fraction), Path.Combine(tiles, $"Square44x44Logo.targetsize-{px}_altform-lightunplated.png"));
}
Console.WriteLine($"Wrote {appAssets} and {tiles}");
