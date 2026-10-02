package com.yemenfast.wasel

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val SETTINGS_CHANNEL = "wasel/android_settings"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WaselNotificationListener.EVENT_CHANNEL,
        ).setStreamHandler(WaselNotificationListener)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SETTINGS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "openNotificationListenerSettings") {
                startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        WaselNotificationListener.clearSink()
        super.onDestroy()
    }
}
