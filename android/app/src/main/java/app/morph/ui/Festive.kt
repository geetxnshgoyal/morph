package app.morph.ui

import android.provider.Settings
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import kotlin.math.PI
import kotlin.math.sin

/**
 * Seasonal touches for the home screen's hero card. For Diwali the card turns saffron and
 * maroon, says Happy Diwali, and lights a diya with twinkling sparkles; the rest of the year it is Morph's own.
 */
object Festive {
    /** Diwali (Lakshmi Puja) for the next few years; add a line when these run out. */
    private val diwaliDays = listOf(LocalDate.of(2026, 11, 8), LocalDate.of(2027, 10, 29), LocalDate.of(2028, 10, 17),
        LocalDate.of(2029, 11, 5), LocalDate.of(2030, 10, 26))

    /** From three days before Diwali to a week after. */
    val isDiwali: Boolean get() = LocalDate.now().let { today -> diwaliDays.any { today in it.minusDays(3)..it.plusDays(7) } }

    /** Deep maroon into saffron, like a sky lit by diyas. */
    val diwaliBrush = Brush.linearGradient(listOf(Color(0xFF5B1236), Color(0xFFB4371F), Color(0xFFF08A1C)))
    val diwaliText = Color(0xFFFFF4E0)
    val diwaliButton = Color(0xFF8A1E2E)
}

/** Whether the system's animator scale is zero (Settings › Accessibility › Remove animations). */
@Composable
private fun animationsOff(): Boolean {
    val resolver = LocalContext.current.contentResolver
    return remember { Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
}

/** A clay diya with a flickering flame, and sparkles that twinkle around the card. Held still when animations are off. */
@Composable
fun BoxScope.DiwaliLights() {
    val still = animationsOff()
    val time = rememberInfiniteTransition(label = "diwali")
    val t by time.animateFloat(0f, 1f, infiniteRepeatable(tween(2400, easing = LinearEasing), RepeatMode.Restart), label = "t")
    val phase = if (still) 0.25f else t

    // Sparkles: position as a fraction of the card, size in dp, and a phase offset so they twinkle in turn.
    val sparkles = remember {
        // Kept to the right, around the diya, so they never sit on the greeting.
        listOf(Triple(0.70f, 0.07f, 0f), Triple(0.95f, 0.10f, 0.35f), Triple(0.96f, 0.42f, 0.6f),
            Triple(0.74f, 0.40f, 0.8f), Triple(0.88f, 0.56f, 0.15f), Triple(0.80f, 0.03f, 0.5f))
    }
    Canvas(Modifier.matchParentSize()) {
        for ((x, y, offset) in sparkles) {
            val glow = (sin(((phase + offset) % 1f) * 2 * PI).toFloat() + 1) / 2
            val r = 2.dp.toPx() + glow * 3.dp.toPx()
            val c = Offset(size.width * x, size.height * y)
            drawCircle(Color(0xFFFFE08A).copy(alpha = 0.25f * glow), r * 2.4f, c)
            drawCircle(Color(0xFFFFF1C4).copy(alpha = 0.6f + 0.4f * glow), r * 0.55f, c)
        }
    }

    Canvas(Modifier.align(androidx.compose.ui.Alignment.TopEnd).size(96.dp, 104.dp)) {
        val w = size.width; val h = size.height
        val flicker = if (still) 0f else sin(phase * 2 * PI * 3).toFloat()
        // Glow behind the flame.
        drawCircle(Brush.radialGradient(listOf(Color(0x88FFD36B), Color.Transparent), Offset(w * 0.5f, h * 0.42f), w * 0.5f),
            w * 0.5f, Offset(w * 0.5f, h * 0.42f))
        // Flame: a teardrop that sways a little.
        val tip = Offset(w * 0.5f + flicker * w * 0.03f, h * 0.14f - flicker * h * 0.015f)
        val flame = Path().apply {
            moveTo(tip.x, tip.y)
            cubicTo(w * 0.62f, h * 0.34f, w * 0.62f, h * 0.5f, w * 0.5f, h * 0.53f)
            cubicTo(w * 0.38f, h * 0.5f, w * 0.38f, h * 0.34f, tip.x, tip.y)
            close()
        }
        drawPath(flame, Brush.verticalGradient(listOf(Color(0xFFFFF6C8), Color(0xFFFFB627), Color(0xFFF0601A)), tip.y, h * 0.53f))
        // The clay lamp: a shallow bowl with a pointed spout on the right.
        val bowl = Path().apply {
            moveTo(w * 0.12f, h * 0.56f)
            lineTo(w * 0.9f, h * 0.56f)
            lineTo(w * 0.72f, h * 0.62f)
            cubicTo(w * 0.7f, h * 0.84f, w * 0.3f, h * 0.84f, w * 0.18f, h * 0.62f)
            close()
        }
        drawPath(bowl, Brush.verticalGradient(listOf(Color(0xFFE0753A), Color(0xFF8E2F14)), h * 0.56f, h * 0.8f))
        drawRect(Color(0xFFFFC35A).copy(alpha = 0.8f), Offset(w * 0.2f, h * 0.555f), Size(w * 0.6f, h * 0.02f))
    }
}
