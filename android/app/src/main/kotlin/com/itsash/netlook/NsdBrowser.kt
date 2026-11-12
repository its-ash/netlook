package com.itsash.netlook

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import java.net.Inet4Address

/** Browses DNS-SD service types for a fixed time and resolves each hit to an IPv4 address. */
class NsdBrowser(ctx: Context) {
    private val nsd = ctx.applicationContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val main = Handler(Looper.getMainLooper())

    // All state below is touched on the main thread only.
    private val queue = ArrayDeque<Pair<String, NsdServiceInfo>>()
    private val results = mutableListOf<Map<String, Any?>>()
    private val listeners = mutableListOf<NsdManager.DiscoveryListener>()
    private var resolving = false
    private var finished = false

    @Suppress("DEPRECATION")
    fun browse(types: List<String>, durationMs: Long, done: (List<Map<String, Any?>>) -> Unit) {
        for (type in types) {
            val l = object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(serviceType: String) {}
                override fun onDiscoveryStopped(serviceType: String) {}
                override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
                override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
                override fun onServiceLost(serviceInfo: NsdServiceInfo) {}
                override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                    main.post {
                        if (finished) return@post
                        queue.addLast(type to serviceInfo)
                        resolveNext()
                    }
                }
            }
            try {
                nsd.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, l)
                listeners.add(l)
            } catch (_: Exception) {
            }
        }
        main.postDelayed({
            finished = true
            for (l in listeners) {
                try {
                    nsd.stopServiceDiscovery(l)
                } catch (_: Exception) {
                }
            }
            done(results.toList())
        }, durationMs)
    }

    @Suppress("DEPRECATION")
    private fun resolveNext() {
        if (resolving || finished) return
        val (type, info) = queue.removeFirstOrNull() ?: return
        resolving = true
        try {
            nsd.resolveService(info, object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    main.post { resolving = false; resolveNext() }
                }

                override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                    main.post {
                        val host = serviceInfo.host
                        if (host is Inet4Address && !finished) {
                            results.add(mapOf("ip" to host.hostAddress, "name" to serviceInfo.serviceName, "type" to type))
                        }
                        resolving = false
                        resolveNext()
                    }
                }
            })
        } catch (_: Exception) {
            resolving = false
            resolveNext()
        }
    }
}
