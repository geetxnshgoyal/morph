package app.morph.ui

import android.text.format.Formatter
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Audiotrack
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.InsertDriveFile
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.PictureAsPdf
import androidx.compose.material.icons.rounded.PriorityHigh
import androidx.compose.material.icons.rounded.QuestionMark
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.morph.Job
import app.morph.MorphModel
import app.morph.Phase
import app.morph.core.Action
import app.morph.core.FileKind
import app.morph.core.Group

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActionsSheet(job: Job, model: MorphModel) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = { job.phase !is Phase.Running })
    ModalBottomSheet(
        onDismissRequest = model::closeJob,
        sheetState = state,
        shape = RoundedCornerShape(topStart = 34.dp, topEnd = 34.dp),
        containerColor = colors.canvas,
        dragHandle = { BottomSheetDefaults.DragHandle(color = colors.secondary.copy(alpha = 0.4f)) },
    ) {
        AnimatedContent(
            job.phase,
            contentKey = { it::class },
            transitionSpec = { (fadeIn(tween(220)) + scaleIn(initialScale = 0.96f)) togetherWith fadeOut(tween(150)) },
            label = "phase",
        ) { phase ->
            Column(
                Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).navigationBarsPadding()
                    .padding(bottom = 24.dp),
            ) {
                when (phase) {
                    Phase.Choosing -> Choosing(job, model)
                    is Phase.Running -> Running(phase)
                    is Phase.Finished -> Finished(phase, model)
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Choosing(job: Job, model: MorphModel) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        SymbolBubble(kindIcon(job.kind), 52.dp)
        Column {
            Text(job.summary, style = rounded(18, FontWeight.Bold), color = colors.text, maxLines = 1, overflow = TextOverflow.MiddleEllipsis)
            Text("Pick what to make", style = rounded(14), color = colors.secondary)
        }
    }
    Spacer(Modifier.height(20.dp))
    if (job.actions.isEmpty()) {
        MorphCard {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SymbolBubble(Icons.Rounded.QuestionMark, 56.dp)
                Text("Nothing fits this file yet", style = rounded(17, FontWeight.Bold), color = colors.text)
                Text("Morph handles images, video, audio and PDFs.", style = rounded(14), color = colors.secondary, textAlign = TextAlign.Center)
            }
        }
        return
    }
    if (job.groups.size > 1) {
        PillPicker(job.groups, job.group, Group::label) { job.group = it }
        Spacer(Modifier.height(22.dp))
    }
    AnimatedContent(job.group, transitionSpec = { fadeIn(tween(200)) + scaleIn(initialScale = 0.95f) togetherWith fadeOut(tween(120)) },
        label = "group") { group ->
        FlowRow(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalArrangement = Arrangement.spacedBy(18.dp),
            maxItemsInEachRow = 3,
        ) {
            job.actions.filter { it.group == group }.forEach { action ->
                ActionBubble(action, Modifier.weight(1f)) { model.run(action) }
            }
            // Keep the last row's bubbles in their columns.
            repeat((3 - job.actions.count { it.group == group } % 3) % 3) { Spacer(Modifier.weight(1f)) }
        }
    }
}

@Composable
private fun ActionBubble(action: Action, modifier: Modifier, onClick: () -> Unit) {
    Column(modifier.tap(onClick), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(
            Modifier.size(68.dp).shadow(6.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.1f)).clip(CircleShape).background(colors.surface),
            contentAlignment = Alignment.Center,
        ) { Icon(iconFor(action.icon), null, tint = colors.brandText, modifier = Modifier.size(28.dp)) }
        Text(action.title, style = rounded(13, FontWeight.Bold), color = colors.text, textAlign = TextAlign.Center, maxLines = 2)
    }
}

@Composable
private fun Running(phase: Phase.Running) {
    val spin by rememberInfiniteTransition(label = "spin").animateFloat(
        0f, 360f, infiniteRepeatable(tween(1000, easing = LinearEasing), RepeatMode.Restart), label = "angle",
    )
    val fraction = if (phase.total > 1) (phase.done.toFloat() / phase.total).coerceAtLeast(0.08f) else 0.28f
    Column(Modifier.fillMaxWidth().padding(vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(22.dp)) {
        Box(Modifier.size(130.dp), contentAlignment = Alignment.Center) {
            val brand = colors.brand
            val tint = colors.tint
            Canvas(Modifier.size(130.dp).rotate(if (phase.total > 1) 0f else spin)) {
                val stroke = Stroke(12.dp.toPx(), cap = StrokeCap.Round)
                drawArc(tint, 0f, 360f, false, style = stroke)
                drawArc(brand, -90f, 360f * fraction, false, style = stroke)
            }
            Icon(iconFor(phase.action.icon), null, tint = colors.brandText, modifier = Modifier.size(38.dp))
        }
        Text(if (phase.action.group == Group.CONVERT) "Making ${phase.action.title}…" else "${phase.action.title}…",
            style = rounded(20, FontWeight.ExtraBold), color = colors.text)
        if (phase.total > 1) Text("${phase.done} of ${phase.total}", style = rounded(15), color = colors.secondary)
    }
}

@Composable
private fun Finished(phase: Phase.Finished, model: MorphModel) {
    val context = LocalContext.current
    val ok = phase.failures.isEmpty()
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val pop by animateFloatAsState(if (shown) 1f else 0.4f, spring(dampingRatio = 0.45f, stiffness = 300f), label = "pop")

    Column(Modifier.fillMaxWidth().padding(top = 18.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Box(
            Modifier.size(96.dp).scale(pop).clip(CircleShape).background(if (ok) colors.brand else Danger),
            contentAlignment = Alignment.Center,
        ) { Icon(if (ok) Icons.Rounded.Check else Icons.Rounded.PriorityHigh, null, tint = if (ok) colors.onBrand else Color.White, modifier = Modifier.size(46.dp)) }

        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(if (ok) "All done!" else if (phase.outputs.isEmpty()) "That didn't work" else "Partly done",
                style = rounded(24, FontWeight.ExtraBold), color = colors.text)
            Text(if (ok) "Saved to Downloads › Morph." else phase.failures.first(), style = rounded(15), color = colors.secondary,
                textAlign = TextAlign.Center)
        }

        phase.outputs.forEach { out ->
            MorphCard(Modifier.tap { view(context, out) }, padding = 12.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    SymbolBubble(Icons.Rounded.InsertDriveFile, 40.dp)
                    Column(Modifier.weight(1f)) {
                        Text(out.name, style = rounded(15, FontWeight.Bold), color = colors.text, maxLines = 1, overflow = TextOverflow.MiddleEllipsis)
                        Text(Formatter.formatShortFileSize(context, out.size), style = rounded(13), color = colors.secondary)
                    }
                    Icon(Icons.Rounded.Visibility, "Open", tint = colors.secondary)
                }
            }
        }

        if (phase.outputs.isNotEmpty()) {
            BubbleButton("Share", Modifier.fillMaxWidth(), icon = Icons.Rounded.Share) { share(context, phase.outputs) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (phase.outputs.isNotEmpty()) SoftButton("Open Downloads") { openDownloads(context) }
            SoftButton("Done") { model.closeJob() }
        }
    }
}

private fun kindIcon(kind: FileKind) = when (kind) {
    FileKind.IMAGE -> Icons.Rounded.Image
    FileKind.VIDEO -> Icons.Rounded.Movie
    FileKind.AUDIO -> Icons.Rounded.Audiotrack
    FileKind.PDF -> Icons.Rounded.PictureAsPdf
    FileKind.OTHER -> Icons.Rounded.Description
}
