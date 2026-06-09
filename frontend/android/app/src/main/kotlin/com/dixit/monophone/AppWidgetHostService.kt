package com.dixit.monophone

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Manages hosting of third-party Android AppWidgets within the launcher panel.
 *
 * Requirements:
 *   - Android 12+ (API 31+) for official AppWidget host support.
 *   - BIND_APPWIDGET permission (system-granted for launchers).
 */
class AppWidgetHostManager(private val context: Context) {

    companion object {
        private const val TAG = "AppWidgetHostMgr"
        private const val HOST_ID = 0x0B0B // Unique host ID

        var instance: AppWidgetHostManager? = null
            private set
    }

    private val appWidgetManager: AppWidgetManager =
        AppWidgetManager.getInstance(context)

    private val appWidgetHost: AppWidgetHost = AppWidgetHost(
        context,
        HOST_ID
    )

    /** Map of bound widget IDs to metadata for Flutter communication */
    private val boundWidgets = mutableMapOf<Int, Map<String, Any?>>()

    init {
        instance = this
    }

    /**
     * Returns a list of all available (installed) AppWidget providers.
     * Each entry contains: packageName, label, preview image info, etc.
     */
    fun getAvailableWidgetProviders(): List<Map<String, Any?>> {
        val providers = appWidgetManager.getInstalledProviders()
        return providers.mapNotNull { info ->
            try {
                val pkg = info.provider.packageName
                val label = info.loadLabel(context.packageManager)
                mapOf(
                    "providerName" to info.provider.flattenToShortString(),
                    "packageName" to pkg,
                    "label" to label,
                    "minWidth" to info.minWidth,
                    "minHeight" to info.minHeight,
                    "description" to (info.loadDescription(context) ?: ""),
                )
            } catch (e: Exception) {
                Log.w(TAG, "Error loading provider info", e)
                null
            }
        }
    }

    /**
     * Get currently bound app widget IDs and their provider info.
     */
    fun getBoundWidgets(): List<Map<String, Any?>> {
        return boundWidgets.values.toList()
    }

    /**
     * Find the AppWidgetProviderInfo for a given component name from
     * the list of installed widget providers.
     */
    private fun findWidgetProvider(component: ComponentName): AppWidgetProviderInfo? {
        return try {
            appWidgetManager.getInstalledProviders().find { info ->
                info.provider == component
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error finding widget provider", e)
            null
        }
    }

    /**
     * Request to bind + create an AppWidget from a provider.
     *
     * Since Android Q+, binding requires either:
     *   - The app being the default launcher (which we are)
     *   - User consent via a permission activity
     */
    fun requestBindWidget(
        providerName: String,
        result: MethodChannel.Result,
        activity: Activity?,
    ) {
        try {
            val component = ComponentName.unflattenFromString(providerName)
                ?: run {
                    result.error("INVALID_PROVIDER", "Could not parse provider", null)
                    return
                }

            val info = findWidgetProvider(component)
            if (info == null) {
                result.error("NO_INFO", "Widget provider not found", null)
                return
            }

            // Allocate a new widget ID from the host
            val appWidgetId = appWidgetHost.allocateAppWidgetId()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val success = appWidgetManager.bindAppWidgetIdIfAllowed(
                    appWidgetId,
                    component
                )
                if (success) {
                    onWidgetBound(appWidgetId, info)
                    result.success(mapOf(
                        "appWidgetId" to appWidgetId,
                        "providerName" to providerName,
                        "label" to info.loadLabel(context.packageManager),
                    ))
                } else {
                    // Need to request permission via intent
                    val intent = Intent(AppWidgetManager.ACTION_APPWIDGET_BIND).apply {
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, component)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    activity?.startActivityForResult(intent, HOST_ID)
                    result.success(mapOf(
                        "appWidgetId" to appWidgetId,
                        "providerName" to providerName,
                        "requiresPermission" to true,
                    ))
                }
            } else {
                // Pre-Q: direct binding
                appWidgetManager.bindAppWidgetIdIfAllowed(appWidgetId, component)
                onWidgetBound(appWidgetId, info)
                result.success(mapOf(
                    "appWidgetId" to appWidgetId,
                    "providerName" to providerName,
                ))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to bind widget", e)
            result.error("BIND_FAILED", e.message ?: "Unknown error", null)
        }
    }

    /**
     * Remove a bound AppWidget by its ID.
     */
    fun removeWidget(appWidgetId: Int) {
        try {
            appWidgetHost.deleteAppWidgetId(appWidgetId)
            boundWidgets.remove(appWidgetId)
        } catch (e: Exception) {
            Log.w(TAG, "Error removing widget $appWidgetId", e)
        }
    }

    /**
     * Start listening for widget updates.
     */
    fun startListening() {
        appWidgetHost.startListening()
    }

    /**
     * Stop listening for widget updates.
     */
    fun stopListening() {
        appWidgetHost.stopListening()
    }

    /**
     * Create an AppWidgetHostView for a given widget ID.
     * This returns the actual Android widget view that can be embedded.
     */
    fun createViewForWidget(appWidgetId: Int): AppWidgetHostView? {
        return try {
            val info = appWidgetManager.getAppWidgetInfo(appWidgetId) ?: return null
            val view = appWidgetHost.createView(context, appWidgetId, info)
            view.setAppWidget(appWidgetId, info)
            view
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create widget view", e)
            null
        }
    }

    /**
     * Clean up all hosted widgets.
     */
    fun dispose() {
        stopListening()
        boundWidgets.keys.forEach { id ->
            try {
                appWidgetHost.deleteAppWidgetId(id)
            } catch (_: Exception) { }
        }
        boundWidgets.clear()
        instance = null
    }

    // ── Private helpers ──────────────────────────────────────────

    private fun onWidgetBound(appWidgetId: Int, info: AppWidgetProviderInfo) {
        val label = info.loadLabel(context.packageManager)
        boundWidgets[appWidgetId] = mapOf(
            "appWidgetId" to appWidgetId,
            "providerName" to info.provider.flattenToShortString(),
            "label" to label,
            "packageName" to info.provider.packageName,
        )
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == HOST_ID) {
            if (resultCode == Activity.RESULT_OK) {
                val appWidgetId = data?.getIntExtra(
                    AppWidgetManager.EXTRA_APPWIDGET_ID,
                    -1
                ) ?: -1
                if (appWidgetId > 0) {
                    val info = appWidgetManager.getAppWidgetInfo(appWidgetId)
                    if (info != null) {
                        onWidgetBound(appWidgetId, info)
                    }
                }
            }
            // Notify Flutter channel of result
            MainActivity.channel?.invokeMethod("onWidgetBindResult", mapOf(
                "resultCode" to resultCode,
            ))
        }
    }
}

class AppWidgetPlatformView(
    private val context: Context,
    private val appWidgetId: Int
) : PlatformView {
    private val view: android.appwidget.AppWidgetHostView? =
        AppWidgetHostManager.instance?.createViewForWidget(appWidgetId)

    override fun getView(): android.view.View =
        view ?: android.widget.TextView(context).apply { text = "Widget unavailable" }

    override fun dispose() {}
}

class AppWidgetPlatformViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val appWidgetId = (params?.get("appWidgetId") as? Number)?.toInt() ?: -1
        return AppWidgetPlatformView(context, appWidgetId)
    }
}