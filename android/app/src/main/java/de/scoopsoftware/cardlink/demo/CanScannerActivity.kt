package de.scoopsoftware.cardlink.demo

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Activity that uses the camera and ML Kit OCR to scan the CAN (Card Access Number)
 * from an eGK card. Analyzes each frame for 6-digit numbers and uses consensus
 * (most common result from 10 readings) to determine the CAN.
 */
class CanScannerActivity : AppCompatActivity() {

    private lateinit var previewView: PreviewView
    private lateinit var statusText: TextView
    private lateinit var cameraExecutor: ExecutorService

    private val textRecognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

    // Consensus tracking - require 3 consecutive identical readings for fast, reliable detection
    private val detectedNumbers = mutableListOf<String>()
    private val requiredReadings = 3
    private val consensusRatio = 1.0f  // 100% consensus required

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_can_scanner)

        previewView = findViewById(R.id.previewView)
        statusText = findViewById(R.id.scannerStatusText)

        supportActionBar?.apply {
            title = "Scan CAN"
            setDisplayHomeAsUpEnabled(true)
        }

        cameraExecutor = Executors.newSingleThreadExecutor()

        if (hasCameraPermission()) {
            startCamera()
        } else {
            requestCameraPermission()
        }
    }

    private fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this, Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestCameraPermission() {
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.CAMERA),
            CAMERA_PERMISSION_REQUEST
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                startCamera()
            } else {
                Toast.makeText(this, "Camera permission required to scan CAN", Toast.LENGTH_LONG).show()
                finish()
            }
        }
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)

        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()

            val preview = Preview.Builder()
                .build()
                .also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }

            val imageAnalyzer = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also {
                    it.setAnalyzer(cameraExecutor, CanAnalyzer())
                }

            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            try {
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(
                    this, cameraSelector, preview, imageAnalyzer
                )
            } catch (e: Exception) {
                Log.e(TAG, "Camera binding failed", e)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private inner class CanAnalyzer : ImageAnalysis.Analyzer {
        @androidx.camera.core.ExperimentalGetImage
        override fun analyze(imageProxy: ImageProxy) {
            val mediaImage = imageProxy.image
            if (mediaImage != null) {
                val image = InputImage.fromMediaImage(
                    mediaImage,
                    imageProxy.imageInfo.rotationDegrees
                )

                textRecognizer.process(image)
                    .addOnSuccessListener { result ->
                        // Find all 6-digit numbers in the recognized text
                        val sixDigitPattern = Regex("\\b\\d{6}\\b")
                        val foundNumbers = sixDigitPattern.findAll(result.text)
                            .map { it.value }
                            .toList()

                        if (foundNumbers.isNotEmpty()) {
                            processDetectedNumbers(foundNumbers)
                        }
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "Text recognition failed", e)
                    }
                    .addOnCompleteListener {
                        imageProxy.close()
                    }
            } else {
                imageProxy.close()
            }
        }
    }

    private fun processDetectedNumbers(numbers: List<String>) {
        // Add all found 6-digit numbers to our collection
        detectedNumbers.addAll(numbers)

        // Update status
        val uniqueCount = detectedNumbers.groupingBy { it }.eachCount()
        val mostCommon = uniqueCount.maxByOrNull { it.value }

        runOnUiThread {
            if (mostCommon != null) {
                statusText.text = "Detected: ${mostCommon.key} (${mostCommon.value}/$requiredReadings)"
            }
        }

        // Check if we have enough readings
        if (detectedNumbers.size >= requiredReadings) {
            // Find the most common number
            val counts = detectedNumbers.groupingBy { it }.eachCount()
            val winner = counts.maxByOrNull { it.value }

            val minRequired = (requiredReadings * consensusRatio).toInt()
            if (winner != null && winner.value >= minRequired) {
                // We have a consensus
                returnResult(winner.key)
            } else {
                // No clear consensus, keep the most recent readings
                while (detectedNumbers.size > requiredReadings / 2) {
                    detectedNumbers.removeAt(0)
                }
            }
        }
    }

    private fun returnResult(can: String) {
        val resultIntent = Intent().apply {
            putExtra(EXTRA_CAN_RESULT, can)
        }
        setResult(Activity.RESULT_OK, resultIntent)
        finish()
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraExecutor.shutdown()
        textRecognizer.close()
    }

    companion object {
        private const val TAG = "CanScannerActivity"
        private const val CAMERA_PERMISSION_REQUEST = 100
        const val EXTRA_CAN_RESULT = "can_result"

        fun start(activity: Activity, requestCode: Int) {
            val intent = Intent(activity, CanScannerActivity::class.java)
            activity.startActivityForResult(intent, requestCode)
        }
    }
}
