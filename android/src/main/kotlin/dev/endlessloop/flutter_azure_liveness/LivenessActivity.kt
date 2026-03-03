package dev.endlessloop.flutter_azure_liveness

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent

// Azure AI Vision Face Liveness SDK imports.
// These are available only after the gated Maven artifact is configured.
// See README for access instructions.
import com.azure.android.ai.vision.face.ui.FaceLivenessDetector
import com.azure.android.ai.vision.face.ui.LivenessDetectionError
import com.azure.android.ai.vision.face.ui.LivenessDetectionSuccess

/**
 * LivenessActivity
 *
 * A thin Jetpack Compose [ComponentActivity] that hosts [FaceLivenessDetector]
 * from the Azure AI Vision Face UI SDK.
 *
 * Extras in (from [AzureLivenessPlugin]):
 *   - [EXTRA_SESSION_TOKEN]          Required. Session authorisation token.
 *   - [EXTRA_VERIFY_IMAGE_BYTES]     Optional. Reference face image bytes for
 *                                    liveness-with-verify mode.
 *   - [EXTRA_DEVICE_CORRELATION_ID]  Optional. Caller-supplied diagnostic ID.
 *
 * Extras out (set before finish()):
 *   - On success  (RESULT_OK):       [RESULT_DIGEST], [RESULT_RESULT_ID]
 *   - On failure  (RESULT_CANCELED): [RESULT_ERROR_CODE], [RESULT_ERROR_MESSAGE]
 */
class LivenessActivity : ComponentActivity() {

    companion object {
        const val EXTRA_SESSION_TOKEN = "sessionToken"
        const val EXTRA_VERIFY_IMAGE_BYTES = "verifyImageBytes"
        const val EXTRA_DEVICE_CORRELATION_ID = "deviceCorrelationId"

        const val RESULT_DIGEST = "digest"
        const val RESULT_RESULT_ID = "resultId"
        const val RESULT_ERROR_CODE = "errorCode"
        const val RESULT_ERROR_MESSAGE = "errorMessage"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val sessionToken = intent.getStringExtra(EXTRA_SESSION_TOKEN)
        if (sessionToken.isNullOrEmpty()) {
            finishWithError("InvalidArguments", "Missing sessionToken")
            return
        }

        val verifyImageBytes: ByteArray? = intent.getByteArrayExtra(EXTRA_VERIFY_IMAGE_BYTES)

        setContent {
            FaceLivenessDetector(
                sessionAuthorizationToken = sessionToken,
                verifyImageFileContent = verifyImageBytes,
                onSuccess = { success: LivenessDetectionSuccess ->
                    finishWithSuccess(
                        digest = success.digest,
                        resultId = success.resultId,
                    )
                },
                onError = { error: LivenessDetectionError ->
                    finishWithError(
                        errorCode = error.kind.name,
                        errorMessage = error.message,
                    )
                },
            )
        }
    }

    private fun finishWithSuccess(digest: String, resultId: String?) {
        val intent = Intent().apply {
            putExtra(RESULT_DIGEST, digest)
            putExtra(RESULT_RESULT_ID, resultId)
        }
        setResult(Activity.RESULT_OK, intent)
        finish()
    }

    private fun finishWithError(errorCode: String, errorMessage: String?) {
        val intent = Intent().apply {
            putExtra(RESULT_ERROR_CODE, errorCode)
            putExtra(RESULT_ERROR_MESSAGE, errorMessage)
        }
        setResult(Activity.RESULT_CANCELED, intent)
        finish()
    }
}
