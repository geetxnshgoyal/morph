package app.morph.ui

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
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
import androidx.compose.ui.graphics.Brush
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

// Morph's soft, bubbly look; mirrors Theme.swift in the macOS and iOS apps.

val Tangerine = Color(0xFFFF8F38)
val Coral = Color(0xFFFF6661)
val Accent = Brush.linearGradient(listOf(Tangerine, Coral))
val Tint = Tangerine.copy(alpha = 0.14f)

data class MorphColors(val canvas: Color, val surface: Color, val text: Color, val secondary: Color, val dark: Boolean)

private val Light = MorphColors(Color(0xFFFFF7F0), Color.White, Color(0xFF231F1C), Color(0xFF8A817A), dark = false)
private val Dark = MorphColors(Color(0xFF1F1C1A), Color(0xFF2E2926), Color(0xFFF7F2EE), Color(0xFFA89F98), dark = true)

val LocalMorphColors = staticCompositionLocalOf { Light }
val colors: MorphColors @Composable get() = LocalMorphColors.current

@OptIn(ExperimentalTextApi::class)
val Nunito = FontFamily(
    listOf(400, 500, 600, 700, 800).map { w ->
        Font(R.font.nunito, FontWeight(w), variationSettings = FontVariation.Settings(FontVariation.weight(w)))
    },
)

fun rounded(size: Int, weight: FontWeight = FontWeight.Normal) = TextStyle(fontFamily = Nunito, fontSize = size.sp, fontWeight = weight)

@Composable
fun MorphTheme(content: @Composable () -> Unit) {
    val c = if (isSystemInDarkTheme()) Dark else Light
    val scheme = if (c.dark) {
        darkColorScheme(primary = Tangerine, background = c.canvas, surface = c.surface, onSurface = c.text, onBackground = c.text)
    } else {
        lightColorScheme(primary = Tangerine, background = c.canvas, surface = c.surface, onSurface = c.text, onBackground = c.text)
    }
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

/** Filled tangerine pill for the main action on a screen. */
@Composable
fun BubbleButton(text: String, modifier: Modifier = Modifier, icon: ImageVector? = null, onClick: () -> Unit) {
    Row(
        modifier
            .tap(onClick)
            .shadow(14.dp, CircleShape, ambientColor = Coral, spotColor = Coral)
            .clip(CircleShape)
            .background(Accent)
            .padding(horizontal = 26.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.let { Icon(it, null, tint = Color.White, modifier = Modifier.size(20.dp)); Spacer(Modifier.width(8.dp)) }
        Text(text, style = rounded(17, FontWeight.Bold), color = Color.White)
    }
}

/** Tinted pill for secondary actions. */
@Composable
fun SoftButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Text(
        text,
        style = rounded(15, FontWeight.Bold),
        color = Tangerine,
        textAlign = TextAlign.Center,
        modifier = modifier.tap(onClick).clip(CircleShape).background(Tint).padding(horizontal = 16.dp, vertical = 10.dp),
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
    Box(Modifier.size(size).clip(CircleShape).background(Tint), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = Tangerine, modifier = Modifier.size(size * 0.48f))
    }
}

/** The app icon: seven circles in a hexagon on the gradient. */
@Composable
fun LogoMark(size: Dp = 112.dp) {
    Box(
        Modifier
            .size(size)
            .shadow(20.dp, RoundedCornerShape(size * 0.27f), ambientColor = Coral, spotColor = Coral)
            .clip(RoundedCornerShape(size * 0.27f))
            .background(Accent),
    ) {
        Canvas(Modifier.size(size)) {
            val c = Offset(this.size.width / 2, this.size.height / 2)
            val ring = this.size.width * 0.155f
            val r = this.size.width * 0.07f
            drawCircle(Color.White, r, c)
            for (i in 0 until 6) {
                val a = Math.toRadians(i * 60.0)
                drawCircle(Color.White, r, Offset(c.x + ring * cos(a).toFloat(), c.y + ring * sin(a).toFloat()))
            }
        }
    }
}

/** Bubbly segmented control: a gradient pill slides to the selection. */
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
            Box(Modifier.width(segment).fillMaxHeight().clip(CircleShape).background(Accent))
        }
        Row(Modifier.fillMaxWidth()) {
            options.forEach { option ->
                Text(
                    label(option),
                    style = rounded(15, FontWeight.Bold),
                    color = if (option == selected) Color.White else colors.secondary,
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
