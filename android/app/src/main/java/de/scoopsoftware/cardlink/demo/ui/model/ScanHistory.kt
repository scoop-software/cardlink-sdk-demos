package de.scoopsoftware.cardlink.demo.ui.model

import android.content.Context
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.google.gson.reflect.TypeToken
import de.scoopsoftware.cardlink.metrics.CsvExporter
import de.scoopsoftware.cardlink.metrics.ScanRecord
import de.scoopsoftware.cardlink.metrics.ScanStatistics
import de.scoopsoftware.nfc.model.ApduExchangeRecord
import de.scoopsoftware.nfc.model.PerformanceMetricsSnapshot
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Manages the history of card scans with persistence to JSON file.
 * Uses SDK's ScanRecord for the data model.
 */
class ScanHistory(private val context: Context) {
    private val _records = MutableStateFlow<List<ScanRecord>>(emptyList())
    val records: StateFlow<List<ScanRecord>> = _records.asStateFlow()

    private val gson: Gson = GsonBuilder().create()
    private val file: File
        get() = File(context.filesDir, "scan-history.json")

    private val timestampFormatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    init {
        loadFromDisk()
    }

    /**
     * Adds a new scan record to the history.
     */
    fun add(record: ScanRecord) {
        _records.value = _records.value + record
        saveToDisk()
    }

    /**
     * Clears all scan history.
     */
    fun clear() {
        _records.value = emptyList()
        saveToDisk()
    }

    private fun loadFromDisk() {
        if (!file.exists()) return

        try {
            val json = file.readText()
            val type = object : TypeToken<List<ScanRecordJson>>() {}.type
            val jsonRecords: List<ScanRecordJson> = gson.fromJson(json, type) ?: emptyList()
            _records.value = jsonRecords.map { it.toScanRecord() }
        } catch (e: Exception) {
            android.util.Log.e("ScanHistory", "Failed to load scan history", e)
        }
    }

    private fun saveToDisk() {
        try {
            val jsonRecords = _records.value.map { ScanRecordJson.fromScanRecord(it) }
            val json = gson.toJson(jsonRecords)
            file.writeText(json)
        } catch (e: Exception) {
            android.util.Log.e("ScanHistory", "Failed to save scan history", e)
        }
    }

    /**
     * Exports records to CSV format using the SDK's CsvExporter.
     */
    fun exportCSV(): String {
        return CsvExporter.export(_records.value) { timestampMs ->
            timestampFormatter.format(Date(timestampMs))
        }
    }

    // Computed statistics using SDK utilities
    private val stats get() = ScanStatistics.calculateStats(_records.value)

    val totalScans: Int get() = stats.totalScans
    val averageTotalTimeMs: Long get() = stats.averageTotalTimeMs
    val minTotalTimeMs: Long get() = stats.minTotalTimeMs
    val maxTotalTimeMs: Long get() = stats.maxTotalTimeMs
    val averageNfcTimeMs: Long get() = stats.averageNfcTimeMs
    val averageCryptoTimeMs: Long get() = stats.averageCryptoTimeMs
}

/**
 * JSON-serializable version of ScanRecord for persistence.
 */
private data class ScanRecordJson(
    val id: String,
    val timestampMs: Long,
    val totalTimeMs: Long,
    val nfcTimeMs: Long,
    val nfcCallCount: Int,
    val totalCryptoTimeMs: Long,
    val aesCbcEncryptTimeMs: Long,
    val aesCbcEncryptCount: Int,
    val aesCbcDecryptTimeMs: Long,
    val aesCbcDecryptCount: Int,
    val aesCmacTimeMs: Long,
    val aesCmacCount: Int,
    val sha1TimeMs: Long,
    val sha1Count: Int,
    val sha256TimeMs: Long,
    val sha256Count: Int,
    val ecKeyGenTimeMs: Long,
    val ecKeyGenCount: Int,
    val ecScalarMultiplyTimeMs: Long,
    val ecScalarMultiplyCount: Int,
    val ecPointAddTimeMs: Long,
    val ecPointAddCount: Int,
    val gzipDecompressTimeMs: Long,
    val gzipDecompressCount: Int,
    val otherTimeMs: Long,
    val apduExchanges: List<ApduExchangeJson>
) {
    companion object {
        fun fromScanRecord(record: ScanRecord): ScanRecordJson {
            return ScanRecordJson(
                id = record.id,
                timestampMs = record.timestampMs,
                totalTimeMs = record.totalTimeMs,
                nfcTimeMs = record.nfcTimeMs,
                nfcCallCount = record.nfcCallCount,
                totalCryptoTimeMs = record.cryptoTimeMs,
                aesCbcEncryptTimeMs = record.aesCbcEncryptTimeMs,
                aesCbcEncryptCount = record.aesCbcEncryptCount,
                aesCbcDecryptTimeMs = record.aesCbcDecryptTimeMs,
                aesCbcDecryptCount = record.aesCbcDecryptCount,
                aesCmacTimeMs = record.aesCmacTimeMs,
                aesCmacCount = record.aesCmacCount,
                sha1TimeMs = record.sha1TimeMs,
                sha1Count = record.sha1Count,
                sha256TimeMs = record.sha256TimeMs,
                sha256Count = record.sha256Count,
                ecKeyGenTimeMs = record.ecKeyGenTimeMs,
                ecKeyGenCount = record.ecKeyGenCount,
                ecScalarMultiplyTimeMs = record.ecScalarMultiplyTimeMs,
                ecScalarMultiplyCount = record.ecScalarMultiplyCount,
                ecPointAddTimeMs = record.ecPointAddTimeMs,
                ecPointAddCount = record.ecPointAddCount,
                gzipDecompressTimeMs = record.gzipTimeMs,
                gzipDecompressCount = record.gzipDecompressCount,
                otherTimeMs = record.otherTimeMs,
                apduExchanges = record.apduExchanges.map { ApduExchangeJson(it.command, it.response, it.durationMs, it.label) }
            )
        }
    }

    fun toScanRecord(): ScanRecord {
        return ScanRecord(
            id = id,
            metrics = PerformanceMetricsSnapshot(
                timestampMs = timestampMs,
                totalTimeMs = totalTimeMs,
                nfcTimeMs = nfcTimeMs,
                nfcCallCount = nfcCallCount,
                totalCryptoTimeMs = totalCryptoTimeMs,
                aesCbcEncryptTimeMs = aesCbcEncryptTimeMs,
                aesCbcEncryptCount = aesCbcEncryptCount,
                aesCbcDecryptTimeMs = aesCbcDecryptTimeMs,
                aesCbcDecryptCount = aesCbcDecryptCount,
                aesCmacTimeMs = aesCmacTimeMs,
                aesCmacCount = aesCmacCount,
                sha1TimeMs = sha1TimeMs,
                sha1Count = sha1Count,
                sha256TimeMs = sha256TimeMs,
                sha256Count = sha256Count,
                ecKeyGenTimeMs = ecKeyGenTimeMs,
                ecKeyGenCount = ecKeyGenCount,
                ecScalarMultiplyTimeMs = ecScalarMultiplyTimeMs,
                ecScalarMultiplyCount = ecScalarMultiplyCount,
                ecPointAddTimeMs = ecPointAddTimeMs,
                ecPointAddCount = ecPointAddCount,
                gzipDecompressTimeMs = gzipDecompressTimeMs,
                gzipDecompressCount = gzipDecompressCount,
                otherTimeMs = otherTimeMs,
                apduExchanges = apduExchanges.map {
                    ApduExchangeRecord(it.command, it.response, it.durationMs, it.label)
                }
            )
        )
    }
}

private data class ApduExchangeJson(
    val command: String,
    val response: String,
    val durationMs: Long,
    val label: String
)