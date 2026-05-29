package de.scoopsoftware.cardlink.demo

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.graphics.Rect
import android.view.MotionEvent
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.view.animation.AccelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import androidx.core.content.ContextCompat
import androidx.appcompat.widget.SwitchCompat
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import de.scoopsoftware.nfc.vsd.EgkCardView
import de.scoopsoftware.nfc.EgkReader
import de.scoopsoftware.nfc.FILE_NOT_FOUND
import de.scoopsoftware.nfc.NfcReadOptions
import de.scoopsoftware.nfc.model.EgkCardData
import de.scoopsoftware.nfc.nfc.NfcReadCallback
import de.scoopsoftware.nfc.nfc.NfcSession
import de.scoopsoftware.nfc.nfc.NfcResult
import de.scoopsoftware.nfc.nfc.NfcMessage
import de.scoopsoftware.nfc.vsd.VsdXmlParser
import de.scoopsoftware.cardlink.sms.SmsReceiver

class MainActivity : AppCompatActivity() {

    private val isDebugBuild: Boolean
        get() = (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private lateinit var canInputLayout: TextInputLayout
    private lateinit var canInput: TextInputEditText
    private lateinit var ecOnlySwitch: SwitchCompat
    private lateinit var metricsSwitch: SwitchCompat
    private lateinit var apduTracingSwitch: SwitchCompat
    private lateinit var readButton: Button
    private lateinit var certButtonsLayout: LinearLayout
    private lateinit var viewRsaCertButton: Button
    private lateinit var viewEccCertButton: Button
    private lateinit var egkCardView: EgkCardView
    private lateinit var statusText: TextView
    private lateinit var resultText: TextView

    // Use the NfcSession API
    private val nfcSession = NfcSession()

    // Progress log for display
    private val progressLog = StringBuilder()

    // Store certificate data for viewing
    private var x509RsaCert: ByteArray? = null
    private var x509EccCert: ByteArray? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        canInputLayout = findViewById(R.id.canInputLayout)
        canInput = findViewById(R.id.canInput)
        ecOnlySwitch = findViewById(R.id.ecOnlySwitch)
        metricsSwitch = findViewById(R.id.metricsSwitch)
        apduTracingSwitch = findViewById(R.id.apduTracingSwitch)
        readButton = findViewById(R.id.readButton)
        certButtonsLayout = findViewById(R.id.certButtonsLayout)
        viewRsaCertButton = findViewById(R.id.viewRsaCertButton)
        viewEccCertButton = findViewById(R.id.viewEccCertButton)
        egkCardView = findViewById(R.id.egkCardView)
        statusText = findViewById(R.id.statusText)
        resultText = findViewById(R.id.resultText)

        supportActionBar?.title = "SCOOP Cardlink Android Demo"

        // Show dev indicator dot in the action bar for debug builds
        if (isDebugBuild) {
            supportActionBar?.apply {
                setDisplayShowCustomEnabled(true)
                val dot = View(this@MainActivity).apply {
                    val size = (8 * resources.displayMetrics.density).toInt()
                    layoutParams = Toolbar.LayoutParams(size, size).apply {
                        gravity = Gravity.END or Gravity.TOP
                        marginEnd = (8 * resources.displayMetrics.density).toInt()
                        topMargin = (8 * resources.displayMetrics.density).toInt()
                    }
                    background = ContextCompat.getDrawable(this@MainActivity, R.drawable.dev_indicator)
                }
                customView = dot
            }
        }

        viewRsaCertButton.setOnClickListener {
            x509RsaCert?.let { CertificateDetailActivity.start(this, it, "X.509 Auth RSA") }
        }
        viewEccCertButton.setOnClickListener {
            x509EccCert?.let { CertificateDetailActivity.start(this, it, "X.509 Auth ECC") }
        }

        // Camera button to scan CAN
        canInputLayout.setEndIconOnClickListener {
            CanScannerActivity.start(this, REQUEST_SCAN_CAN)
        }

        readButton.setOnClickListener {
            startReading()
        }

        // Request SMS permission and listen for CAN codes (SDK handles everything)
        SmsReceiver.requestPermissionAndListen(this) { can ->
            runOnUiThread {
                canInput.setText(can)
                Toast.makeText(this, "CAN received via SMS: $can", Toast.LENGTH_SHORT).show()
            }
        }
    }

    companion object {
        private const val CARD_ANIMATION_DURATION = 300L
        private const val REQUEST_SCAN_CAN = 1001
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_SCAN_CAN && resultCode == Activity.RESULT_OK) {
            val scannedCan = data?.getStringExtra(CanScannerActivity.EXTRA_CAN_RESULT)
            if (scannedCan != null) {
                canInput.setText(scannedCan)
                Toast.makeText(this, "CAN scanned: $scannedCan", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun startReading() {
        val can = canInput.text?.toString() ?: ""
        if (can.length != 6) {
            statusText.text = "Please enter a 6-digit CAN"
            return
        }

        val ecOnlyCard = ecOnlySwitch.isChecked
        val recordMetrics = metricsSwitch.isChecked
        val enableApduTracing = apduTracingSwitch.isChecked

        progressLog.clear()
        resultText.text = ""
        readButton.isEnabled = false

        // Hide any previously displayed card with animation
        hideCardVisualizationAnimated()
        hideCertificateButtons()

        // Build options
        val options = NfcReadOptions.Builder()
            .recordMetrics(recordMetrics)
            .enableApduTracing(enableApduTracing)
            .fileCacheProvider(
                if (ecOnlyCard) {
                    { fileName ->
                        if (fileName == "EF.C.CH.AUT.R2048") FILE_NOT_FOUND else null
                    }
                } else null
            )
            .build()

        // Use the NfcSession API
        nfcSession.readCard(this, can, options, object : NfcReadCallback {
            override fun onMessage(message: String, nfcMessage: NfcMessage) {
                statusText.text = message

                // Log the progress for display
                val logLine = when (nfcMessage) {
                    is NfcMessage.PaceStep -> "PACE Step ${nfcMessage.step}: ${nfcMessage.label} (${nfcMessage.durationMs}ms)"
                    is NfcMessage.PaceComplete -> "PACE Complete (${nfcMessage.durationMs}ms)"
                    is NfcMessage.ReadingFile -> if (nfcMessage.name.isNotEmpty()) "Reading ${nfcMessage.name}..." else "Reading files..."
                    is NfcMessage.FileRead -> "Read ${nfcMessage.name} (${nfcMessage.sizeBytes} bytes, ${nfcMessage.durationMs}ms)"
                    is NfcMessage.VsdDataAvailable -> {
                        // Display card visualization as soon as VSD data is available
                        displayCardVisualizationEarly(nfcMessage.pdXml, nfcMessage.vdXml, can)
                        "Patient data available"
                    }
                    is NfcMessage.ApduExchange -> {
                        val desc = if (nfcMessage.label.isNotEmpty()) "${nfcMessage.label}: " else ""
                        "  ${desc}${nfcMessage.durationMs}ms | C:${nfcMessage.command.take(16)}... R:${nfcMessage.response.takeLast(4)}"
                    }
                    else -> message
                }
                progressLog.insert(0, logLine + "\n")
                resultText.text = progressLog.toString()
            }

            override fun onComplete(result: NfcResult) {
                readButton.isEnabled = true

                when (result) {
                    is NfcResult.Success -> {
                        statusText.text = "Card read successfully!"
                        resultText.text = formatCardData(result.data)

                        // Store certificates and show view buttons
                        x509RsaCert = result.data.x509AuthRSA
                        x509EccCert = result.data.x509AuthECC
                        updateCertificateButtons()

                        // Display eGK card visualization
                        displayCardVisualization(result.data, can)
                    }

                    is NfcResult.Error -> {
                        statusText.text = "Error: ${result.message}"
                        resultText.text = buildString {
                            append(progressLog.toString())
                            appendLine()
                            appendLine("=== Error Details ===")
                            appendLine()
                            appendLine("Message: ${result.message}")
                            appendLine()
                            appendLine("Stack Trace:")
                            appendLine(result.exception.stackTraceToString())
                        }
                    }

                    NfcResult.Cancelled -> {
                        statusText.text = "Reading cancelled"
                        hideCertificateButtons()
                        hideCardVisualizationAnimated()
                    }

                    NfcResult.NfcNotAvailable -> {
                        statusText.text = "NFC is not available on this device"
                        hideCertificateButtons()
                        hideCardVisualizationAnimated()
                    }

                    NfcResult.NfcDisabled -> {
                        statusText.text = "Please enable NFC in settings"
                        hideCertificateButtons()
                        hideCardVisualizationAnimated()
                    }
                }
            }
        })
    }

    private fun updateCertificateButtons() {
        val hasRsa = x509RsaCert != null
        val hasEcc = x509EccCert != null

        if (hasRsa || hasEcc) {
            certButtonsLayout.visibility = View.VISIBLE
            viewRsaCertButton.visibility = if (hasRsa) View.VISIBLE else View.GONE
            viewEccCertButton.visibility = if (hasEcc) View.VISIBLE else View.GONE
        } else {
            hideCertificateButtons()
        }
    }

    private fun hideCertificateButtons() {
        certButtonsLayout.visibility = View.GONE
        viewRsaCertButton.visibility = View.GONE
        viewEccCertButton.visibility = View.GONE
    }

    private fun displayCardVisualization(cardData: EgkCardData, can: String) {
        val parsedData = VsdXmlParser.parse(cardData.pdXml, cardData.vdXml)
        if (parsedData != null) {
            egkCardView.setCardData(parsedData, can)
            showCardAnimated()
        } else {
            // If no VSD data available, hide the card view
            hideCardVisualizationAnimated()
        }
    }

    /**
     * Display card visualization early when VSD data becomes available.
     * Called during card reading before certificates are read.
     */
    private fun displayCardVisualizationEarly(pdXml: String?, vdXml: String?, can: String) {
        val parsedData = VsdXmlParser.parse(pdXml, vdXml)
        if (parsedData != null) {
            egkCardView.setCardData(parsedData, can)
            showCardAnimated()
        }
    }

    /**
     * Show card with scale and fade animation.
     */
    private fun showCardAnimated() {
        if (egkCardView.visibility == View.VISIBLE && egkCardView.alpha == 1f) {
            return // Already visible
        }

        egkCardView.apply {
            // Cancel any running animation
            animate().cancel()

            // Start from scaled down and invisible
            alpha = 0f
            scaleX = 0.8f
            scaleY = 0.8f
            visibility = View.VISIBLE

            // Animate in with overshoot for a playful bounce effect
            animate()
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(CARD_ANIMATION_DURATION)
                .setInterpolator(OvershootInterpolator(1.2f))
                .setListener(null)
                .start()
        }
    }

    /**
     * Hide card with scale and fade animation.
     */
    private fun hideCardVisualizationAnimated() {
        if (egkCardView.visibility != View.VISIBLE) {
            return // Already hidden
        }

        egkCardView.animate()
            .alpha(0f)
            .scaleX(0.8f)
            .scaleY(0.8f)
            .setDuration(CARD_ANIMATION_DURATION)
            .setInterpolator(AccelerateInterpolator())
            .setListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    egkCardView.visibility = View.GONE
                    // Reset scale for next show
                    egkCardView.scaleX = 1f
                    egkCardView.scaleY = 1f
                }
            })
            .start()
    }

    /**
     * Hide card immediately without animation.
     */
    private fun hideCardVisualization() {
        egkCardView.animate().cancel()
        egkCardView.visibility = View.GONE
        egkCardView.alpha = 1f
        egkCardView.scaleX = 1f
        egkCardView.scaleY = 1f
    }

    private fun formatCardData(cardData: EgkCardData): String = buildString {
        append(progressLog.toString())
        appendLine()
        appendLine(EgkReader.getPerformanceMetrics())
        appendLine()
        appendLine("=== Card Data ===")
        appendLine()
        cardData.atrCard?.let {
            appendLine("ATR (card):")
            appendLine(it.toHexString())
            appendLine()
        }
        appendLine("GDO:")
        appendLine(cardData.gdo.toHexString())
        appendLine()
        appendLine("CVC Auth (${cardData.cvcAuth.size} bytes):")
        appendLine(cardData.cvcAuth.toHexString())
        cardData.cvcCA?.let {
            appendLine()
            appendLine("CVC CA (${it.size} bytes):")
            appendLine(it.toHexString())
        }

        cardData.x509AuthRSA?.let {
            appendLine()
            appendLine("X.509 RSA (${it.size} bytes):")
            appendLine(it.toHexString())
        }

        cardData.x509AuthECC?.let {
            appendLine()
            appendLine("X.509 ECC (${it.size} bytes):")
            appendLine(it.toHexString())
        }

        cardData.pdXml?.let {
            appendLine()
            appendLine("=== PD (Persönliche Daten) ===")
            appendLine(it)
        }

        cardData.vdXml?.let {
            appendLine()
            appendLine("=== VD (Versicherungsdaten) ===")
            appendLine(it)
        }
    }

    override fun onPause() {
        super.onPause()
        nfcSession.cancel()
    }

    override fun onDestroy() {
        super.onDestroy()
        SmsReceiver.clearListener()
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (ev.action == MotionEvent.ACTION_DOWN) {
            val v = currentFocus
            if (v is EditText) {
                val outRect = Rect()
                v.getGlobalVisibleRect(outRect)
                if (!outRect.contains(ev.rawX.toInt(), ev.rawY.toInt())) {
                    v.clearFocus()
                    val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
                    imm.hideSoftInputFromWindow(v.windowToken, 0)
                }
            }
        }
        return super.dispatchTouchEvent(ev)
    }

    private fun ByteArray.toHexString(): String =
        joinToString("") { "%02x".format(it) }
            .chunked(64)
            .joinToString("\n")
}
