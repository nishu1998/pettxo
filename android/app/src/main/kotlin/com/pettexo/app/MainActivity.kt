package com.pettexo.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
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
