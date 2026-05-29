package de.scoopsoftware.cardlink.demo.ui.theme

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.graphics.Color

/**
 * Predefined brand themes matching real pharmacy apps.
 * Each theme provides light + dark color schemes and custom typography.
 */
enum class BrandTheme(
    val displayName: String,
    val previewColor: Color,
    val lightScheme: ColorScheme,
    val darkScheme: ColorScheme,
    val fontFamily: FontFamily? = null,
    val useDynamic: Boolean = false,
) {
    /** System default — uses Android 12+ dynamic colors or Material defaults. */
    SYSTEM(
        displayName = "System",
        previewColor = Color(0xFF6750A4),
        lightScheme = lightColorScheme(),
        darkScheme = darkColorScheme(),
        useDynamic = true,
    ),

    /** SCOOP Software — blue primary, gold accent. Colors from scoop-software.de */
    SCOOP(
        displayName = "SCOOP",
        fontFamily = ScoopFontFamily,
        previewColor = Color(0xFF005894),
        lightScheme = lightColorScheme(
            primary = Color(0xFF005894),
            onPrimary = Color.White,
            primaryContainer = Color(0xFFD4E8F7),
            onPrimaryContainer = Color(0xFF001D33),
            secondary = Color(0xFFF7A700),
            onSecondary = Color.White,
            secondaryContainer = Color(0xFFFFF0CC),
            onSecondaryContainer = Color(0xFF3D2E00),
            surface = Color(0xFFFAFAFA),
            onSurface = Color(0xFF292929),
            surfaceVariant = Color(0xFFF0F0F0),
            onSurfaceVariant = Color(0xFF44474E),
            error = Color(0xFFBA1A1A),
            outline = Color(0xFF79747E),
        ),
        darkScheme = darkColorScheme(
            primary = Color(0xFF85C5EE),
            onPrimary = Color(0xFF003354),
            primaryContainer = Color(0xFF005894),
            onPrimaryContainer = Color(0xFFD4E8F7),
            secondary = Color(0xFFF7A700),
            onSecondary = Color(0xFF3D2E00),
            secondaryContainer = Color(0xFF574200),
            onSecondaryContainer = Color(0xFFFFF0CC),
            surface = Color(0xFF1C244B),
            onSurface = Color(0xFFE2E2E9),
            surfaceVariant = Color(0xFF2A3260),
            onSurfaceVariant = Color(0xFFC3C6CF),
            error = Color(0xFFFFB4AB),
            outline = Color(0xFF8D9099),
        ),
    ),

    /** apo.com (formerly APONEO) — colors extracted from the real app. */
    APO_COM(
        displayName = "apo.com",
        previewColor = Color(0xFF1A73E8),
        fontFamily = ApoComFontFamily,
        lightScheme = lightColorScheme(
            primary = Color(0xFF1A73E8),          // primaryColor from APK
            onPrimary = Color.White,
            primaryContainer = Color(0xFFD4E3FF),
            onPrimaryContainer = Color(0xFF001A41),
            secondary = Color(0xFF565E71),
            onSecondary = Color.White,
            secondaryContainer = Color(0xFFDAE2F9),
            onSecondaryContainer = Color(0xFF131C2B),
            surface = Color.White,
            onSurface = Color(0xFF1A1C1E),        // ~87% black (textColor #DE000000)
            surfaceVariant = Color(0xFFF0F0F0),
            onSurfaceVariant = Color(0xFF44474E),
            error = Color(0xFFFF5722),            // error_color_material_light
            outline = Color(0xFF74777F),
        ),
        darkScheme = darkColorScheme(
            primary = Color(0xFFA8C8FF),
            onPrimary = Color(0xFF003063),
            primaryContainer = Color(0xFF1A73E8),
            onPrimaryContainer = Color(0xFFD4E3FF),
            secondary = Color(0xFFBEC6DC),
            onSecondary = Color(0xFF283141),
            secondaryContainer = Color(0xFF3E4759),
            onSecondaryContainer = Color(0xFFDAE2F9),
            surface = Color(0xFF1A1C1E),
            onSurface = Color(0xFFE3E2E6),
            surfaceVariant = Color(0xFF44474E),
            onSurfaceVariant = Color(0xFFC4C6D0),
            error = Color(0xFFFF7043),            // error_color_material_dark
            outline = Color(0xFF8E9099),
        ),
    ),

    /** DocMorris style — teal/green primary, clean white. */
    DOCMORRIS(
        displayName = "DocMorris",
        previewColor = Color(0xFF1A5950),
        fontFamily = DocMorrisFontFamily,
        lightScheme = lightColorScheme(
            primary = Color(0xFF1A5950),
            onPrimary = Color.White,
            primaryContainer = Color(0xFFD6F0EB),
            onPrimaryContainer = Color(0xFF00463D),
            secondary = Color(0xFF5F8B84),
            onSecondary = Color.White,
            secondaryContainer = Color(0xFFD6F0EB),
            onSecondaryContainer = Color(0xFF00463D),
            surface = Color(0xFFFAFAFA),
            onSurface = Color(0xFF1A1A1A),
            surfaceVariant = Color(0xFFF2F2F2),
            onSurfaceVariant = Color(0xFF4A4A4A),
            error = Color(0xFFC62850),
            outline = Color(0xFF79747E),
        ),
        darkScheme = darkColorScheme(
            primary = Color(0xFF8BD7C3),
            onPrimary = Color(0xFF00463D),
            primaryContainer = Color(0xFF1A5950),
            onPrimaryContainer = Color(0xFFD6F0EB),
            secondary = Color(0xFF8BD7C3),
            onSecondary = Color(0xFF00463D),
            secondaryContainer = Color(0xFF1A5950),
            onSecondaryContainer = Color(0xFFD6F0EB),
            surface = Color(0xFF1A1A1A),
            onSurface = Color(0xFFF2F2F2),
            surfaceVariant = Color(0xFF2A2A2A),
            onSurfaceVariant = Color(0xFFBFC9C4),
            error = Color(0xFFFFB3B3),
            outline = Color(0xFF4A4A4A),
        ),
    ),

    /** mea/Hubertus style — green/mint accent, dark mode. */
    MEA(
        displayName = "mea",
        fontFamily = MeaFontFamily,
        previewColor = Color(0xFF058550),
        lightScheme = lightColorScheme(
            primary = Color(0xFF058550),
            onPrimary = Color.White,
            primaryContainer = Color(0xFFCCE5DF),
            onPrimaryContainer = Color(0xFF034328),
            secondary = Color(0xFF69B595),
            onSecondary = Color.White,
            secondaryContainer = Color(0xFF9BCEB9),
            onSecondaryContainer = Color(0xFF19241F),
            surface = Color(0xFFF7F7F7),
            onSurface = Color(0xFF1E1E1E),
            surfaceVariant = Color(0xFFE6F2EF),
            onSurfaceVariant = Color(0xFF454545),
            error = Color(0xFFD0021B),
            outline = Color(0xFFADADAD),
        ),
        darkScheme = darkColorScheme(
            primary = Color(0xFF69B696),
            onPrimary = Color(0xFF034328),
            primaryContainer = Color(0xFF058550),
            onPrimaryContainer = Color(0xFFCCE5DF),
            secondary = Color(0xFF9BCEB9),
            onSecondary = Color(0xFF19241F),
            secondaryContainer = Color(0xFF2D4038),
            onSecondaryContainer = Color(0xFFCCE5DF),
            surface = Color(0xFF1E1E1E),
            onSurface = Color(0xFFF7F7F7),
            surfaceVariant = Color(0xFF2D4038),
            onSurfaceVariant = Color(0xFFB2B2B2),
            error = Color(0xFFE7A5AE),
            outline = Color(0xFF606060),
        ),
    ),

    /** Redcare (formerly Shop Apotheke) — colors extracted from the real app. */
    REDCARE(
        displayName = "Redcare",
        previewColor = Color(0xFFED0434),
        fontFamily = RedcareFontFamily,
        lightScheme = lightColorScheme(
            primary = Color(0xFFED0434),          // Content.Dark.Brand.Medium
            onPrimary = Color.White,
            primaryContainer = Color(0xFFFFEADE), // Background.Light.Brand.Medium
            onPrimaryContainer = Color(0xFF410012),
            secondary = Color(0xFF1B1C1B),        // Content.Dark.Primary.Max (used for text buttons)
            onSecondary = Color.White,
            secondaryContainer = Color(0xFFFDF1EE), // Background.Light.Brand.Low
            onSecondaryContainer = Color(0xFF1B1C1B),
            surface = Color(0xFFFBF9F8),          // Background.Light.Primary.Low
            onSurface = Color(0xFF1B1C1B),        // Content.Dark.Primary.Max
            surfaceVariant = Color(0xFFFDF1EE),   // Background.Light.Brand.Low
            onSurfaceVariant = Color(0xFF49454F),
            error = Color(0xFFBA1A1A),
            outline = Color(0xFFDBDAD9),          // Background.Light.Primary.High
        ),
        darkScheme = darkColorScheme(
            primary = Color(0xFFFFB3B3),
            onPrimary = Color(0xFF680020),
            primaryContainer = Color(0xFFED0434),
            onPrimaryContainer = Color(0xFFFFEADE),
            secondary = Color(0xFFFBF9F8),
            onSecondary = Color(0xFF1B1C1B),
            secondaryContainer = Color(0xFF3D2020),
            onSecondaryContainer = Color(0xFFFDF1EE),
            surface = Color(0xFF1B1C1B),
            onSurface = Color(0xFFFBF9F8),
            surfaceVariant = Color(0xFF2D2626),
            onSurfaceVariant = Color(0xFFDBDAD9),
            error = Color(0xFFFFB4AB),
            outline = Color(0xFF79747E),
        ),
    ),
    ;

    /** Typography derived from this theme's font family, or default if null. */
    val typography: Typography
        get() = fontFamily?.let { brandTypography(it) } ?: Typography()
}

/** CompositionLocal for the currently selected brand theme. */
val LocalBrandTheme = compositionLocalOf { mutableStateOf(BrandTheme.SYSTEM) }
