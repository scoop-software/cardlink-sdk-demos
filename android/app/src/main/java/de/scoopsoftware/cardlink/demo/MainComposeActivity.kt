package de.scoopsoftware.cardlink.demo

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import de.scoopsoftware.cardlink.demo.ui.CardlinkApp
import de.scoopsoftware.cardlink.demo.ui.model.ScanHistory
import de.scoopsoftware.cardlink.demo.ui.theme.BrandTheme
import de.scoopsoftware.cardlink.demo.ui.theme.CardlinkDemoTheme
import de.scoopsoftware.cardlink.demo.ui.theme.LocalBrandTheme
import de.scoopsoftware.cardlink.sms.SmsReceiver

/**
 * Main activity with Jetpack Compose UI featuring bottom navigation tabs.
 */
class MainComposeActivity : ComponentActivity() {

    private lateinit var scanHistory: ScanHistory

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        scanHistory = ScanHistory(this)

        // Restore saved theme
        val savedThemeName = getPreferences(MODE_PRIVATE).getString("brand_theme", null)
        val initialTheme = savedThemeName?.let {
            runCatching { BrandTheme.valueOf(it) }.getOrNull()
        } ?: BrandTheme.SYSTEM

        SmsReceiver.requestPermissionAndListen(this) { can ->
            runOnUiThread {
                Toast.makeText(this, "CAN received via SMS: $can", Toast.LENGTH_SHORT).show()
            }
        }

        setContent {
            val brandThemeState = remember { mutableStateOf(initialTheme) }

            CompositionLocalProvider(LocalBrandTheme provides brandThemeState) {
                CardlinkDemoTheme(brandTheme = brandThemeState.value) {
                    CardlinkApp(
                        scanHistory = scanHistory,
                        onThemeChanged = { theme ->
                            brandThemeState.value = theme
                            getPreferences(MODE_PRIVATE).edit()
                                .putString("brand_theme", theme.name)
                                .apply()
                        },
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        SmsReceiver.clearListener()
    }
}
