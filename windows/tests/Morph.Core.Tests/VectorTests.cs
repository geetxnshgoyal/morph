using ImageMagick;
using ImageMagick.Drawing;

namespace Morph.Tests;

public class VectorTests : Scratch
{
    const string Logo = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 200 100">
          <rect width="200" height="100" fill="#ffffff"/>
          <circle cx="50" cy="50" r="40" fill="#0b6e69"/>
          <image xlink:href="https://example.com/tracker.png" width="10" height="10"/>
        </svg>
        """;

    [Fact]
    public void SvgIsAnImage()
    {
        var svg = Write("logo.svg", Logo);
        Assert.Equal(FileKind.Image, FileKinds.Of(svg));
        var ids = Library.ActionsFor([svg]).Select(a => a.Id).ToList();
        Assert.Contains("convert.png", ids);
        Assert.Contains("convert.images-pdf", ids);
        Assert.Contains("tool.resize", ids);
        Assert.DoesNotContain("convert.svg", ids);
        Assert.DoesNotContain("tool.compress", ids);
        Assert.DoesNotContain("tool.strip-metadata", ids);
        Assert.Contains("convert.svg", Library.ActionsFor([Picture("a.png")]).Select(a => a.Id));
    }

    [Fact]
    public void OutsideReferencesAreStripped()
    {
        var svg = System.Text.Encoding.UTF8.GetString(VectorOps.Contained(Write("logo.svg", Logo)));
        Assert.DoesNotContain("example.com", svg);
        Assert.Contains("circle", svg);
    }

    [Fact]
    public void SvgRendersAtItsOwnShapeAndAtLeastIconSize()
    {
        var svg = Write("logo.svg", Logo);
        var png = ImageOps.Convert(svg, ImageFormat.Png, new Options());
        using var image = new MagickImage(png);
        Assert.Equal(1024u, image.Width);
        Assert.Equal(512u, image.Height);
        // The circle is drawn where the SVG puts it.
        var middle = image.GetPixels().GetPixel(256, 256).ToColor()!;
        Assert.True(middle.R < 40 && middle.G > 90, $"expected teal, got {middle}");

        var small = ImageOps.Convert(svg, ImageFormat.Jpg, new Options { MaxPixel = 300 });
        using var jpg = new MagickImage(small);
        Assert.Equal(300u, jpg.Width);
    }

    [Fact]
    public void ImagesTraceIntoShapes()
    {
        var png = Picture("badge.png", 400, 300, edit: image =>
        {
            image.Draw(new Drawables().FillColor(MagickColors.White).Rectangle(0, 0, 400, 300));
            image.Draw(new Drawables().FillColor(new MagickColor("#0b6e69")).Circle(200, 150, 300, 150));
        });
        var svg = VectorOps.Trace(png, new Options());
        Assert.Equal(PathOf("badge.svg"), svg);
        var text = File.ReadAllText(svg);
        Assert.Contains("width=\"400\" height=\"300\"", text);
        Assert.DoesNotContain("<image", text);
        Assert.Matches("fill=\"#0[ab]6[de]6[89]\"", text);
        Assert.InRange(text.Length, 100, 20_000);

        // Drawn back, it looks like the picture it came from.
        var back = ImageOps.Convert(svg, ImageFormat.Png, new Options { MaxPixel = 400, OutputDirectory = Directory.CreateDirectory(PathOf("back")).FullName });
        using var original = new MagickImage(png);
        using var traced = new MagickImage(back);
        Assert.True(new Similarity(original).Score(traced) > 0.9);
    }

    [Fact]
    public void FewerColorsMakeSmallerFiles()
    {
        var png = Picture("gradient.png");
        var many = new FileInfo(VectorOps.Trace(png, new Options { Colors = 24 })).Length;
        var few = new FileInfo(VectorOps.Trace(png, new Options { Colors = 3 })).Length;
        Assert.True(few < many, $"{few} should be under {many}");
    }
}
