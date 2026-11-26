package com.itsash.netlook

import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.InetAddress
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val io = Executors.newFixedThreadPool(32)
    private var lock: WifiManager.MulticastLock? = null
    private val nsdBrowsers = mutableSetOf<NsdBrowser>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.itsash.netlook/net")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "networkInfo" -> io.execute {
                        val m = try { NetInfoReader.read(this)?.toMap() } catch (_: Exception) { null }
                        runOnUiThread { result.success(m) }
                    }
                    "multicast" -> {
                        setMulticast(call.arguments as? Boolean ?: false)
                        result.success(null)
                    }
                    "ping" -> {
                        val ip = call.argument<String>("ip")
                        val timeout = call.argument<Int>("timeout") ?: 400
                        io.execute {
                            var ms = -1.0
                            try {
                                val t0 = System.nanoTime()
                                if (InetAddress.getByName(ip).isReachable(timeout)) {
                                    ms = (System.nanoTime() - t0) / 1_000_000.0
                                }
                            } catch (_: Exception) {
                            }
                            runOnUiThread { result.success(ms) }
                        }
                    }
                    "nsd" -> {
                        val types = call.argument<List<String>>("types") ?: emptyList()
                        val duration = (call.argument<Int>("duration") ?: 5000).toLong()
                        val browser = NsdBrowser(this)
                        nsdBrowsers.add(browser)
                        browser.browse(types, duration) { hits ->
                            nsdBrowsers.remove(browser)
                            result.success(hits)
                        }
                    }
                    "watch" -> {
                        NetWatch.configure(
                            this,
                            call.argument<Boolean>("enabled") ?: false,
                            call.argument<Int>("interval") ?: 60,
                            call.argument<String>("key") ?: "",
                            call.argument<List<String>>("known") ?: emptyList(),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun setMulticast(on: Boolean) {
        try {
            if (on) {
                if (lock == null) {
                    val wm = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
                    lock = wm.createMulticastLock("netlook").apply { setReferenceCounted(false) }
                }
                lock?.acquire()
            } else {
                lock?.release()
            }
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        for (browser in nsdBrowsers.toList()) {
            browser.stop()
        }
        nsdBrowsers.clear()
        io.shutdownNow()
        setMulticast(false)
        super.onDestroy()
    }
}
