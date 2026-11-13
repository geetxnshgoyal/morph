package app.morph

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.core.content.IntentCompat
import app.morph.ui.MorphApp
import app.morph.ui.MorphTheme

class MainActivity : ComponentActivity() {
    private val model: MorphModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) handle(intent)
        setContent { MorphTheme(model.palette) { MorphApp(model) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    /** Share sheet (one or many files) and "Open with Morph". */
    private fun handle(intent: Intent) {
        val uris = intent.sharedUris()
        // Debug builds only: `adb shell am start … --es run <action id>` runs an action straight away.
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        model.open(uris, autoRun = if (debuggable) intent.getStringExtra("run") else null)
    }
}

/** The files a share, a multi-share or an "Open with" intent carries. */
fun Intent.sharedUris(): List<Uri> = when (action) {
    Intent.ACTION_SEND -> listOfNotNull(IntentCompat.getParcelableExtra(this, Intent.EXTRA_STREAM, Uri::class.java))
    Intent.ACTION_SEND_MULTIPLE -> IntentCompat.getParcelableArrayListExtra(this, Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
    Intent.ACTION_VIEW -> listOfNotNull(data)
    else -> emptyList()
}
