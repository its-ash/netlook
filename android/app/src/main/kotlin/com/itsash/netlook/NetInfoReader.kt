package com.itsash.netlook

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import java.net.Inet4Address

/** Reads IP, prefix, gateway and DNS of the Wi-Fi network from LinkProperties. */
object NetInfoReader {
    data class Info(
        val ip: String,
        val prefix: Int,
        val gateway: String?,
        val dns: List<String>,
        val ssid: String?,
        val isWifi: Boolean,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "ip" to ip, "prefix" to prefix, "gateway" to gateway,
            "dns" to dns, "ssid" to ssid, "isWifi" to isWifi,
        )
    }

    @Suppress("DEPRECATION")
    fun read(ctx: Context): Info? {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        var net: Network? = null
        for (n in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(n) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                net = n
                break
            }
        }
        if (net == null) net = cm.activeNetwork
        if (net == null) return null
        val lp = cm.getLinkProperties(net) ?: return null
        val addr = lp.linkAddresses.firstOrNull {
            it.address is Inet4Address && !it.address.isLoopbackAddress
        } ?: return null
        val gateway = lp.routes
            .firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }
            ?.gateway?.hostAddress
        val dns = lp.dnsServers.filterIsInstance<Inet4Address>().mapNotNull { it.hostAddress }
        val isWifi = cm.getNetworkCapabilities(net)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        return Info(addr.address.hostAddress ?: return null, addr.prefixLength, gateway, dns, if (isWifi) ssid(ctx) else null, isWifi)
    }

    /** The SSID is only returned when location permission is granted. */
    @Suppress("DEPRECATION")
    private fun ssid(ctx: Context): String? {
        if (ctx.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) return null
        val wm = ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val raw = wm.connectionInfo?.ssid ?: return null
        val s = raw.trim('"')
        return if (s.isEmpty() || s == "<unknown ssid>" || s == "0x") null else s
    }
}
