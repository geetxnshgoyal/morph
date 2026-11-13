package app.morph

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.LaunchedEffect
import app.morph.ui.ActionsSheet
import app.morph.ui.MorphTheme

/**
 * Share or "Open with" from another app: only the actions sheet, floating over that app, so a photo shared from
 * the gallery is converted without leaving it. Closing the sheet returns to where the share started.
 */
class ShareActivity : ComponentActivity() {
    private val model: MorphModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) model.open(intent.sharedUris())
        setContent {
            MorphTheme(model.palette) { model.job?.let { ActionsSheet(it, model) } }
            // Nothing left to show: the sheet was closed, or the files couldn't be read.
            LaunchedEffect(model.job, model.importing) {
                if (model.job == null && !model.importing) {
                    model.error?.let { Toast.makeText(this@ShareActivity, it, Toast.LENGTH_LONG).show() }
                    finish()
                }
            }
        }
    }
}
