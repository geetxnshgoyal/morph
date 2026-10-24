using System.IO;
using System.Media;

namespace Morph.App;

/// A soft tick each time the wheel's highlight moves, and Windows' own sounds when a job finishes. The tick is
/// synthesized at launch, so no sound files ship with the app; it's the same 60 ms detent click as the Mac's.
public sealed class Feedback
{
    public static readonly Feedback Shared = new();

    readonly SoundPlayer tick = new(MakeTick());
    DateTime lastTick = DateTime.MinValue;

    Feedback() => tick.Load();

    public void Tick()
    {
        if (!Preferences.Shared.PlaySounds) return;
        // Keep very fast sweeps crisp rather than buzzing.
        var now = DateTime.UtcNow;
        if ((now - lastTick).TotalMilliseconds < 25) return;
        lastTick = now;
        try { tick.Play(); } catch (InvalidOperationException) { }
    }

    public static void Done(bool failed)
    {
        if (!Preferences.Shared.PlaySounds) return;
        (failed ? SystemSounds.Hand : SystemSounds.Asterisk).Play();
    }

    /// A bright edge that is gone within a millisecond, a short knock under it and a soft low thump carrying the
    /// tail, as a 16-bit mono WAV.
    static MemoryStream MakeTick()
    {
        const int rate = 48_000;
        var frames = (int)(rate * 0.06);
        var samples = new double[frames];
        double Wave(double frequency, double t) => Math.Sin(2 * Math.PI * frequency * t);
        var peak = 0.0;
        for (var i = 0; i < frames; i++)
        {
            var t = (double)i / rate;
            var edge = (Wave(9_200, t) + 0.45 * Wave(14_800, t) + 0.35 * Wave(6_300, t)) * Math.Exp(-t / 0.000_45);
            var knock = 0.24 * Wave(1_100, t) * Math.Exp(-t / 0.000_8);
            var thump = 0.09 * Wave(230, t) * Math.Exp(-t / 0.005_2) * (1 - Math.Exp(-t / 0.000_6));
            samples[i] = (edge + knock) * Math.Min(1, t / 0.000_2) + thump;
            peak = Math.Max(peak, Math.Abs(samples[i]));
        }
        var stream = new MemoryStream();
        using (var w = new BinaryWriter(stream, System.Text.Encoding.ASCII, leaveOpen: true))
        {
            w.Write("RIFF"u8); w.Write(36 + frames * 2); w.Write("WAVE"u8);
            w.Write("fmt "u8); w.Write(16); w.Write((short)1); w.Write((short)1); w.Write(rate); w.Write(rate * 2); w.Write((short)2); w.Write((short)16);
            w.Write("data"u8); w.Write(frames * 2);
            // The Mac plays it at 0.4 of full scale through a mixer at 0.35.
            foreach (var s in samples) w.Write((short)(s / peak * 0.14 * short.MaxValue));
        }
        stream.Position = 0;
        return stream;
    }
}
