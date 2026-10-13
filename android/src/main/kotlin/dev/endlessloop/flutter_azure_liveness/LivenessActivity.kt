package dev.endlessloop.flutter_azure_liveness

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.MotionEvent
import android.window.OnBackInvokedDispatcher
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.platform.createLifecycleAwareWindowRecomposer
import kotlinx.coroutines.CoroutineExceptionHandler
import java.util.Locale

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
 *
 * Error codes set by this activity: `InvalidArguments`, `UserCanceled`,
 * `UserBackPressed` (Back or swipe-back, intercepted before the SDK sees it; see
 * [onUserBack]) and `SdkInternalError` (an exception escaped the SDK's Compose
 * tree during recomposition or from an effect coroutine; see
 * [onLivenessScreenFailure]).
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

        private const val TAG = "LivenessActivity"
        private const val ERROR_SDK_INTERNAL = "SdkInternalError"
        private const val ERROR_USER_BACK_PRESSED = "UserBackPressed"
        private const val MAX_ERROR_MESSAGE_LENGTH = 2000

        // Set by AzureLivenessPlugin before startActivityForResult so it is
        // available in attachBaseContext (called before onCreate/intent is set).
        @Volatile
        internal var pendingLocale: String? = null
    }

    override fun attachBaseContext(newBase: Context) {
        val locale = pendingLocale.also { pendingLocale = null }
        if (locale != null) {
            val localeObj = Locale.forLanguageTag(locale)
            val config = Configuration(newBase.resources.configuration)
            config.setLocale(localeObj)
            super.attachBaseContext(newBase.createConfigurationContext(config))
        } else {
            super.attachBaseContext(newBase)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val sessionToken = intent.getStringExtra(EXTRA_SESSION_TOKEN)
        if (sessionToken.isNullOrEmpty()) {
            finishWithError("InvalidArguments", "Missing sessionToken")
            return
        }

        val verifyImageBytes: ByteArray? = intent.getByteArrayExtra(EXTRA_VERIFY_IMAGE_BYTES)

        // PC-483: take Back before the SDK's own BackHandler (composed ~1 s later,
        // and whose stopAnalyze() can throw mid-start). PRIORITY_OVERLAY outranks
        // androidx's PRIORITY_DEFAULT callback. If the host app is not opted in to
        // predictive back the platform rejects this registration and Back arrives
        // through onBackPressed(), which is also ours.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_OVERLAY,
            ) { onUserBack() }
        }

        // Compose 1.7.4: createLifecycleAwareWindowRecomposer is
        // @ExperimentalComposeUiApi (stable in 1.9.x). Re-verify its behaviour and
        // Recomposer.processCompositionError's rethrow semantics on Compose upgrades
        // (see ADR pc-500).
        @OptIn(ExperimentalComposeUiApi::class)
        val recomposer = window.decorView.createLifecycleAwareWindowRecomposer(
            CoroutineExceptionHandler { _, throwable -> onLivenessScreenFailure(throwable) },
            lifecycle,
        )

        setContent(parent = recomposer) {
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
                        errorCode = error.livenessError.name,
                        errorMessage = error.recognitionError?.name ?:
         error.livenessError.name,
                    )
                },
            )
        }
    }

    /**
     * Receives throwables that escape the SDK's Compose tree during recomposition,
     * applyChanges or an effect coroutine (PC-500: Azure SDK 1.5.1 NullPointerException
     * in `AnalyzeScreenInternalKt$InnerAnalyzeScreen`). Without this handler the failed
     * recompose coroutine reaches the thread's uncaught-exception handler and kills the
     * process. It does not cover initial composition, measure/layout or input dispatch.
     *
     * Reports and closes: logs the throwable, then finishes with `SdkInternalError`.
     * Only the first result is delivered; later throwables are logged only.
     * May be invoked off the main thread, hence [runOnUiThread].
     */
    private fun onLivenessScreenFailure(throwable: Throwable) {
        Log.e(TAG, "Liveness screen threw; closing with $ERROR_SDK_INTERNAL", throwable)
        runOnUiThread {
            if (isFinishing || isDestroyed) return@runOnUiThread
            finishWithError(
                ERROR_SDK_INTERNAL,
                throwable.stackTraceToString().take(MAX_ERROR_MESSAGE_LENGTH),
            )
        }
    }

    /**
     * Back or swipe-back (PC-483). Closes with `UserBackPressed` without calling into
     * the SDK, so its `stopAnalyze()` (which throws if a single-shot start is in
     * flight) is never reached from Back. No-op once a result is being delivered.
     */
    private fun onUserBack() {
        if (isFinishing || isDestroyed) return
        Log.i(TAG, "Back pressed; closing with $ERROR_USER_BACK_PRESSED")
        finishWithError(ERROR_USER_BACK_PRESSED, "User pressed back")
    }

    // Back on non-predictive routes (Android <= 12, or a host app not opted in).
    // The SDK's handler is bypassed on purpose, hence no super call (PC-483).
    @Suppress("MissingSuperCall")
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        onUserBack()
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        return try {
            super.dispatchTouchEvent(ev)
        } catch (e: RuntimeException) {
            // Azure SDK throws the same RuntimeException as the back-press race
            // (VisionSessionJNI.sessionViewSingleShotStop) when the close (X)
            // button is tapped while a single-shot session is starting. The close
            // button is handled inside the SDK's own Compose UI (onCloseButtonClick),
            // so it never routes through onBackPressed(); the exception unwinds
            // synchronously through dispatchTouchEvent instead. Treat as cancellation.
            finishWithError("UserCanceled", "User cancelled liveness check")
            true
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
