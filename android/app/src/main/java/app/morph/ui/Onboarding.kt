package app.morph.ui

import app.morph.MorphModel
import androidx.compose.material.icons.rounded.PhotoLibrary
import androidx.compose.material.icons.rounded.IosShare
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoFixHigh
import androidx.compose.material.icons.rounded.Compress
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

/**
 * First-launch guide: what Morph is, how to use it, where it works, the settings worth choosing up front, and the
 * privacy promise. Picking a colour recolours the guide as you tap.
 */
@Composable
fun Onboarding(model: MorphModel, onFinish: () -> Unit) {
    val pages = 5
    val pager = rememberPagerState { pages }
    val scope = rememberCoroutineScope()
    val last = pager.currentPage == pages - 1

    Column(Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding().navigationBarsPadding()) {
        HorizontalPager(pager, Modifier.weight(1f)) { page ->
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 26.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                when (page) {
                    0 -> Intro()
                    1 -> HowItWorks()
                    2 -> Everywhere()
                    3 -> MakeItYours(model)
                    else -> Privacy()
                }
            }
        }

        Column(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                repeat(pages) { i ->
                    val selected = i == pager.currentPage
                    Box(
                        Modifier.animateContentSize().height(8.dp).width(if (selected) 24.dp else 8.dp).clip(CircleShape)
                            .background(if (selected) colors.brand else colors.secondary.copy(alpha = 0.25f)),
                    )
                }
            }
            BubbleButton(if (last) "Get Started" else "Continue", Modifier.fillMaxWidth()) {
                if (last) onFinish() else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
            }
            Text("Skip", style = rounded(15, FontWeight.SemiBold), color = colors.secondary,
                modifier = Modifier.alpha(if (last) 0f else 1f).tap { if (!last) onFinish() }.padding(6.dp))
        }
    }
}

@Composable
private fun Intro() {
    Spacer(Modifier.height(48.dp))
    LogoMark()
    Spacer(Modifier.height(26.dp))
    Text("Welcome to Morph", style = rounded(32, FontWeight.ExtraBold), color = colors.text, textAlign = TextAlign.Center)
    Spacer(Modifier.height(8.dp))
    Text("Convert, shrink and tidy up any file, right on your phone.", style = rounded(17), color = colors.secondary,
        textAlign = TextAlign.Center)
    Spacer(Modifier.height(24.dp))
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Feature(Icons.Rounded.SwapHoriz, "Convert", "Images, video, audio and PDFs")
        Feature(Icons.Rounded.Compress, "Compress", "Make big files small enough to send")
        Feature(Icons.Rounded.AutoFixHigh, "Clean up", "Strip location data, read text from photos")
    }
}

@Composable
private fun HowItWorks() {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        Text("How it works", style = rounded(32, FontWeight.ExtraBold), color = colors.text, modifier = Modifier.padding(top = 60.dp))
        Step(1, "Pick some files", "Tap Photos or Files on the home screen, or share to Morph from any app.")
        Step(2, "Choose what to make", "Only actions that fit your files show up.")
        Step(3, "Share or save the result", "Results land in Downloads › Morph. Your originals never change.")
    }
}

@Composable
private fun Everywhere() {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Works with your apps", style = rounded(32, FontWeight.ExtraBold), color = colors.text,
            modifier = Modifier.padding(top = 60.dp, bottom = 8.dp))
        Feature(Icons.Rounded.IosShare, "Share to Morph", "In Photos, Files or any app, tap Share, then Morph.")
        Feature(Icons.Rounded.PhotoLibrary, "Pick photos privately", "Android's photo picker hands Morph only the photos you choose.")
        Feature(Icons.Rounded.Folder, "Results in Downloads", "Everything you make lands in Downloads › Morph, in any file manager.")
    }
}

@Composable
private fun MakeItYours(model: MorphModel) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.padding(top = 60.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Make it yours", style = rounded(32, FontWeight.ExtraBold), color = colors.text)
            Text("You can change all of this later in Settings.", style = rounded(15), color = colors.secondary)
        }
        MorphCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Color", style = rounded(17, FontWeight.Bold), color = colors.text, modifier = Modifier.weight(1f))
                Text(model.palette.label, style = rounded(15, FontWeight.Bold), color = colors.brandText)
            }
            Spacer(Modifier.height(12.dp))
            PalettePicker(model.palette, model::updatePalette)
        }
        MorphCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Size limit", style = rounded(17, FontWeight.Bold), color = colors.text, modifier = Modifier.weight(1f))
                SizeLimitPicker(model.sizeLimit, model::updateSizeLimit)
            }
            Spacer(Modifier.height(8.dp))
            Text("Upload forms often want photos under 200 KB or 100 KB. Set a limit and Compress makes a JPG that fits.",
                style = rounded(14), color = colors.secondary)
        }
        MorphCard {
            Text("Compression", style = rounded(17, FontWeight.Bold), color = colors.text)
            Spacer(Modifier.height(12.dp))
            PillPicker(app.morph.core.Compression.entries, model.compression, { it.label }, model::updateCompression)
            Spacer(Modifier.height(10.dp))
            Text(model.compression.detail, style = rounded(14), color = colors.secondary)
        }
    }
}

@Composable
private fun Privacy() {
    Spacer(Modifier.height(70.dp))
    Box(Modifier.size(150.dp).clip(CircleShape).background(colors.tint), contentAlignment = Alignment.Center) {
        Box(
            Modifier.size(96.dp).clip(CircleShape).background(colors.brand),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Rounded.Lock, null, tint = colors.onBrand, modifier = Modifier.size(42.dp)) }
    }
    Spacer(Modifier.height(26.dp))
    Text("Private by design", style = rounded(32, FontWeight.ExtraBold), color = colors.text)
    Spacer(Modifier.height(10.dp))
    Text("Everything happens on your device. No accounts, no uploads, no tracking.", style = rounded(17),
        color = colors.secondary, textAlign = TextAlign.Center)
}

@Composable
private fun Feature(icon: ImageVector, title: String, detail: String) {
    MorphCard(padding = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            SymbolBubble(icon, 48.dp)
            Column {
                Text(title, style = rounded(17, FontWeight.Bold), color = colors.text)
                Text(detail, style = rounded(14), color = colors.secondary)
            }
        }
    }
}

@Composable
private fun Step(n: Int, title: String, detail: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(Modifier.size(38.dp).clip(CircleShape).background(colors.brand), contentAlignment = Alignment.Center) {
            Text("$n", style = rounded(18, FontWeight.ExtraBold), color = colors.onBrand)
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = rounded(19, FontWeight.Bold), color = colors.text)
            Text(detail, style = rounded(15), color = colors.secondary)
        }
    }
}
