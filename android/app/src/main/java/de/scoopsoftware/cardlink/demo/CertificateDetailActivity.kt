package de.scoopsoftware.cardlink.demo

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import java.io.ByteArrayInputStream
import java.security.MessageDigest
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.text.SimpleDateFormat
import java.util.Locale

class CertificateDetailActivity : AppCompatActivity() {

    companion object {
        private const val EXTRA_CERT_DATA = "cert_data"
        private const val EXTRA_CERT_TITLE = "cert_title"

        fun start(context: Context, certData: ByteArray, title: String) {
            val intent = Intent(context, CertificateDetailActivity::class.java).apply {
                putExtra(EXTRA_CERT_DATA, certData)
                putExtra(EXTRA_CERT_TITLE, title)
            }
            context.startActivity(intent)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_certificate_detail)

        val certData = intent.getByteArrayExtra(EXTRA_CERT_DATA)
        val title = intent.getStringExtra(EXTRA_CERT_TITLE) ?: "Certificate Details"

        supportActionBar?.apply {
            this.title = title
            setDisplayHomeAsUpEnabled(true)
        }

        val detailText = findViewById<TextView>(R.id.certificateDetailText)

        if (certData == null) {
            detailText.text = "No certificate data"
            return
        }

        try {
            val certFactory = CertificateFactory.getInstance("X.509")
            val cert = certFactory.generateCertificate(ByteArrayInputStream(certData)) as X509Certificate
            detailText.text = formatCertificateDetails(cert, certData)
        } catch (e: Exception) {
            detailText.text = "Error parsing certificate: ${e.message}"
        }
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    private fun formatCertificateDetails(cert: X509Certificate, rawData: ByteArray): String = buildString {
        val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss z", Locale.getDefault())

        appendLine("═══════════════════════════════════")
        appendLine("         SUBJECT")
        appendLine("═══════════════════════════════════")
        appendLine()
        formatDN(cert.subjectX500Principal.name).forEach { (key, value) ->
            appendLine("$key: $value")
        }

        appendLine()
        appendLine("═══════════════════════════════════")
        appendLine("         ISSUER")
        appendLine("═══════════════════════════════════")
        appendLine()
        formatDN(cert.issuerX500Principal.name).forEach { (key, value) ->
            appendLine("$key: $value")
        }

        appendLine()
        appendLine("═══════════════════════════════════")
        appendLine("         VALIDITY")
        appendLine("═══════════════════════════════════")
        appendLine()
        appendLine("Not Before: ${dateFormat.format(cert.notBefore)}")
        appendLine("Not After:  ${dateFormat.format(cert.notAfter)}")

        val now = System.currentTimeMillis()
        val status = when {
            now < cert.notBefore.time -> "⚠️ Not yet valid"
            now > cert.notAfter.time -> "❌ Expired"
            else -> "✓ Valid"
        }
        appendLine("Status:     $status")

        appendLine()
        appendLine("═══════════════════════════════════")
        appendLine("         DETAILS")
        appendLine("═══════════════════════════════════")
        appendLine()
        appendLine("Version:        ${cert.version}")
        appendLine("Serial Number:  ${cert.serialNumber.toString(16).uppercase()}")
        appendLine("Signature Alg:  ${cert.sigAlgName}")

        appendLine()
        appendLine("═══════════════════════════════════")
        appendLine("         PUBLIC KEY")
        appendLine("═══════════════════════════════════")
        appendLine()
        appendLine("Algorithm:  ${cert.publicKey.algorithm}")
        appendLine("Key Size:   ${getKeySize(cert)} bits")

        appendLine()
        appendLine("═══════════════════════════════════")
        appendLine("         FINGERPRINTS")
        appendLine("═══════════════════════════════════")
        appendLine()
        appendLine("SHA-256:")
        appendLine(formatFingerprint(sha256(rawData)))
        appendLine()
        appendLine("SHA-1:")
        appendLine(formatFingerprint(sha1(rawData)))

        // Key Usage
        cert.keyUsage?.let { keyUsage ->
            appendLine()
            appendLine("═══════════════════════════════════")
            appendLine("         KEY USAGE")
            appendLine("═══════════════════════════════════")
            appendLine()
            val usages = mutableListOf<String>()
            if (keyUsage[0]) usages.add("Digital Signature")
            if (keyUsage[1]) usages.add("Non-Repudiation")
            if (keyUsage[2]) usages.add("Key Encipherment")
            if (keyUsage[3]) usages.add("Data Encipherment")
            if (keyUsage[4]) usages.add("Key Agreement")
            if (keyUsage[5]) usages.add("Key Cert Sign")
            if (keyUsage[6]) usages.add("CRL Sign")
            if (keyUsage[7]) usages.add("Encipher Only")
            if (keyUsage[8]) usages.add("Decipher Only")
            usages.forEach { appendLine("• $it") }
        }

        // Extended Key Usage
        cert.extendedKeyUsage?.let { extKeyUsage ->
            appendLine()
            appendLine("═══════════════════════════════════")
            appendLine("      EXTENDED KEY USAGE")
            appendLine("═══════════════════════════════════")
            appendLine()
            extKeyUsage.forEach { oid ->
                val name = when (oid) {
                    "1.3.6.1.5.5.7.3.1" -> "Server Authentication"
                    "1.3.6.1.5.5.7.3.2" -> "Client Authentication"
                    "1.3.6.1.5.5.7.3.3" -> "Code Signing"
                    "1.3.6.1.5.5.7.3.4" -> "Email Protection"
                    "1.3.6.1.5.5.7.3.8" -> "Time Stamping"
                    else -> oid
                }
                appendLine("• $name")
            }
        }
    }

    private fun formatDN(dn: String): List<Pair<String, String>> {
        val result = mutableListOf<Pair<String, String>>()
        val labelMap = mapOf(
            "CN" to "Common Name",
            "O" to "Organization",
            "OU" to "Org. Unit",
            "C" to "Country",
            "ST" to "State",
            "L" to "Locality",
            "SERIALNUMBER" to "Serial Number",
            "2.5.4.5" to "Serial Number"
        )

        // Simple parsing - split by comma but handle escaped commas
        val parts = dn.split(",(?=(?:[^\"]*\"[^\"]*\")*[^\"]*$)".toRegex())
        for (part in parts) {
            val trimmed = part.trim()
            val eqIndex = trimmed.indexOf('=')
            if (eqIndex > 0) {
                val key = trimmed.substring(0, eqIndex).trim()
                val value = trimmed.substring(eqIndex + 1).trim().removeSurrounding("\"")
                val label = labelMap[key] ?: key
                result.add(label to value)
            }
        }
        return result
    }

    private fun getKeySize(cert: X509Certificate): Int {
        return when (val key = cert.publicKey) {
            is java.security.interfaces.RSAPublicKey -> key.modulus.bitLength()
            is java.security.interfaces.ECPublicKey -> key.params.order.bitLength()
            else -> 0
        }
    }

    private fun sha256(data: ByteArray): ByteArray {
        return MessageDigest.getInstance("SHA-256").digest(data)
    }

    private fun sha1(data: ByteArray): ByteArray {
        return MessageDigest.getInstance("SHA-1").digest(data)
    }

    private fun formatFingerprint(hash: ByteArray): String {
        return hash.joinToString(":") { "%02X".format(it) }
    }
}
