package de.scoopsoftware.cardlink.demo.reporting

import com.google.gson.Gson
import com.google.gson.JsonParser
import de.scoopsoftware.cardlink.metrics.MetricsFormatting
import de.scoopsoftware.cardlink.metrics.ScanRecord
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Demo-only telemetry: posts scan statistics to a RocketChat channel.
 *
 * This lives in the demo app, NOT in the SDK — it exfiltrates scan data to a
 * configured server, which is an application decision, not SDK behaviour.
 * Uses only the JDK HttpURLConnection + Gson (already a demo dependency).
 * Consumes the SDK's public metrics types (ScanRecord, MetricsFormatting).
 */
object RocketChatReporter {

    private val gson = Gson()

    private data class AuthInfo(val userId: String, val authToken: String)

    // Cached auth token to avoid logging in on every scan
    private var cachedAuth: AuthInfo? = null

    /** Posts scan results to RocketChat. Silently fails on any error. */
    suspend fun report(
        serverUrl: String,
        username: String,
        password: String,
        channel: String,
        record: ScanRecord,
        success: Boolean = true,
        traceLog: List<String> = emptyList()
    ): Unit = withContext(Dispatchers.IO) {
        try {
            val auth = getOrLogin(serverUrl, username, password)
            postMessage(serverUrl, auth, channel, formatMessage(record, success))

            if (traceLog.isNotEmpty()) {
                val roomId = resolveRoomId(serverUrl, auth, channel)
                if (roomId != null) {
                    uploadFile(serverUrl, auth, roomId, "trace.log", traceLog.joinToString("\n").encodeToByteArray())
                }
            }
        } catch (_: Exception) {
            // Silent failure — never interrupt the app flow
        }
    }

    /** Tests the connection by logging in. Returns null on success, else an error message. */
    suspend fun testConnection(serverUrl: String, username: String, password: String): String? =
        withContext(Dispatchers.IO) {
            try {
                cachedAuth = null
                getOrLogin(serverUrl, username, password)
                null
            } catch (e: Exception) {
                e.message ?: "Connection failed"
            }
        }

    /** Clears any cached auth. Call when settings change. */
    fun clearAuth() {
        cachedAuth = null
    }

    private fun getOrLogin(serverUrl: String, username: String, password: String): AuthInfo {
        cachedAuth?.let { return it }
        val baseUrl = serverUrl.trimEnd('/')
        val body = gson.toJson(mapOf("user" to username, "password" to password))
        val (status, text) = httpRequest("$baseUrl/api/v1/login", "POST", jsonBody = body)
        if (status !in 200..299) throw Exception("RocketChat login failed: $status")
        val data = JsonParser.parseString(text).asJsonObject.getAsJsonObject("data")
        val auth = AuthInfo(data.get("userId").asString, data.get("authToken").asString)
        cachedAuth = auth
        return auth
    }

    private fun resolveRoomId(serverUrl: String, auth: AuthInfo, channel: String): String? {
        val baseUrl = serverUrl.trimEnd('/')
        for ((endpoint, key) in listOf("channels.info" to "channel", "groups.info" to "group")) {
            val encoded = java.net.URLEncoder.encode(channel, "UTF-8")
            val (status, text) = httpRequest("$baseUrl/api/v1/$endpoint?roomName=$encoded", "GET", auth = auth)
            if (status in 200..299) {
                val room = JsonParser.parseString(text).asJsonObject.getAsJsonObject(key) ?: continue
                room.get("_id")?.asString?.let { return it }
            }
        }
        return null
    }

    private fun postMessage(serverUrl: String, auth: AuthInfo, channel: String, text: String) {
        val baseUrl = serverUrl.trimEnd('/')
        val body = gson.toJson(mapOf("channel" to channel, "text" to text))
        val (status, _) = httpRequest("$baseUrl/api/v1/chat.postMessage", "POST", jsonBody = body, auth = auth)
        if (status !in 200..299) cachedAuth = null
    }

    private fun uploadFile(serverUrl: String, auth: AuthInfo, roomId: String, fileName: String, fileBytes: ByteArray) {
        val baseUrl = serverUrl.trimEnd('/')
        val boundary = "----CardlinkDemoBoundary"
        val conn = (URL("$baseUrl/api/v1/rooms.upload/$roomId").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            setRequestProperty("X-Auth-Token", auth.authToken)
            setRequestProperty("X-User-Id", auth.userId)
            setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
        }
        conn.outputStream.use { out ->
            out.write("--$boundary\r\n".toByteArray())
            out.write("Content-Disposition: form-data; name=\"file\"; filename=\"$fileName\"\r\n".toByteArray())
            out.write("Content-Type: text/plain\r\n\r\n".toByteArray())
            out.write(fileBytes)
            out.write("\r\n--$boundary--\r\n".toByteArray())
        }
        if (conn.responseCode !in 200..299) cachedAuth = null
        conn.disconnect()
    }

    private fun httpRequest(
        url: String,
        method: String,
        jsonBody: String? = null,
        auth: AuthInfo? = null
    ): Pair<Int, String> {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15_000
            readTimeout = 15_000
            auth?.let {
                setRequestProperty("X-Auth-Token", it.authToken)
                setRequestProperty("X-User-Id", it.userId)
            }
            if (jsonBody != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
        }
        jsonBody?.let { body -> conn.outputStream.use { it.write(body.toByteArray()) } }
        val status = conn.responseCode
        val stream = if (status in 200..299) conn.inputStream else conn.errorStream
        val text = stream?.bufferedReader()?.use { it.readText() } ?: ""
        conn.disconnect()
        return status to text
    }

    private data class Category(val name: String, val ms: Long)

    /** Formats a ScanRecord as an ASCII bar chart + APDU log for RocketChat. */
    private fun formatMessage(record: ScanRecord, success: Boolean): String {
        val categories = buildCategories(record)
        val total = record.totalTimeMs
        val icon = if (success) "✅" else "❌"

        return buildString {
            appendLine("$icon *Cardlink Scan* — ${MetricsFormatting.formatMs(total)} total")
            appendLine("```")
            for ((name, ms) in categories) {
                if (ms <= 0) continue
                val pct = if (total > 0) (ms.toDouble() / total * 100).toInt() else 0
                val barLen = (pct / 5).coerceIn(0, 20)
                val bar = "█".repeat(barLen).padEnd(20, '░')
                val label = name.padEnd(8)
                val time = MetricsFormatting.formatMs(ms).padStart(6)
                appendLine("$label $bar $time ($pct%)")
            }
            appendLine("```")

            val exchanges = record.apduExchanges
            if (exchanges.isNotEmpty()) {
                appendLine()
                appendLine("APDU Log (${exchanges.size} exchanges)")
                appendLine("```")
                for ((i, apdu) in exchanges.withIndex()) {
                    appendLine("${(i + 1).toString().padStart(2)}. ${apdu.label} — ${apdu.durationMs}ms")
                }
                appendLine("```")
            }
        }.trimEnd()
    }

    private fun buildCategories(record: ScanRecord): List<Category> {
        val exchanges = record.apduExchanges
        var pace = 0L
        var popp = 0L
        var network = 0L
        var otherNfc = 0L

        for (ex in exchanges) {
            when {
                ex.label.startsWith("Network:") -> network += ex.durationMs
                ex.label.contains("MSE:SET AT") ||
                    ex.label.contains("GENERAL AUTHENTICATE") ||
                    ex.label.contains("CardAccess") -> pace += ex.durationMs
                ex.label.startsWith("PoPP:") -> popp += ex.durationMs
                else -> otherNfc += ex.durationMs
            }
        }

        if (exchanges.isEmpty()) otherNfc = record.nfcTimeMs

        val hasPoPP = popp > 0 || exchanges.any { it.label.startsWith("PoPP:") }
        val adjustedOther = maxOf(0L, record.otherTimeMs - network)

        return if (hasPoPP) {
            listOf(
                Category("PACE", pace),
                Category("PoPP", popp),
                Category("NFC", otherNfc),
                Category("Network", network),
                Category("Crypto", record.cryptoTimeMs),
                Category("Gzip", record.gzipTimeMs),
                Category("Other", adjustedOther)
            )
        } else {
            listOf(
                Category("NFC", otherNfc),
                Category("Crypto", record.cryptoTimeMs),
                Category("Gzip", record.gzipTimeMs),
                Category("Other", record.otherTimeMs)
            )
        }
    }
}
