package dev.endlessloop.flutter_azure_liveness

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * AzureLivenessPlugin
 *
 * Bridges Flutter's MethodChannel to the native [LivenessActivity] that hosts
 * the Azure AI Vision Face Liveness SDK UI.
 */
class AzureLivenessPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {

    companion object {
        const val CHANNEL = "azure_liveness"
        private const val REQUEST_LIVENESS = 10001
    }

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    /** Holds the pending Flutter result while the native Activity is running. */
    private var pendingResult: Result? = null

    // -------------------------------------------------------------------------
    // FlutterPlugin
    // -------------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // -------------------------------------------------------------------------
    // ActivityAware
    // -------------------------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        teardownActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        teardownActivity()
    }

    private fun teardownActivity() {
        activityBinding?.removeActivityResultListener(this)
        activity = null
        activityBinding = null
    }

    // -------------------------------------------------------------------------
    // MethodCallHandler
    // -------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startLivenessCheck" -> handleStartLivenessCheck(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleStartLivenessCheck(call: MethodCall, result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Plugin is not attached to an Activity.", null)
            return
        }
        if (pendingResult != null) {
            result.error("ALREADY_RUNNING", "A liveness check is already in progress.", null)
            return
        }

        val sessionToken = call.argument<String>("sessionToken")
        if (sessionToken.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "sessionToken is required.", null)
            return
        }

        pendingResult = result

        LivenessActivity.pendingLocale = call.argument<String>("locale")

        val intent = Intent(currentActivity, LivenessActivity::class.java).apply {
            putExtra(LivenessActivity.EXTRA_SESSION_TOKEN, sessionToken)
            call.argument<ByteArray>("verifyImageBytes")?.let {
                putExtra(LivenessActivity.EXTRA_VERIFY_IMAGE_BYTES, it)
            }
            call.argument<String>("deviceCorrelationId")?.let {
                putExtra(LivenessActivity.EXTRA_DEVICE_CORRELATION_ID, it)
            }
        }

        @Suppress("DEPRECATION")
        currentActivity.startActivityForResult(intent, REQUEST_LIVENESS)
    }

    // -------------------------------------------------------------------------
    // ActivityResultListener
    // -------------------------------------------------------------------------

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_LIVENESS) return false

        val pending = pendingResult ?: return false
        pendingResult = null

        if (resultCode == Activity.RESULT_OK && data != null) {
            val digest = data.getStringExtra(LivenessActivity.RESULT_DIGEST) ?: ""
            val resultId = data.getStringExtra(LivenessActivity.RESULT_RESULT_ID)
            pending.success(
                mapOf(
                    "success" to true,
                    "digest" to digest,
                    "resultId" to resultId,
                )
            )
        } else {
            val errorCode = data?.getStringExtra(LivenessActivity.RESULT_ERROR_CODE) ?: "UserCanceled"
            val errorMessage = data?.getStringExtra(LivenessActivity.RESULT_ERROR_MESSAGE)
            pending.success(
                mapOf(
                    "success" to false,
                    "errorCode" to errorCode,
                    "errorMessage" to errorMessage,
                )
            )
        }

        return true
    }
}
