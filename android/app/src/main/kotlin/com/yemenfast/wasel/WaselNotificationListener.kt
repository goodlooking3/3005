package com.yemenfast.wasel

import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel

class WaselNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val extras = sbn.notification.extras
        val title = extras.getString("android.title")?.trim().orEmpty()
        val text = extras.getCharSequence("android.text")?.toString()?.trim().orEmpty()
        if (title.isBlank() || text.isBlank()) return
        val event = mapOf(
            "packageName" to sbn.packageName,
            "title" to title,
            "body" to text,
            "receivedAt" to System.currentTimeMillis(),
        )
        Handler(Looper.getMainLooper()).post { eventSink?.success(event) }
    }

    companion object : EventChannel.StreamHandler {
        const val EVENT_CHANNEL = "wasel/android_notifications"
        private var eventSink: EventChannel.EventSink? = null

        override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
            eventSink = sink
        }

        override fun onCancel(arguments: Any?) {
            eventSink = null
        }

        fun clearSink() {
            eventSink = null
        }
    }
}
