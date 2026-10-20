package app.morph.ui

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.morph.R
import kotlin.math.cos
import kotlin.math.sin

// Morph's look: one flat brand colour, Teal Ink, on cool neutrals; mirrors Theme.swift in the macOS and iOS apps.

/** Errors keep a plain red rather than borrowing the brand. */
val Danger = Color(0xFFD32F2F)

/** Teal Ink, Morph's own colour: the app icon keeps it whichever accent is chosen. */
val TealInk = Color(0xFF0B6E69)

/**
 * The accent colours people can choose in Settings; Teal Ink is the default. Each has a fill (a step lighter in
 * dark mode where needed), a text colour for light and dark surfaces, and the label colour on its fill, keeping
 * every pairing at WCAG AA or better.
 */
enum class Palette(
    val label: String, val fillLight: Long, val fillDark: Long, val textLight: Long, val textDark: Long, val onFill: Long,
) {
    TEAL("Teal Ink", 0xFF0B6E69, 0xFF157F79, 0xFF0B6E69, 0xFF4FC1B9, 0xFFFFFFFF),
    ULTRAMARINE("Ultramarine", 0xFF2F2EFF, 0xFF2F2EFF, 0xFF2F2EFF, 0xFFA6A8FF, 0xFFFFFFFF),
    GREEN("Green", 0xFF17804A, 0xFF17804A, 0xFF136B3E, 0xFF62C48E, 0xFFFFFFFF),
    MAGENTA("Magenta", 0xFFD6007A, 0xFFD6007A, 0xFFC2006E, 0xFFFF8CC6, 0xFFFFFFFF),
    YELLOW("Yellow", 0xFFFFD60A, 0xFFFFD60A, 0xFF735A00, 0xFFFFD60A, 0xFF121318),
}

data class MorphColors(
    val canvas: Color,
    val surface: Color,
    val text: Color,
    val secondary: Color,
    /** The chosen accent, for the one selected or primary thing on screen. */
    val brand: Color,
    /** The accent for text and icons, readable on this theme's surfaces. */
    val brandText: Color,
    /** Labels and icons drawn on a [brand] fill. */
    val onBrand: Color,
    /** The accent as text on white, for controls drawn on white in both themes. */
    val brandOnWhite: Color,
    val tint: Color,
    val dark: Boolean,
)

private fun morphColors(palette: Palette, dark: Boolean): MorphColors {
    val brand = Color(if (dark) palette.fillDark else palette.fillLight)
    return if (dark) {
        MorphColors(Color(0xFF0E1414), Color(0xFF172020), Color(0xFFEEF3F2), Color(0xFF9AA6A4), brand, Color(palette.textDark),
            Color(palette.onFill), Color(palette.textLight), brand.copy(alpha = 0.2f), dark = true)
    } else {
        MorphColors(Color(0xFFF1F4F3), Color.White, Color(0xFF121A19), Color(0xFF5C6664), brand, Color(palette.textLight),
            Color(palette.onFill), Color(palette.textLight), brand.copy(alpha = 0.12f), dark = false)
    }
}

val LocalMorphColors = staticCompositionLocalOf { morphColors(Palette.TEAL, dark = false) }
val colors: MorphColors @Composable get() = LocalMorphColors.current

@OptIn(ExperimentalTextApi::class)
val Nunito = FontFamily(
    listOf(400, 500, 600, 700, 800).map { w ->
        Font(R.font.nunito, FontWeight(w), variationSettings = FontVariation.Settings(FontVariation.weight(w)))
    },
)

fun rounded(size: Int, weight: FontWeight = FontWeight.Normal) = TextStyle(fontFamily = Nunito, fontSize = size.sp, fontWeight = weight)

@Composable
fun MorphTheme(palette: Palette = Palette.TEAL, content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    // Built once per palette and theme, so recomposing the app doesn't hand every screen a new set of colours.
    val c = remember(palette, dark) { morphColors(palette, dark) }
    val scheme = if (c.dark) {
        darkColorScheme(primary = c.brand, onPrimary = c.onBrand, background = c.canvas, surface = c.surface, onSurface = c.text,
            onBackground = c.text)
    } else {
        lightColorScheme(primary = c.brand, onPrimary = c.onBrand, background = c.canvas, surface = c.surface, onSurface = c.text,
            onBackground = c.text)
    }.copy(
        // Menus, dialogs and text fields use Morph's own surfaces instead of Material's default lilac tones.
        surfaceContainerLowest = c.surface, surfaceContainerLow = c.surface, surfaceContainer = c.surface,
        surfaceContainerHigh = c.surface, surfaceContainerHighest = c.surface, surfaceVariant = c.canvas,
        onSurfaceVariant = c.secondary, primaryContainer = c.tint, onPrimaryContainer = c.brandText,
        secondaryContainer = c.tint, onSecondaryContainer = c.brandText, outline = c.secondary.copy(alpha = 0.5f),
    )
    val base = Typography()
    val type = Typography(
        bodyLarge = base.bodyLarge.copy(fontFamily = Nunito),
        bodyMedium = base.bodyMedium.copy(fontFamily = Nunito),
        labelLarge = base.labelLarge.copy(fontFamily = Nunito),
        titleLarge = base.titleLarge.copy(fontFamily = Nunito),
    )
    CompositionLocalProvider(LocalMorphColors provides c) {
        MaterialTheme(colorScheme = scheme, typography = type, content = content)
    }
}

// MARK: - Components

/** Shrinks a little under the finger. */
@Composable
fun Modifier.squishy(interaction: MutableInteractionSource, pressed: Float = 0.96f): Modifier {
    val isPressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (isPressed) pressed else 1f, spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessMedium), label = "squish")
    return this.scale(scale)
}

@Composable
fun Modifier.tap(onClick: () -> Unit): Modifier {
    val interaction = remember { MutableInteractionSource() }
    return this.squishy(interaction).clickable(interaction, indication = null, onClick = onClick)
}

/** Filled teal pill for the main action on a screen. */
@Composable
fun BubbleButton(text: String, modifier: Modifier = Modifier, icon: ImageVector? = null, onClick: () -> Unit) {
    Row(
        modifier
            .tap(onClick)
            .clip(CircleShape)
            .background(colors.brand)
            .padding(horizontal = 26.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.let { Icon(it, null, tint = colors.onBrand, modifier = Modifier.size(20.dp)); Spacer(Modifier.width(8.dp)) }
        Text(text, style = rounded(17, FontWeight.Bold), color = colors.onBrand)
    }
}

/** Tinted pill for secondary actions. */
@Composable
fun SoftButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Text(
        text,
        style = rounded(15, FontWeight.Bold),
        color = colors.brandText,
        textAlign = TextAlign.Center,
        modifier = modifier.tap(onClick).clip(CircleShape).background(colors.tint).padding(horizontal = 16.dp, vertical = 10.dp),
    )
}

/** A soft rounded card on the canvas. */
@Composable
fun MorphCard(modifier: Modifier = Modifier, padding: Dp = 18.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .shadow(6.dp, RoundedCornerShape(26.dp), ambientColor = Color.Black.copy(alpha = 0.05f), spotColor = Color.Black.copy(alpha = 0.08f))
            .clip(RoundedCornerShape(26.dp))
            .background(colors.surface)
            .padding(padding),
        content = content,
    )
}

/** Round tinted badge holding a symbol. */
@Composable
fun SymbolBubble(icon: ImageVector, size: Dp = 44.dp) {
    Box(Modifier.size(size).clip(CircleShape).background(colors.tint), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = colors.brandText, modifier = Modifier.size(size * 0.48f))
    }
}

/** The app icon: Morph's seven drops in white on Teal Ink, whichever accent is chosen, like the icon itself. */
@Composable
fun LogoMark(size: Dp = 112.dp) {
    Box(
        Modifier
            .size(size)
            .shadow(12.dp, RoundedCornerShape(size * 0.27f), ambientColor = Color.Black.copy(alpha = 0.1f), spotColor = Color.Black.copy(alpha = 0.15f))
            .clip(RoundedCornerShape(size * 0.27f))
            .background(TealInk),
    ) {
        Canvas(Modifier.size(size)) {
            val c = Offset(this.size.width / 2, this.size.height / 2)
            // The same proportions as MorphMark in the Apple apps: one drop in the middle, six around it, point up.
            val ring = this.size.width * 0.192f
            val r = this.size.width * 0.0744f
            drawCircle(Color.White, r, c)
            for (i in 0 until 6) {
                val a = Math.toRadians(i * 60.0 - 90)
                drawCircle(Color.White, r, Offset(c.x + ring * cos(a).toFloat(), c.y + ring * sin(a).toFloat()))
            }
        }
    }
}

/** Bubbly segmented control: a teal pill slides to the selection. */
@Composable
fun <T> PillPicker(options: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit) {
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .shadow(4.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.05f))
            .clip(CircleShape)
            .background(colors.surface)
            .padding(5.dp),
    ) {
        val segment = maxWidth / options.size
        val offset by animateDpAsState(segment * options.indexOf(selected), spring(dampingRatio = 0.75f, stiffness = 500f), label = "pill")
        // Sized to the row of labels below, so it works inside scrolling columns too.
        Row(Modifier.matchParentSize()) {
            Spacer(Modifier.width(offset))
            Box(Modifier.width(segment).fillMaxHeight().clip(CircleShape).background(colors.brand))
        }
        Row(Modifier.fillMaxWidth()) {
            options.forEach { option ->
                Text(
                    label(option),
                    style = rounded(15, FontWeight.Bold),
                    color = if (option == selected) colors.onBrand else colors.secondary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .weight(1f)
                        .clip(CircleShape)
                        .clickable { onSelect(option) }
                        .padding(vertical = 11.dp),
                )
            }
        }
    }
}

/** One round swatch per palette; the chosen one wears a ring and a check. */
@Composable
fun PalettePicker(selected: Palette, onSelect: (Palette) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Palette.entries.forEach { palette ->
            val chosen = palette == selected
            Box(
                Modifier
                    .size(46.dp)
                    .border(2.dp, if (chosen) colors.brandText else Color.Transparent, CircleShape)
                    .padding(4.dp)
                    .clip(CircleShape)
                    .background(Color(if (colors.dark) palette.fillDark else palette.fillLight))
                    .clickable { onSelect(palette) }
                    .semantics { contentDescription = palette.label; this.selected = chosen },
                contentAlignment = Alignment.Center,
            ) {
                if (chosen) Icon(Icons.Rounded.Check, null, tint = Color(palette.onFill), modifier = Modifier.size(20.dp))
            }
        }
    }
}
