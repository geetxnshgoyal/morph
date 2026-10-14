using System.Runtime.CompilerServices;
using ImageMagick;
using ImageMagick.Drawing;

namespace Morph.Tests;

static class Setup
{
    public static readonly List<string> Recycled = [];

    /// History, recipes and the recycle bin all go to a scratch folder, never the real ones.
    [ModuleInitializer]
    internal static void Init()
    {
        Environment.SetEnvironmentVariable("MORPH_HOME", Path.Combine(Path.GetTempPath(), "morph-tests-" + Guid.NewGuid().ToString("N")));
        Trash.Override = path =>
        {
            lock (Recycled) Recycled.Add(path);
            if (Directory.Exists(path)) Directory.Delete(path, true); else File.Delete(path);
        };
    }
}

/// A fresh folder per test, deleted afterwards.
public abstract class Scratch : IDisposable
{
    protected readonly string Dir = Directory.CreateTempSubdirectory("morph-test-").FullName;

    protected string PathOf(string name) => System.IO.Path.Combine(Dir, name);

    protected string Write(string name, string text)
    {
        var path = PathOf(name);
        File.WriteAllText(path, text);
        return path;
    }

    /// A gradient picture, so lossy encoders have something to chew on.
    protected string Picture(string name, uint width = 640, uint height = 480, bool alpha = false, Action<MagickImage>? edit = null)
    {
        using var image = new MagickImage($"gradient:#FF8F38-#FF6661", width, height);
        image.Draw(new Drawables().FillColor(MagickColors.White).Circle(width / 2.0, height / 2.0, width / 2.0 + 40, height / 2.0));
        if (alpha)
        {
            image.Alpha(AlphaOption.Set);
            image.Draw(new Drawables().FillColor(MagickColors.Transparent).Rectangle(0, 0, 40, 40));
        }
        edit?.Invoke(image);
        var path = PathOf(name);
        image.Write(path);
        return path;
    }

    public void Dispose()
    {
        try { Directory.Delete(Dir, true); } catch (IOException) { }
        GC.SuppressFinalize(this);
    }
}
