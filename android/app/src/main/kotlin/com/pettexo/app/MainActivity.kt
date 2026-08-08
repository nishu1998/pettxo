package com.pettexo.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var deepLinkEventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pettexo.app/social_post_deep_links",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> result.success(intent?.dataString)
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pettexo.app/social_post_deep_links/events",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                deepLinkEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                deepLinkEventSink = null
            }
        })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = intent.dataString ?: return
        deepLinkEventSink?.success(link)
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .build()
        val channels = listOf(
            NotificationChannel(
                "pettxo_general_notifications",
                "Pettxo Alerts",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Booking and social updates from Pettxo."
                enableVibration(true)
                setShowBadge(true)
                setSound(soundUri, audioAttributes)
            },
            NotificationChannel(
                "pettxo_chat_messages",
                "\uD83D\uDCAC Chat Messages",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Direct chat and provider/customer messages."
                enableVibration(true)
                setShowBadge(true)
                setSound(soundUri, audioAttributes)
            },
            NotificationChannel(
                "pettxo_bookings_payments",
                "\uD83D\uDCC5 Bookings & Payments",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Booking requests, booking updates, and payment alerts."
                enableVibration(true)
                setShowBadge(true)
                setSound(soundUri, audioAttributes)
            },
            NotificationChannel(
                "pettxo_social_activity",
                "❤️ Social Activity",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Likes, comments, follows, and social activity."
                enableVibration(true)
                setShowBadge(true)
                setSound(soundUri, audioAttributes)
            },
            NotificationChannel(
                "pettxo_other_updates",
                "\uD83D\uDCE2 Other Updates",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Announcements, promotions, and other Pettxo updates."
                enableVibration(true)
                setShowBadge(true)
                setSound(soundUri, audioAttributes)
            },
        )

        val manager = getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannels(channels)
    }
}
