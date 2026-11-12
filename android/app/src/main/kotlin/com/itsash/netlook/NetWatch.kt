package com.itsash.netlook

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Notification
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Settings and scheduling for the periodic new-device check. */
object NetWatch {
    private const val WORK = "netlook_watch"
    private const val PREFS = "netlook_watch"

    fun configure(ctx: Context, enabled: Boolean, interval: Int, key: String, known: List<String>) {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val alerted = (p.getStringSet("alerted", emptySet()) ?: emptySet()).toMutableSet()
        // A device the user marked known no longer counts as alerted.
        val sameNet = p.getString("key", null) == key
        if (!sameNet) alerted.clear() else alerted.removeAll(known.toSet())
        p.edit()
            .putBoolean("enabled", enabled)
            .putString("key", key)
            .putStringSet("known", known.toSet())
            .putStringSet("alerted", alerted)
            .apply()
        val wm = WorkManager.getInstance(ctx)
        if (!enabled) {
            wm.cancelUniqueWork(WORK)
            return
        }
        val req = PeriodicWorkRequestBuilder<WatchWorker>(maxOf(interval, 15).toLong(), TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.UNMETERED).build())
            .build()
        wm.enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.UPDATE, req)
    }

    fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

class WatchWorker(private val ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    private val ports = intArrayOf(80, 443, 22, 53, 445, 139, 554, 8008, 8009, 62078, 7000, 9100)

    override fun doWork(): Result {
        val p = NetWatch.prefs(ctx)
        if (!p.getBoolean("enabled", false)) return Result.success()
        val info = NetInfoReader.read(ctx) ?: return Result.success()
        if (!info.isWifi) return Result.success()
        val ip = ipToInt(info.ip)
        val mask = if (info.prefix == 0) 0 else (-1 shl (32 - info.prefix))
        val net = ip and mask
        // Same key format as the Dart side: network/prefix.
        if (intToIp(net) + "/" + info.prefix != p.getString("key", null)) return Result.success()

        // Same cap as the app: never wider than /22, narrowed around this phone.
        val scanPrefix = maxOf(info.prefix, 22)
        val scanMask = -1 shl (32 - scanPrefix)
        val first = (ip and scanMask) + 1
        val last = (ip and scanMask) + (scanMask.inv()) - 1
        val alive = ConcurrentHashMap.newKeySet<String>()
        val pool = Executors.newFixedThreadPool(32)
        var i = first.toLong() and 0xFFFFFFFFL
        val end = last.toLong() and 0xFFFFFFFFL
        while (i <= end) {
            val target = intToIp(i.toInt())
            pool.execute { if (probe(target)) alive.add(target) }
            i++
        }
        pool.shutdown()
        if (!pool.awaitTermination(8, TimeUnit.MINUTES)) pool.shutdownNow()
        if (isStopped) return Result.success()

        val known = p.getStringSet("known", emptySet()) ?: emptySet()
        val alerted = (p.getStringSet("alerted", emptySet()) ?: emptySet()).toMutableSet()
        val fresh = alive.filter { it != info.ip && it != info.gateway && it !in known && it !in alerted }.sortedBy { ipToInt(it).toLong() and 0xFFFFFFFFL }
        if (fresh.isNotEmpty()) {
            alerted.addAll(fresh)
            p.edit().putStringSet("alerted", alerted).apply()
            notify(fresh)
        }
        return Result.success()
    }

    private fun probe(ip: String): Boolean {
        try {
            if (InetAddress.getByName(ip).isReachable(300)) return true
        } catch (_: Exception) {
        }
        for (port in ports) {
            try {
                Socket().use { it.connect(InetSocketAddress(ip, port), 250) }
                return true
            } catch (e: java.net.ConnectException) {
                // Refused still means a host is there.
                if (e.message?.contains("refused", ignoreCase = true) == true) return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    private fun notify(fresh: List<String>) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel("new_devices", "New devices", NotificationManager.IMPORTANCE_DEFAULT))
        val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        val pi = PendingIntent.getActivity(ctx, 0, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val title = if (fresh.size == 1) "New device on your Wi-Fi" else "${fresh.size} new devices on your Wi-Fi"
        val text = fresh.take(4).joinToString(", ") + if (fresh.size > 4) " and ${fresh.size - 4} more" else ""
        val n = Notification.Builder(ctx, "new_devices")
            .setSmallIcon(R.drawable.ic_stat_netlook)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build()
        nm.notify(1001, n)
    }

    private fun ipToInt(s: String): Int {
        val b = InetAddress.getByName(s).address
        return ((b[0].toInt() and 255) shl 24) or ((b[1].toInt() and 255) shl 16) or ((b[2].toInt() and 255) shl 8) or (b[3].toInt() and 255)
    }

    private fun intToIp(v: Int) = "${(v ushr 24) and 255}.${(v ushr 16) and 255}.${(v ushr 8) and 255}.${v and 255}"
}
