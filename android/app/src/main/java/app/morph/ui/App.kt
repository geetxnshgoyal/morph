package app.morph.ui

import androidx.compose.material.icons.automirrored.rounded.HelpOutline
import androidx.compose.material.icons.rounded.PrivacyTip
import android.net.Uri
import app.morph.core.PixelSize
import app.morph.core.SizeLimit
import androidx.compose.runtime.remember
import androidx.compose.material3.TextButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.AlertDialog
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.text.format.DateUtils
import android.view.HapticFeedbackConstants
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Collections
import androidx.compose.material.icons.rounded.Compress
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.DocumentScanner
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.FolderZip
import androidx.compose.material.icons.rounded.Gesture
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.IosShare
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PhotoLibrary
import androidx.compose.material.icons.rounded.PhotoSizeSelectLarge
import androidx.compose.material.icons.rounded.PictureAsPdf
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.Vibration
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material.icons.automirrored.rounded.VolumeOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.morph.MorphModel
import app.morph.core.HistoryEntry
import app.morph.core.Published

enum class Screen { HOME, SETTINGS }

@Composable
fun MorphApp(model: MorphModel) {
    var screen by rememberSaveable { mutableStateOf(Screen.HOME) }
    val view = LocalView.current

    // A gentle buzz when a job finishes.
    LaunchedEffect(model.lastRunSucceeded) {
        val ok = model.lastRunSucceeded ?: return@LaunchedEffect
        if (model.haptics) view.performHapticFeedback(if (ok) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.REJECT)
        model.lastRunSucceeded = null
    }

    Box(Modifier.fillMaxSize().background(colors.canvas)) {
        AnimatedContent(
            screen,
            transitionSpec = {
                val forward = targetState == Screen.SETTINGS
                (slideInHorizontally { if (forward) it else -it / 3 } + fadeIn()) togetherWith
                    (slideOutHorizontally { if (forward) -it / 3 else it } + fadeOut())
            },
            label = "screen",
        ) { s ->
            when (s) {
                Screen.HOME -> HomeScreen(model) { screen = Screen.SETTINGS }
                Screen.SETTINGS -> SettingsScreen(model) { screen = Screen.HOME }
            }
        }
        BackHandler(screen == Screen.SETTINGS) { screen = Screen.HOME }

        model.job?.let { ActionsSheet(it, model) }

        AnimatedVisibility(!model.hasSeenWelcome, enter = fadeIn(), exit = fadeOut() + slideOutVertically { it / 4 }) {
            Onboarding(model, onFinish = model::finishWelcome)
        }

        model.error?.let { message ->
            Toast(message) { model.error = null }
        }
    }
}

// MARK: - Home

@Composable
fun HomeScreen(model: MorphModel, openSettings: () -> Unit) {
    val context = LocalContext.current
    val photos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(50)) { model.open(it) }
    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { model.open(it) }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Morph", style = rounded(34, FontWeight.ExtraBold), color = colors.text, modifier = Modifier.weight(1f))
            Box(
                Modifier.size(46.dp).shadow(4.dp, CircleShape).clip(CircleShape).background(colors.surface).tap(openSettings),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Rounded.Settings, "Settings", tint = colors.secondary) }
        }

        // Hero
        Box(
            Modifier
                .fillMaxWidth()
                .shadow(12.dp, RoundedCornerShape(32.dp), ambientColor = Color.Black.copy(alpha = 0.1f), spotColor = Color.Black.copy(alpha = 0.15f))
                .clip(RoundedCornerShape(32.dp))
                .background(colors.brand),
        ) {
            Box(Modifier.size(160.dp).align(Alignment.TopEnd).offset(50.dp, (-50).dp).clip(CircleShape).background(Color.White.copy(alpha = 0.12f)))
            Box(Modifier.size(90.dp).align(Alignment.BottomEnd).offset((-30).dp, 30.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.10f)))
            Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("What are we\nmaking today?", style = rounded(28, FontWeight.ExtraBold), color = colors.onBrand)
                    Text("Convert, shrink and clean up any file.", style = rounded(15, FontWeight.SemiBold), color = colors.onBrand.copy(alpha = 0.85f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    HeroButton("Photos", Icons.Rounded.PhotoLibrary, Modifier.weight(1f)) {
                        // The system photo picker needs no permission and hands over only what's picked.
                        photos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo))
                    }
                    HeroButton("Files", Icons.Rounded.Folder, Modifier.weight(1f)) { files.launch(arrayOf("*/*")) }
                }
            }
        }

        if (model.importing) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                CircularProgressIndicator(Modifier.size(18.dp), color = colors.brand, strokeWidth = 2.5.dp)
                Text("Bringing your files in…", style = rounded(14), color = colors.secondary)
            }
        }

        Text("Recent", style = rounded(20, FontWeight.ExtraBold), color = colors.text, modifier = Modifier.padding(top = 6.dp))
        if (model.recent.isEmpty()) {
            MorphCard {
                Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    SymbolBubble(Icons.Rounded.AutoAwesome, 56.dp)
                    Text("Nothing yet", style = rounded(17, FontWeight.Bold), color = colors.text)
                    Text("Files you convert show up here, and in Downloads › Morph.", style = rounded(14), color = colors.secondary,
                        textAlign = TextAlign.Center)
                }
            }
        } else {
            model.recent.forEach { entry -> RecentRow(entry, model) }
        }
        Spacer(Modifier.height(24.dp))
    }

}

@Composable
private fun HeroButton(title: String, icon: ImageVector, modifier: Modifier, onClick: () -> Unit) {
    Row(
        modifier.tap(onClick).clip(CircleShape).background(Color.White).padding(vertical = 15.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = colors.brandOnWhite, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(title, style = rounded(16, FontWeight.Bold), color = colors.brandOnWhite)
    }
}

@Composable
private fun RecentRow(entry: HistoryEntry, model: MorphModel) {
    val context = LocalContext.current
    val usable = !entry.deleted && entry.outputs.isNotEmpty()
    MorphCard(Modifier.tap { if (usable) view(context, entry.outputs.first()) }, padding = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            SymbolBubble(if (entry.deleted) Icons.Rounded.DeleteOutline else if (entry.outputs.isEmpty()) Icons.Rounded.Close else Icons.Rounded.Check)
            Column(Modifier.weight(1f)) {
                Text(entry.title, style = rounded(16, FontWeight.Bold), color = colors.text,
                    textDecoration = if (entry.deleted) TextDecoration.LineThrough else null)
                val n = entry.outputs.size
                Text("${DateUtils.getRelativeTimeSpanString(entry.date)} · $n file${if (n == 1) "" else "s"}",
                    style = rounded(13), color = colors.secondary)
            }
            if (usable) {
                RoundIcon(Icons.Rounded.Share, "Share") { share(context, entry.outputs) }
                RoundIcon(Icons.Rounded.DeleteOutline, "Delete results") { model.deleteResults(entry) }
            }
        }
    }
}

@Composable
fun RoundIcon(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(38.dp).clip(CircleShape).background(colors.tint).tap(onClick), contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = colors.brandText, modifier = Modifier.size(18.dp))
    }
}

// MARK: - Settings

@Composable
fun SettingsScreen(model: MorphModel, back: () -> Unit) {
    val context = LocalContext.current
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(Modifier.padding(top = 12.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(46.dp).shadow(4.dp, CircleShape).clip(CircleShape).background(colors.surface).tap(back),
                contentAlignment = Alignment.Center) {
                Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back", tint = colors.secondary)
            }
            Spacer(Modifier.width(14.dp))
            Text("Settings", style = rounded(28, FontWeight.ExtraBold), color = colors.text)
        }

        MorphCard {
            Text("Compression", style = rounded(17, FontWeight.Bold), color = colors.text)
            Spacer(Modifier.height(12.dp))
            PillPicker(app.morph.core.Compression.entries, model.compression, { it.label }, model::updateCompression)
            Spacer(Modifier.height(10.dp))
            Text(model.compression.detail, style = rounded(14), color = colors.secondary)
            Spacer(Modifier.height(16.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Size limit", style = rounded(17, FontWeight.Bold), color = colors.text, modifier = Modifier.weight(1f))
                SizeLimitPicker(model.sizeLimit, model::updateSizeLimit)
            }
            Spacer(Modifier.height(8.dp))
            Text(SizeLimit.detail(model.sizeLimit), style = rounded(14), color = colors.secondary)
            Spacer(Modifier.height(16.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Photo size", style = rounded(17, FontWeight.Bold), color = colors.text, modifier = Modifier.weight(1f))
                PhotoSizePicker(model.photoSize, model::updatePhotoSize)
            }
            Spacer(Modifier.height(8.dp))
            Text(
                model.photoSize?.let { "Resize makes photos exactly ${it.label} as a JPG, cropped to fill, and under your size limit if one is set. For passport, visa and exam forms." }
                    ?: "Pick the exact size a form asks for, like 600 × 600, and Resize makes it.",
                style = rounded(14), color = colors.secondary,
            )
            if (model.photoSize != null) {
                Spacer(Modifier.height(10.dp))
                OutlinedTextField(model.photoCaption, model::updatePhotoCaption, singleLine = true,
                    placeholder = { Text("Name to print below the photo (optional)") }, modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(6.dp))
                Text("Some exam forms want the name and the date the photo was taken under it.", style = rounded(13), color = colors.secondary)
            }
        }

        MorphCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Color", style = rounded(17, FontWeight.Bold), color = colors.text, modifier = Modifier.weight(1f))
                Text(model.palette.label, style = rounded(15, FontWeight.Bold), color = colors.brandText)
            }
            Spacer(Modifier.height(12.dp))
            PalettePicker(model.palette, model::updatePalette)
            Spacer(Modifier.height(10.dp))
            Text("For highlights and buttons. The app icon stays Teal Ink.", style = rounded(14), color = colors.secondary)
        }

        SettingRow(Icons.Rounded.Vibration, "Haptics", "A gentle buzz when a job finishes.") {
            Switch(model.haptics, model::updateHaptics, colors = SwitchDefaults.colors(checkedTrackColor = colors.brand))
        }
        SettingRow(Icons.Rounded.Folder, "Your results", "Saved in Downloads › Morph, visible in any file manager.") {
            SoftButton("Open") { openDownloads(context) }
        }
        SettingRow(Icons.Rounded.IosShare, "Share to Morph", "In any app, tap Share, then Morph.") {}
        SettingRow(Icons.Rounded.AutoAwesome, "Welcome guide", "See the introduction again.") {
            SoftButton("Show") { back(); model.replayWelcome() }
        }
        SettingRow(Icons.Rounded.PrivacyTip, "Privacy", "Morph collects nothing. Your files never leave this phone.") {
            SoftButton("Read") { openLink(context, "https://morph.geetanshgoyal.in/privacy.html") }
        }
        SettingRow(Icons.AutoMirrored.Rounded.HelpOutline, "Help and feedback", "Questions, ideas or a file that didn't convert.") {
            SoftButton("Open") { openLink(context, "https://morph.geetanshgoyal.in/support.html") }
        }

        val version = runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull().orEmpty()
        Text("Morph $version · Everything stays on your device", style = rounded(12), color = colors.secondary.copy(alpha = 0.7f),
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp))
    }
}

@Composable
private fun SettingRow(icon: ImageVector, title: String, detail: String, trailing: @Composable () -> Unit) {
    MorphCard(padding = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            SymbolBubble(icon)
            Column(Modifier.weight(1f)) {
                Text(title, style = rounded(16, FontWeight.Bold), color = colors.text)
                Text(detail, style = rounded(13), color = colors.secondary)
            }
            trailing()
        }
    }
}

@Composable
private fun Toast(message: String, dismiss: () -> Unit) {
    LaunchedEffect(message) { kotlinx.coroutines.delay(3500); dismiss() }
    Box(Modifier.fillMaxSize().navigationBarsPadding().padding(20.dp), contentAlignment = Alignment.BottomCenter) {
        AnimatedVisibility(true, enter = slideInVertically { it } + fadeIn()) {
            Text(message, style = rounded(15, FontWeight.SemiBold), color = Color.White,
                modifier = Modifier.clip(CircleShape).background(Danger).padding(horizontal = 20.dp, vertical = 12.dp))
        }
    }
}

// MARK: - Helpers

fun iconFor(key: String): ImageVector = when (key) {
    "photo" -> Icons.Rounded.Image
    "vector" -> Icons.Rounded.Gesture
    "pdf" -> Icons.Rounded.PictureAsPdf
    "pages" -> Icons.Rounded.Collections
    "video" -> Icons.Rounded.Movie
    "audio" -> Icons.Rounded.MusicNote
    "compress" -> Icons.Rounded.Compress
    "resize" -> Icons.Rounded.PhotoSizeSelectLarge
    "strip" -> Icons.Rounded.VisibilityOff
    "text" -> Icons.Rounded.DocumentScanner
    "zip" -> Icons.Rounded.FolderZip
    "mute" -> Icons.AutoMirrored.Rounded.VolumeOff
    "recipe" -> Icons.Rounded.AutoAwesome
    else -> Icons.Rounded.Description
}

fun share(context: Context, outputs: List<Published>) {
    val intent = if (outputs.size == 1) {
        Intent(Intent.ACTION_SEND).setType(outputs[0].mime).putExtra(Intent.EXTRA_STREAM, outputs[0].uri)
    } else {
        Intent(Intent.ACTION_SEND_MULTIPLE).setType("*/*").putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(outputs.map { it.uri }))
    }
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    val chooser = Intent.createChooser(intent, null).apply {
        if (context !is android.app.Activity) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    context.startActivity(chooser)
}

fun view(context: Context, output: Published) {
    val intent = Intent(Intent.ACTION_VIEW).setDataAndType(output.uri, output.mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    if (context !is android.app.Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(intent) }.onFailure { share(context, listOf(output)) }
}

fun openDownloads(context: Context) {
    val opened = runCatching {
        context.startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }.isSuccess
    if (!opened) {
        runCatching {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(Uri.parse("content://com.android.externalstorage.documents/document/primary%3ADownload%2FMorph"), "resource/folder")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }
    }
}

/** Compress's size limit: none, a common upload-form size, or any size typed in ("300 KB", "1.5 MB"). */
@Composable
internal fun SizeLimitPicker(limit: Int, onChange: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    var typing by remember { mutableStateOf(false) }
    Box {
        SoftButton(SizeLimit.label(limit) + "  ▾") { open = true }
        DropdownMenu(open, onDismissRequest = { open = false }) {
            (listOf(0) + SizeLimit.presets).forEach { bytes ->
                DropdownMenuItem(
                    text = { Text(SizeLimit.label(bytes), style = rounded(15, if (bytes == limit) FontWeight.Bold else FontWeight.Medium)) },
                    trailingIcon = { if (bytes == limit) Icon(Icons.Rounded.Check, null, tint = colors.brandText) },
                    onClick = { onChange(bytes); open = false },
                )
            }
            DropdownMenuItem(text = { Text("Custom size…", style = rounded(15, FontWeight.Medium)) }, onClick = { open = false; typing = true })
        }
    }
    if (typing) {
        var text by remember { mutableStateOf(if (limit > 0) SizeLimit.label(limit) else "") }
        AlertDialog(
            onDismissRequest = { typing = false },
            title = { Text("Custom size limit", style = rounded(20, FontWeight.Bold)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Type a size such as 300 KB or 1.5 MB.", style = rounded(15))
                    OutlinedTextField(text, { text = it }, singleLine = true, placeholder = { Text("200 KB") })
                }
            },
            confirmButton = {
                TextButton({ SizeLimit.parse(text)?.takeIf { it >= 5_000 }?.let(onChange); typing = false }) { Text("Set") }
            },
            dismissButton = { TextButton({ typing = false }) { Text("Cancel") } },
        )
    }
}

/** Resize's exact size: off, a preset (passport, exams, signature, social), or any width × height typed in. */
@Composable
internal fun PhotoSizePicker(size: PixelSize?, onChange: (PixelSize?) -> Unit) {
    var open by remember { mutableStateOf(false) }
    var typing by remember { mutableStateOf(false) }
    Box {
        SoftButton((size?.label ?: "Off") + "  ▾") { open = true }
        DropdownMenu(open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text("Off", style = rounded(15, if (size == null) FontWeight.Bold else FontWeight.Medium)) },
                trailingIcon = { if (size == null) Icon(Icons.Rounded.Check, null, tint = colors.brandText) },
                onClick = { onChange(null); open = false })
            PixelSize.presets.forEach { (group, items) ->
                Text(group, style = rounded(12, FontWeight.Bold), color = colors.secondary, modifier = Modifier.padding(start = 12.dp, top = 10.dp, bottom = 2.dp))
                items.forEach { (name, preset) ->
                    DropdownMenuItem(
                        text = { Text("$name · ${preset.label}", style = rounded(15, if (preset == size) FontWeight.Bold else FontWeight.Medium)) },
                        trailingIcon = { if (preset == size) Icon(Icons.Rounded.Check, null, tint = colors.brandText) },
                        onClick = { onChange(preset); open = false },
                    )
                }
            }
            DropdownMenuItem(text = { Text("Custom size…", style = rounded(15, FontWeight.Medium)) }, onClick = { open = false; typing = true })
        }
    }
    if (typing) {
        var text by remember { mutableStateOf(size?.let { "${it.width} x ${it.height}" } ?: "") }
        AlertDialog(
            onDismissRequest = { typing = false },
            title = { Text("Custom photo size", style = rounded(20, FontWeight.Bold)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Width × height in pixels, as the form asks for it.", style = rounded(15))
                    OutlinedTextField(text, { text = it }, singleLine = true, placeholder = { Text("600 x 600") })
                }
            },
            confirmButton = { TextButton({ PixelSize.parse(text)?.let(onChange); typing = false }) { Text("Set") } },
            dismissButton = { TextButton({ typing = false }) { Text("Cancel") } },
        )
    }
}

/** Opens a web page in the browser. Morph itself never goes online; the browser does. */
private fun openLink(context: Context, url: String) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}
