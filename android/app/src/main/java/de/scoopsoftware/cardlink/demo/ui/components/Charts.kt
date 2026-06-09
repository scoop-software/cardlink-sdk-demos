package de.scoopsoftware.cardlink.demo.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.patrykandpatrick.vico.compose.axis.horizontal.rememberBottomAxis
import com.patrykandpatrick.vico.compose.axis.vertical.rememberStartAxis
import com.patrykandpatrick.vico.compose.chart.Chart
import com.patrykandpatrick.vico.compose.chart.column.columnChart
import com.patrykandpatrick.vico.compose.chart.line.lineChart
import com.patrykandpatrick.vico.compose.component.shape.shader.fromComponent
import com.patrykandpatrick.vico.compose.component.shapeComponent
import com.patrykandpatrick.vico.compose.component.textComponent
import com.patrykandpatrick.vico.compose.dimensions.dimensionsOf
import com.patrykandpatrick.vico.compose.style.ProvideChartStyle
import com.patrykandpatrick.vico.core.axis.AxisItemPlacer
import com.patrykandpatrick.vico.core.axis.formatter.AxisValueFormatter
import com.patrykandpatrick.vico.core.chart.column.ColumnChart
import com.patrykandpatrick.vico.core.chart.line.LineChart
import com.patrykandpatrick.vico.core.component.shape.DashedShape
import com.patrykandpatrick.vico.core.component.shape.LineComponent
import com.patrykandpatrick.vico.core.component.shape.Shapes
import com.patrykandpatrick.vico.core.component.shape.shader.DynamicShaders
import com.patrykandpatrick.vico.core.entry.ChartEntryModelProducer
import com.patrykandpatrick.vico.core.entry.FloatEntry
import com.patrykandpatrick.vico.core.entry.composed.ComposedChartEntryModelProducer
import com.patrykandpatrick.vico.core.entry.entryOf
import de.scoopsoftware.cardlink.metrics.ScanRecord
import de.scoopsoftware.cardlink.demo.ui.theme.ChartColors

/**
 * Line chart showing scan time history using Vico.
 */
@Composable
fun ScanTimeChart(
    records: List<ScanRecord>,
    modifier: Modifier = Modifier
) {
    if (records.isEmpty()) return

    val entries = remember(records) {
        records.mapIndexed { index, record ->
            entryOf(index.toFloat(), record.totalTimeMs.toFloat())
        }
    }

    val chartEntryModelProducer = remember(entries) {
        ChartEntryModelProducer(entries)
    }

    val axisValueFormatter = AxisValueFormatter<com.patrykandpatrick.vico.core.axis.AxisPosition.Vertical.Start> { value, _ ->
        formatMs(value.toLong())
    }

    ProvideChartStyle(chartStyle = rememberChartStyle(listOf(ChartColors.Blue))) {
        Chart(
            chart = lineChart(
                lines = listOf(
                    LineChart.LineSpec(
                        lineColor = ChartColors.Blue.hashCode(),
                        lineBackgroundShader = DynamicShaders.fromComponent(
                            componentSize = 4.dp,
                            component = shapeComponent(
                                shape = Shapes.rectShape,
                                color = ChartColors.Blue.copy(alpha = 0.2f)
                            )
                        )
                    )
                )
            ),
            chartModelProducer = chartEntryModelProducer,
            startAxis = rememberStartAxis(
                valueFormatter = axisValueFormatter,
                itemPlacer = AxisItemPlacer.Vertical.default(maxItemCount = 5)
            ),
            bottomAxis = rememberBottomAxis(
                guideline = null,
                itemPlacer = AxisItemPlacer.Horizontal.default(spacing = 1)
            ),
            modifier = modifier
                .fillMaxWidth()
                .height(200.dp)
        )
    }
}

/**
 * Stacked bar chart showing time breakdown using Vico.
 */
@Composable
fun BreakdownChart(
    records: List<ScanRecord>,
    modifier: Modifier = Modifier
) {
    if (records.isEmpty()) return

    // Split NFC into PACE, PoPP APDU, and other NFC based on APDU labels
    val hasPoPP = remember(records) {
        records.any { record -> record.apduExchanges.any { it.label.startsWith("PoPP:") } }
    }

    data class Breakdown(val pace: Float, val popp: Float, val otherNfc: Float, val network: Float, val crypto: Float, val gzip: Float, val other: Float)

    val breakdowns = remember(records) {
        records.map { record ->
            val exchanges = record.apduExchanges
            var pace = 0L; var popp = 0L; var network = 0L; var otherNfc = 0L
            for (ex in exchanges) {
                when {
                    ex.label.startsWith("Network:") -> network += ex.durationMs
                    ex.label.contains("MSE:SET AT") || ex.label.contains("GENERAL AUTHENTICATE") || ex.label.contains("CardAccess") -> pace += ex.durationMs
                    ex.label.startsWith("PoPP:") -> popp += ex.durationMs
                    else -> otherNfc += ex.durationMs
                }
            }
            if (exchanges.isEmpty()) otherNfc = record.nfcTimeMs
            val adjustedOther = maxOf(0L, record.otherTimeMs - network)
            Breakdown(pace.toFloat(), popp.toFloat(), otherNfc.toFloat(), network.toFloat(),
                record.cryptoTimeMs.toFloat(), record.gzipTimeMs.toFloat(), adjustedOther.toFloat())
        }
    }

    val chartEntryModelProducer = remember(breakdowns) {
        if (hasPoPP) {
            ComposedChartEntryModelProducer.build {
                add(breakdowns.mapIndexed { i, b -> entryOf(i.toFloat(), b.pace) })
                add(breakdowns.mapIndexed { i, b -> entryOf(i.toFloat(), b.popp) })
                add(breakdowns.mapIndexed { i, b -> entryOf(i.toFloat(), b.otherNfc) })
                add(breakdowns.mapIndexed { i, b -> entryOf(i.toFloat(), b.network) })
                add(breakdowns.mapIndexed { i, b -> entryOf(i.toFloat(), b.crypto) })
                add(breakdowns.mapIndexed { i, b -> entryOf(i.toFloat(), b.gzip) })
                add(breakdowns.mapIndexed { i, b -> entryOf(i.toFloat(), b.other) })
            }
        } else {
            ComposedChartEntryModelProducer.build {
                add(records.mapIndexed { i, r -> entryOf(i.toFloat(), r.nfcTimeMs.toFloat()) })
                add(records.mapIndexed { i, r -> entryOf(i.toFloat(), r.cryptoTimeMs.toFloat()) })
                add(records.mapIndexed { i, r -> entryOf(i.toFloat(), r.gzipTimeMs.toFloat()) })
                add(records.mapIndexed { i, r -> entryOf(i.toFloat(), r.otherTimeMs.toFloat()) })
            }
        }
    }

    val axisValueFormatter = AxisValueFormatter<com.patrykandpatrick.vico.core.axis.AxisPosition.Vertical.Start> { value, _ ->
        formatMs(value.toLong())
    }

    val colors = if (hasPoPP) {
        listOf(ChartColors.Indigo, ChartColors.Blue, ChartColors.Cyan, ChartColors.Purple, ChartColors.Green, ChartColors.Orange, ChartColors.Gray)
    } else {
        listOf(ChartColors.Blue, ChartColors.Green, ChartColors.Orange, ChartColors.Gray)
    }

    ProvideChartStyle(chartStyle = rememberChartStyle(colors)) {
        Chart(
            chart = columnChart(
                columns = colors.map { color ->
                    LineComponent(
                        color = color.hashCode(),
                        thicknessDp = 16f,
                        shape = Shapes.rectShape
                    )
                },
                mergeMode = ColumnChart.MergeMode.Stack
            ),
            chartModelProducer = chartEntryModelProducer,
            startAxis = rememberStartAxis(
                valueFormatter = axisValueFormatter,
                itemPlacer = AxisItemPlacer.Vertical.default(maxItemCount = 5)
            ),
            bottomAxis = rememberBottomAxis(
                guideline = null,
                itemPlacer = AxisItemPlacer.Horizontal.default(spacing = 1)
            ),
            modifier = modifier
                .fillMaxWidth()
                .height(200.dp)
        )
    }
}

/**
 * APDU Timeline chart for a single scan (horizontal bar style).
 */
@Composable
fun ApduTimelineChart(
    record: ScanRecord,
    modifier: Modifier = Modifier
) {
    val exchanges = record.apduExchanges
    if (exchanges.isEmpty()) {
        Text(
            "No APDU data recorded",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        return
    }

    var totalDuration = 0L
    for (exchange in exchanges) {
        totalDuration += exchange.durationMs
    }
    totalDuration = totalDuration.coerceAtLeast(1L)
    var cumulative = 0L

    Column(modifier = modifier) {
        for (exchange in exchanges) {
            val widthPercent = exchange.durationMs.toFloat() / totalDuration
            cumulative += exchange.durationMs

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Label
                Text(
                    text = exchange.label.ifEmpty { "Other" },
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.width(140.dp),
                    maxLines = 1
                )

                // Bar
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(20.dp)
                ) {
                    // Background
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(20.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(Color.Gray.copy(alpha = 0.1f))
                    )
                    // Bar
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(widthPercent.coerceAtLeast(0.02f))
                            .height(20.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(ChartColors.Cyan)
                    )
                }

                Spacer(modifier = Modifier.width(8.dp))

                // Duration
                Text(
                    text = "${exchange.durationMs}ms",
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.width(50.dp)
                )
            }
        }
    }
}

/**
 * Aggregated APDU chart showing total time by label.
 */
@Composable
fun ApduAggregatedChart(
    records: List<ScanRecord>,
    modifier: Modifier = Modifier
) {
    val allExchanges = records.flatMap { it.apduExchanges }
    if (allExchanges.isEmpty()) {
        Text(
            "No APDU data recorded",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        return
    }

    // Group by label and sum durations
    val durationByLabel = mutableMapOf<String, Long>()
    for (exchange in allExchanges) {
        val label = exchange.label.ifEmpty { "Other" }
        durationByLabel[label] = (durationByLabel[label] ?: 0L) + exchange.durationMs
    }
    val grouped = durationByLabel.entries.sortedByDescending { it.value }

    var maxDuration = 1L
    for (entry in grouped) {
        if (entry.value > maxDuration) {
            maxDuration = entry.value
        }
    }

    Column(modifier = modifier) {
        for ((label, duration) in grouped) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 3.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = label,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.width(140.dp),
                    maxLines = 1
                )

                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(24.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(Color.Gray.copy(alpha = 0.1f))
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(duration.toFloat() / maxDuration)
                            .height(24.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(ChartColors.Purple)
                    )
                }

                Spacer(modifier = Modifier.width(8.dp))

                Text(
                    text = "${duration}ms",
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.width(50.dp)
                )
            }
        }
    }
}

@Composable
private fun rememberChartStyle(colors: List<Color>) = com.patrykandpatrick.vico.compose.style.ChartStyle(
    axis = com.patrykandpatrick.vico.compose.style.ChartStyle.Axis(
        axisLabelColor = MaterialTheme.colorScheme.onSurfaceVariant,
        axisGuidelineColor = MaterialTheme.colorScheme.outlineVariant,
        axisLineColor = MaterialTheme.colorScheme.outlineVariant
    ),
    columnChart = com.patrykandpatrick.vico.compose.style.ChartStyle.ColumnChart(
        columns = colors.map { color ->
            LineComponent(
                color = color.hashCode(),
                thicknessDp = 16f,
                shape = Shapes.rectShape
            )
        }
    ),
    lineChart = com.patrykandpatrick.vico.compose.style.ChartStyle.LineChart(
        lines = colors.map { color ->
            LineChart.LineSpec(lineColor = color.hashCode())
        }
    ),
    marker = com.patrykandpatrick.vico.compose.style.ChartStyle.Marker(),
    elevationOverlayColor = MaterialTheme.colorScheme.primary
)

private fun formatMs(ms: Long): String = de.scoopsoftware.cardlink.metrics.MetricsFormatting.formatMs(ms)