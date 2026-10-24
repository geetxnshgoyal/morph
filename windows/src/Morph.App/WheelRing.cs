using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace Morph.App;

/// The ring of petals around the hub, drawn by hand so every petal can bloom out of the hub and lift when
/// highlighted. Hover, click and drop all find their petal by position, gaps included: the whole disc is
/// painted (almost invisibly) so a layered window still receives the pointer and drags over the gaps.
public sealed class WheelRing : FrameworkElement
{
    const double Side = WheelGeometry.Side;
    readonly WheelModel model;
    readonly Dictionary<string, double> lift = [];
    double bloom;
    double closing;
    bool animating;
    TimeSpan lastFrame;

    public WheelRing(WheelModel model)
    {
        this.model = model;
        Width = Height = Side;
        model.Changed += Animate;
        model.Turned += () => { bloom = Motion ? 0 : 1; Animate(); };
        bloom = Motion ? 0 : 1;
        Loaded += (_, _) => Animate();
        Unloaded += (_, _) => StopAnimating();
    }

    /// Windows' "Animation effects" setting.
    public static bool Motion => !Snapshots.Active && SystemParameters.ClientAreaAnimation;

    /// The petals shrink back into the hub as the wheel closes.
    public void Close()
    {
        closing = 1;
        Animate();
    }

    void Animate()
    {
        InvalidateVisual();
        if (animating || !Motion) return;
        animating = true;
        lastFrame = TimeSpan.Zero;
        CompositionTarget.Rendering += Frame;
    }

    void StopAnimating()
    {
        if (!animating) return;
        animating = false;
        CompositionTarget.Rendering -= Frame;
    }

    void Frame(object? sender, EventArgs e)
    {
        var now = ((RenderingEventArgs)e).RenderingTime;
        var dt = lastFrame == TimeSpan.Zero ? 1 / 60.0 : Math.Clamp((now - lastFrame).TotalSeconds, 0, 0.05);
        lastFrame = now;
        var settled = true;
        double Approach(double value, double target, double rate)
        {
            var next = target + (value - target) * Math.Exp(-dt * rate);
            if (Math.Abs(next - target) < 0.002) return target;
            settled = false;
            return next;
        }
        bloom = Approach(bloom, closing > 0 ? 0 : 1, closing > 0 ? 22 : 11);
        foreach (var action in model.PageItems)
            lift[action.Id] = Approach(lift.GetValueOrDefault(action.Id), action.Id == model.Hovered ? 1 : 0, 20);
        InvalidateVisual();
        if (settled) StopAnimating();
    }

    protected override void OnRender(DrawingContext dc)
    {
        const double c = Side / 2;
        // Catches the pointer and drags everywhere on the ring, gaps included.
        dc.DrawEllipse(new SolidColorBrush(Color.FromArgb(1, 0, 0, 0)), null, new Point(c, c),
            WheelGeometry.OuterRadius + WheelGeometry.Lift + 24, WheelGeometry.OuterRadius + WheelGeometry.Lift + 24);
        if (model.Phase != WheelPhase.Choosing) return;

        var glass = Theme.BrushOf("Glass");
        var brand = Theme.BrushOf("Brand");
        var onBrand = Theme.BrushOf("OnBrand");
        var primary = Theme.BrushOf("Primary");
        var rim = new Pen(Theme.BrushOf("GlassRim"), 1);
        var stroke = new Pen(Theme.BrushOf("Stroke"), 1);
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;

        var items = model.PageItems;
        // Before the drag reaches the wheel, empty petals hold the shape.
        var count = model.KnowsFiles ? items.Count : 8;
        if (count == 0) return;
        var b = Motion ? Ease(bloom) : 1;
        for (var i = 0; i < count; i++)
        {
            var action = model.KnowsFiles ? items[i] : null;
            var l = action is null ? 0 : Motion ? lift.GetValueOrDefault(action.Id) : action.Id == model.Hovered ? 1 : 0;
            var highlighted = action is not null && action.Id == model.Hovered;
            var angle = WheelGeometry.Angle(i, count);
            var inner = WheelGeometry.InnerRadius - 3 * l;
            var outer = WheelGeometry.InnerRadius + 6 + (WheelGeometry.OuterRadius - WheelGeometry.InnerRadius - 6) * b + WheelGeometry.Lift * l;
            var shape = Petal(new Point(c, c), angle, 360.0 / count, WheelGeometry.GapWidth, inner, outer);
            dc.PushOpacity(Math.Clamp(b * 1.4, 0, 1));
            dc.DrawGeometry(glass, stroke, shape);
            if (l > 0.01)
            {
                dc.PushOpacity(highlighted ? Math.Max(l, 0.6) : l);
                dc.DrawGeometry(brand, null, shape);
                dc.Pop();
            }
            else dc.DrawGeometry(null, rim, shape);

            if (action is not null)
            {
                var radians = angle * Math.PI / 180;
                var labelRadius = WheelGeometry.LabelRadius + (WheelGeometry.Lift / 2) * l;
                var center = new Point(c + Math.Cos(radians) * labelRadius, c + Math.Sin(radians) * labelRadius);
                var ink = highlighted ? onBrand : primary;
                var icon = Text(Icons.For(action.Symbol), "IconFont", highlighted ? 19 : 17, FontWeights.Normal, ink, dpi);
                var label = Text(action.Title, "UiFont", 11, FontWeights.SemiBold, ink, dpi);
                label.MaxTextWidth = LabelWidth(count);
                label.MaxLineCount = 2;
                label.TextAlignment = TextAlignment.Center;
                label.Trimming = TextTrimming.CharacterEllipsis;
                var height = icon.Height + 3 + label.Height;
                var top = center.Y - height / 2;
                dc.PushOpacity(b);
                dc.DrawText(icon, new Point(center.X - icon.Width / 2, top));
                dc.DrawText(label, new Point(center.X - label.MaxTextWidth / 2, top + icon.Height + 3));
                dc.Pop();
            }
            dc.Pop();
        }
    }

    static double Ease(double t) => 1 - Math.Pow(1 - t, 3);

    static FormattedText Text(string text, string fontKey, double size, FontWeight weight, Brush brush, double dpi) =>
        new(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface((FontFamily)Application.Current.Resources[fontKey], FontStyles.Normal, weight, FontStretches.Normal), size, brush, dpi);

    /// Wide enough to use the petal, narrow enough to stay inside it.
    static double LabelWidth(int count)
    {
        var chord = 2 * WheelGeometry.LabelRadius * Math.Sin(Math.PI / Math.Max(count, 2)) - WheelGeometry.GapWidth - 14;
        return Math.Min(92, Math.Max(54, chord));
    }

    /// An annular wedge whose sides run parallel to the boundary between petals, so the gap to each neighbour keeps
    /// the same width from hub to rim, with softly rounded corners. Angles are in degrees, clockwise from three
    /// o'clock (y points down).
    public static Geometry Petal(Point c, double centerAngle, double sectorAngle, double gap, double innerRadius, double outerRadius, double cornerRadius = 9)
    {
        if (outerRadius <= innerRadius || innerRadius <= 0) return Geometry.Empty;
        // A lone petal is the whole ring.
        if (sectorAngle >= 359.9)
            return new CombinedGeometry(GeometryCombineMode.Exclude, new EllipseGeometry(c, outerRadius, outerRadius), new EllipseGeometry(c, innerRadius, innerRadius));

        var mid = centerAngle * Math.PI / 180;
        // Half the petal's angle at radius r, after giving half the gap to each side.
        double Half(double r) => sectorAngle * Math.PI / 360 - Math.Asin(Math.Min(1, gap / 2 / r));
        double ho = Half(outerRadius), hi = Half(innerRadius);
        if (ho <= 0 || hi <= 0) return Geometry.Empty;

        Point At(double r, double a) => new(c.X + r * Math.Cos(a), c.Y + r * Math.Sin(a));
        // Direction of travel along a circle at angle a, toward larger angles.
        Vector Ahead(double a) => new(-Math.Sin(a), Math.Cos(a));

        var r = Math.Min(cornerRadius, (outerRadius - innerRadius) / 3);
        Point outerStart = At(outerRadius, mid - ho), outerEnd = At(outerRadius, mid + ho);
        Point innerEnd = At(innerRadius, mid + hi), innerStart = At(innerRadius, mid - hi);

        var geometry = new StreamGeometry();
        using (var g = geometry.Open())
        {
            var current = new Point((innerStart.X + outerStart.X) / 2, (innerStart.Y + outerStart.Y) / 2);
            g.BeginFigure(current, true, true);
            // Rounds the corner at `corner`, coming from the current point and leaving toward `next`.
            void Fillet(Point corner, Point next)
            {
                var into = corner - current;
                var outOf = next - corner;
                into.Normalize();
                outOf.Normalize();
                var turn = Vector.AngleBetween(into, outOf) * Math.PI / 180;
                var d = r * Math.Tan(Math.Abs(turn) / 2);
                var a = corner - into * d;
                var b = corner + outOf * d;
                g.LineTo(a, true, true);
                g.ArcTo(b, new Size(r, r), 0, false, turn > 0 ? SweepDirection.Clockwise : SweepDirection.Counterclockwise, true, true);
                current = b;
            }
            void Arc(double radius, double from, double to, SweepDirection direction)
            {
                g.LineTo(At(radius, from), true, true);
                current = At(radius, to);
                g.ArcTo(current, new Size(radius, radius), 0, Math.Abs(to - from) > Math.PI, direction, true, true);
            }
            Fillet(outerStart, outerStart + Ahead(mid - ho) * r * 2);
            Arc(outerRadius, mid - ho + r / outerRadius, mid + ho - r / outerRadius, SweepDirection.Clockwise);
            Fillet(outerEnd, innerEnd);
            Fillet(innerEnd, innerEnd - Ahead(mid + hi) * r * 2);
            Arc(innerRadius, mid + hi - r / innerRadius, mid - hi + r / innerRadius, SweepDirection.Counterclockwise);
            Fillet(innerStart, outerStart);
        }
        geometry.Freeze();
        return geometry;
    }
}
