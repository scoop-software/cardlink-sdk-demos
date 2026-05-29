package de.scoopsoftware.cardlink.demo.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

// iOS-style colors for charts
object ChartColors {
    val Blue = Color(0xFF007AFF)
    val Green = Color(0xFF34C759)
    val Orange = Color(0xFFFF9500)
    val Gray = Color(0xFF8E8E93)
    val Purple = Color(0xFFAF52DE)
    val Cyan = Color(0xFF32ADE6)
    val Red = Color(0xFFFF3B30)
    val Indigo = Color(0xFF5856D6)
}

@Composable
fun CardlinkDemoTheme(
    brandTheme: BrandTheme = BrandTheme.SYSTEM,
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        brandTheme.useDynamic && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> brandTheme.darkScheme
        else -> brandTheme.lightScheme
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = colorScheme.primary.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = brandTheme.typography,
        content = content
    )
}
