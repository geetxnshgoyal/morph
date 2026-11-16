using System.Runtime.CompilerServices;
using ImageMagick;
using ImageMagick.Configuration;

namespace Morph;

/// Turns off ImageMagick's script, network, PostScript and file-include coders before any image is opened.
/// MVG stays on because the SVG renderer draws through it; ImageOps.Read stops a file's bytes from choosing it.
/// INLINE stays on (SVGs embed data: images); whatever it decodes is checked against this policy again.
static class MagickPolicy
{
    const string Policy = """
        <policymap>
          <policy domain="coder" rights="none" pattern="{MSL,TEXT,LABEL,CAPTION,SHOW,WIN,PLT,X,EPHEMERAL,URL,HTTP,HTTPS,FTP,PS,PS2,PS3,EPS,EPI,EPSF,EPSI,EPT,PDF,XPS}" />
          <policy domain="path" rights="none" pattern="@*" />
        </policymap>
        """;

    [ModuleInitializer] // must run before any image is opened, whichever entry point (app, tests) loads the engine
    internal static void Apply()
    {
        var config = ConfigurationFiles.Default;
        config.Policy.Data = Policy;
        MagickNET.Initialize(config);
    }
}
