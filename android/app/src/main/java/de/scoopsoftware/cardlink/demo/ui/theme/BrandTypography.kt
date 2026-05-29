package de.scoopsoftware.cardlink.demo.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import de.scoopsoftware.cardlink.demo.R

/** SCOOP: Raleway — elegant, professional */
val ScoopFontFamily = FontFamily(
    Font(R.font.raleway_regular, FontWeight.Normal),
    Font(R.font.raleway_medium, FontWeight.Medium),
    Font(R.font.raleway_semibold, FontWeight.SemiBold),
    Font(R.font.raleway_bold, FontWeight.Bold),
)

/** DocMorris: Poppins — clean geometric */
val DocMorrisFontFamily = FontFamily(
    Font(R.font.poppins_regular, FontWeight.Normal),
    Font(R.font.poppins_medium, FontWeight.Medium),
    Font(R.font.poppins_semibold, FontWeight.SemiBold),
    Font(R.font.poppins_bold, FontWeight.Bold),
)

/** apo.com (formerly APONEO): Roboto Medium as base weight — extracted from the real app */
val ApoComFontFamily = FontFamily(
    Font(R.font.roboto_medium, FontWeight.Normal),
    Font(R.font.roboto_medium, FontWeight.Medium),
    Font(R.font.roboto_medium, FontWeight.SemiBold),
    Font(R.font.roboto_medium, FontWeight.Bold),
)

/** Redcare (formerly Shop Apotheke): Redcare Accessible — custom brand font */
val RedcareFontFamily = FontFamily(
    Font(R.font.redcare_accessible_regular, FontWeight.Normal),
    Font(R.font.redcare_accessible_medium, FontWeight.Medium),
    Font(R.font.redcare_accessible_medium, FontWeight.SemiBold),
    Font(R.font.redcare_accessible_bold, FontWeight.Bold),
)

/** mea: Open Sans — clean, friendly (as used in the actual mea app) */
val MeaFontFamily = FontFamily(
    Font(R.font.open_sans_regular, FontWeight.Normal),
    Font(R.font.open_sans_medium, FontWeight.Medium),
    Font(R.font.open_sans_semibold, FontWeight.SemiBold),
    Font(R.font.open_sans_bold, FontWeight.Bold),
)

fun brandTypography(fontFamily: FontFamily): Typography {
    val default = Typography()
    return Typography(
        displayLarge = default.displayLarge.copy(fontFamily = fontFamily),
        displayMedium = default.displayMedium.copy(fontFamily = fontFamily),
        displaySmall = default.displaySmall.copy(fontFamily = fontFamily),
        headlineLarge = default.headlineLarge.copy(fontFamily = fontFamily),
        headlineMedium = default.headlineMedium.copy(fontFamily = fontFamily),
        headlineSmall = default.headlineSmall.copy(fontFamily = fontFamily),
        titleLarge = default.titleLarge.copy(fontFamily = fontFamily),
        titleMedium = default.titleMedium.copy(fontFamily = fontFamily),
        titleSmall = default.titleSmall.copy(fontFamily = fontFamily),
        bodyLarge = default.bodyLarge.copy(fontFamily = fontFamily),
        bodyMedium = default.bodyMedium.copy(fontFamily = fontFamily),
        bodySmall = default.bodySmall.copy(fontFamily = fontFamily),
        labelLarge = default.labelLarge.copy(fontFamily = fontFamily),
        labelMedium = default.labelMedium.copy(fontFamily = fontFamily),
        labelSmall = default.labelSmall.copy(fontFamily = fontFamily),
    )
}
