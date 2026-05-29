package de.scoopsoftware.cardlink.demo.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import de.scoopsoftware.nfc.cache.KnownCard
import de.scoopsoftware.nfc.vsd.EgkCardView

/**
 * Renders a [KnownCard] as the SVG eGK card visual.
 *
 * Supports optional click and swipe-to-delete gestures.
 * Used across Scan, Upload, and Settings screens for consistent card rendering.
 *
 * @param card The known card data to display
 * @param onClick Optional click handler (e.g. to select the card)
 * @param onSwipeDismiss Optional swipe-to-delete handler. When null, swiping is disabled.
 * @param animateEnter Whether to animate the card entering (used for undo re-insertion)
 * @param onEnterAnimated Called when the enter animation completes
 */
@Composable
fun KnownCardItem(
    card: KnownCard,
    onClick: (() -> Unit)? = null,
    onSwipeDismiss: (() -> Unit)? = null,
    animateEnter: Boolean = false,
    onEnterAnimated: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val content = @Composable {
        AndroidView(
            factory = { ctx ->
                EgkCardView(ctx).apply {
                    setCardData(
                        fullName = card.displayName ?: "—",
                        insuranceId = card.insuranceId ?: "—",
                        insurerId = card.insurerId ?: "—",
                        insurerName = card.insurerName ?: "—",
                        can = card.can,
                    )
                    if (onClick != null) {
                        setOnClickListener { onClick() }
                    }
                }
            },
            modifier = Modifier
                .fillMaxWidth()
                .height(200.dp),
        )
    }

    if (onSwipeDismiss != null) {
        SwipeToDismissCard(
            key = card.iccsn,
            animateEnter = animateEnter,
            onEnterAnimated = onEnterAnimated,
            onDismiss = onSwipeDismiss,
            modifier = modifier.fillMaxWidth()
        ) {
            content()
        }
    } else {
        Box(modifier = modifier.fillMaxWidth()) {
            content()
        }
    }
}

/**
 * Swipe-to-dismiss wrapper that tilts left and fades as the user swipes.
 * On undo, the card flies in from the left (reverse of the dismiss animation).
 */
@Composable
fun SwipeToDismissCard(
    key: String,
    animateEnter: Boolean = false,
    onEnterAnimated: () -> Unit = {},
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val dismissThreshold = 300f
    var offsetX by remember(key) { mutableStateOf(0f) }
    var dismissed by remember(key) { mutableStateOf(false) }
    // Enter animation: only when undoing
    val enterOffset = remember(key) { Animatable(if (animateEnter) -600f else 0f) }
    LaunchedEffect(key, animateEnter) {
        if (animateEnter) {
            enterOffset.snapTo(-600f)
            enterOffset.animateTo(0f, spring(dampingRatio = 0.7f, stiffness = 300f))
            onEnterAnimated()
        }
    }
    val isEntering = enterOffset.value < -1f
    val animatedOffset by animateFloatAsState(
        targetValue = if (dismissed) -1000f else offsetX,
        animationSpec = if (dismissed) tween(300) else snap(),
        finishedListener = { if (dismissed) onDismiss() },
        label = "swipeOffset"
    )
    val effectiveOffset = if (isEntering) enterOffset.value else animatedOffset

    if (dismissed && effectiveOffset <= -999f) return

    val progress = ((-effectiveOffset) / dismissThreshold).coerceIn(0f, 1f)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .graphicsLayer {
                translationX = effectiveOffset
                rotationZ = -progress * 10f
                alpha = 1f - progress * 0.6f
                transformOrigin = TransformOrigin(0.5f, 1f)
            }
            .pointerInput(key) {
                detectHorizontalDragGestures(
                    onHorizontalDrag = { _, dragAmount ->
                        offsetX = (offsetX + dragAmount).coerceAtMost(0f)
                    },
                    onDragEnd = {
                        if (offsetX < -dismissThreshold) {
                            dismissed = true
                        } else {
                            offsetX = 0f
                        }
                    },
                    onDragCancel = { offsetX = 0f }
                )
            }
    ) {
        content()
    }
}

/**
 * Reusable list of known cards with consistent spacing and optional title.
 *
 * Used across Scan, PoPP CAN, Upload, and Settings screens.
 *
 * @param knownCards List of cards to display
 * @param title Optional section title (e.g. "Bekannte Karten")
 * @param onCardClick Called when a card is tapped
 * @param onSwipeDismiss Called when a card is swiped away. Null disables swiping.
 * @param undoneIccsns Set of ICCSNs that should animate re-entry (undo)
 * @param onUndoneAnimated Called when an undo animation finishes
 */
@Composable
fun KnownCardsList(
    knownCards: List<KnownCard>,
    title: String = "Bekannte Karten",
    onCardClick: ((KnownCard) -> Unit)? = null,
    onSwipeDismiss: ((KnownCard) -> Unit)? = null,
    undoneIccsns: Set<String> = emptySet(),
    onUndoneAnimated: (String) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    if (knownCards.isEmpty()) return

    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(title, style = MaterialTheme.typography.titleSmall, modifier = Modifier.fillMaxWidth())
        knownCards.forEach { card ->
            KnownCardItem(
                card = card,
                onClick = onCardClick?.let { { it(card) } },
                onSwipeDismiss = onSwipeDismiss?.let { { it(card) } },
                animateEnter = card.iccsn in undoneIccsns,
                onEnterAnimated = { onUndoneAnimated(card.iccsn) },
            )
        }
    }
}
