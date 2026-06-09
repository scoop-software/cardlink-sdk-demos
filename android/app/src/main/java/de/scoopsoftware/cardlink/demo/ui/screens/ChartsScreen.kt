package de.scoopsoftware.cardlink.demo.ui.screens

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import de.scoopsoftware.cardlink.demo.ui.components.ApduAggregatedChart
import de.scoopsoftware.cardlink.demo.ui.components.ApduTimelineChart
import de.scoopsoftware.cardlink.demo.ui.components.BreakdownChart
import de.scoopsoftware.cardlink.demo.ui.components.ScanTimeChart
import de.scoopsoftware.cardlink.demo.ui.model.ScanHistory
import de.scoopsoftware.cardlink.metrics.MetricsFormatting
import de.scoopsoftware.cardlink.metrics.ScanRecord
import de.scoopsoftware.cardlink.demo.ui.theme.ChartColors
import java.io.File

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChartsScreen(scanHistory: ScanHistory) {
    val records by scanHistory.records.collectAsState()
    val context = LocalContext.current

    var showClearDialog by remember { mutableStateOf(false) }
    var apduChartMode by remember { mutableIntStateOf(0) } // 0 = Last Scan, 1 = Aggregated

    // Clear confirmation dialog
    if (showClearDialog) {
        AlertDialog(
            onDismissRequest = { showClearDialog = false },
            title = { Text("Clear History?") },
            text = { Text("This will delete all ${records.size} scan records. This action cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        scanHistory.clear()
                        showClearDialog = false
                    }
                ) {
                    Text("Clear All Data", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {
        TopAppBar(
            title = { Text("Performance") },
            actions = {
                if (records.isNotEmpty()) {
                    IconButton(
                        onClick = {
                            // Export CSV
                            val csvData = scanHistory.exportCSV()
                            val file = File(context.cacheDir, "cardlink-metrics.csv")
                            file.writeText(csvData)

                            val uri = FileProvider.getUriForFile(
                                context,
                                "${context.packageName}.fileprovider",
                                file
                            )

                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/csv"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                putExtra(Intent.EXTRA_SUBJECT, "Cardlink Performance Metrics")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            context.startActivity(Intent.createChooser(intent, "Export Metrics"))
                        }
                    ) {
                        Icon(Icons.Default.Share, contentDescription = "Export")
                    }
                    IconButton(onClick = { showClearDialog = true }) {
                        Icon(
                            Icons.Default.Delete,
                            contentDescription = "Clear",
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                }
            }
        )

        if (records.isEmpty()) {
            // Empty state
            EmptyState()
        } else {
            Column(
                modifier = Modifier
                    .verticalScroll(rememberScrollState())
                    .fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Summary card
                SummaryCard(scanHistory)

                // Scan time chart
                ChartCard(title = "Scan Time History", icon = "chart.line") {
                    ScanTimeChart(records = records)
                }

                // Breakdown chart
                val hasPoPP = records.any { r -> r.apduExchanges.any { it.label.startsWith("PoPP:") } }
                ChartCard(title = "Time Breakdown", icon = "chart.bar") {
                    BreakdownChart(records = records)
                    Spacer(modifier = Modifier.height(8.dp))
                    BreakdownLegend(hasPoPP = hasPoPP)
                }

                // APDU Timeline
                val lastRecord = records.lastOrNull()
                if (lastRecord != null && lastRecord.apduExchanges.isNotEmpty()) {
                    ChartCard(
                        title = "APDU Timeline",
                        icon = "rectangle.stack",
                        trailing = {
                            SingleChoiceSegmentedButtonRow {
                                SegmentedButton(
                                    selected = apduChartMode == 0,
                                    onClick = { apduChartMode = 0 },
                                    shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
                                ) {
                                    Text("Last Scan", fontSize = 12.sp)
                                }
                                SegmentedButton(
                                    selected = apduChartMode == 1,
                                    onClick = { apduChartMode = 1 },
                                    shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
                                ) {
                                    Text("Aggregated", fontSize = 12.sp)
                                }
                            }
                        }
                    ) {
                        if (apduChartMode == 0) {
                            ApduTimelineChart(record = lastRecord)
                        } else {
                            ApduAggregatedChart(records = records)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyState() {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            Icons.Default.List,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            "No Scan Data",
            style = MaterialTheme.typography.titleLarge
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "Scan a card with metrics enabled to see performance charts here.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun SummaryCard(scanHistory: ScanHistory) {
    val records by scanHistory.records.collectAsState()
    val lastRecord = records.lastOrNull()
    val hasPoPP = lastRecord?.apduExchanges?.any { it.label.startsWith("PoPP:") } == true

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                "Summary",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(12.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                StatCell("Total Scans", "${scanHistory.totalScans}")
                StatCell("Average", formatMs(scanHistory.averageTotalTimeMs))
            }
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                StatCell("Worst", formatMs(scanHistory.maxTotalTimeMs))
                StatCell("Best", formatMs(scanHistory.minTotalTimeMs))
            }

            if (hasPoPP && lastRecord != null) {
                val paceMs = lastRecord.apduExchanges
                    .filter { it.label.contains("MSE:SET AT") || it.label.contains("GENERAL AUTHENTICATE") || it.label.contains("CardAccess") }
                    .sumOf { it.durationMs }
                val poppMs = lastRecord.apduExchanges
                    .filter { it.label.startsWith("PoPP:") }
                    .sumOf { it.durationMs }
                val cachedCount = lastRecord.apduExchanges.count { it.label.contains("cached") }

                Spacer(modifier = Modifier.height(8.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    StatCell("PACE", formatMs(paceMs))
                    StatCell("PoPP APDU", formatMs(poppMs))
                }
                if (cachedCount > 0) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        StatCell("Cached", "$cachedCount APDUs")
                    }
                }
            }
        }
    }
}

@Composable
private fun RowScope.StatCell(title: String, value: String) {
    Column(
        modifier = Modifier
            .weight(1f)
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surface)
            .padding(12.dp),
        horizontalAlignment = Alignment.Start
    ) {
        Text(
            title,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            value,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
private fun ChartCard(
    title: String,
    icon: String,
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                trailing?.invoke()
            }
            Spacer(modifier = Modifier.height(12.dp))
            content()
        }
    }
}

@Composable
private fun BreakdownLegend(hasPoPP: Boolean = false) {
    Row(
        modifier = Modifier.fillMaxWidth(),
    ) {
        if (hasPoPP) {
            LegendItem(ChartColors.Indigo, "PACE")
            LegendItem(ChartColors.Blue, "PoPP")
            LegendItem(ChartColors.Cyan, "NFC")
            LegendItem(ChartColors.Purple, "Network")
        } else {
            LegendItem(ChartColors.Blue, "NFC")
        }
        LegendItem(ChartColors.Green, "Crypto")
        LegendItem(ChartColors.Orange, "Gzip")
        LegendItem(ChartColors.Gray, "Other")
    }
}

@Composable
private fun RowScope.LegendItem(color: Color, label: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.weight(1f),
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(color)
        )
        Spacer(modifier = Modifier.height(12.dp))
        Box(modifier = Modifier.height(48.dp), contentAlignment = Alignment.TopCenter) {
            Text(
                label,
                style = MaterialTheme.typography.labelSmall.copy(fontSize = 9.sp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                softWrap = false,
                modifier = Modifier.rotate(90f),
            )
        }
    }
}

private fun formatMs(ms: Long): String = MetricsFormatting.formatMs(ms)
