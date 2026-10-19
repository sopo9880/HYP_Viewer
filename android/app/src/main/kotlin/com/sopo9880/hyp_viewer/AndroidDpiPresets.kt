package com.sopo9880.hyp_viewer

/**
 * The UI uses the same five user-facing preset names as Windows GoodbyeDPI.
 * ByeDPI's native switches are NOT interchangeable with GoodbyeDPI's:
 * -H filters by hostname, -s splits the first TLS/HTTP payload, -d reorders,
 * -q uses out-of-band reverse data, and -M applies HTTP Host-case tricks.
 * DNS routing is performed by AndroidDpiVpnService when VPN is active.
 */
internal object AndroidDpiPresets {
    val names = setOf(
        "russia_blacklist", "russia_blacklist_dnsredir",
        "all", "all_dnsredir", "all_dnsredir_hardcore"
    )

    fun usesBlacklist(preset: String): Boolean =
        preset == "russia_blacklist" ||
        preset == "russia_blacklist_dnsredir"

    fun usesAlternativeDns(preset: String): Boolean =
        preset.endsWith("_dnsredir") || preset == "all_dnsredir_hardcore"

    fun proxyOptions(preset: String, blacklistPath: String?): List<String> {
        require(preset in names) { "Unknown Android DPI preset" }
        val options = mutableListOf("-s", "1")
        if (usesBlacklist(preset)) {
            require(!blacklistPath.isNullOrBlank()) { "Verified blacklist missing" }
            options.addAll(listOf("-H", blacklistPath))
        }
        if (preset == "all_dnsredir_hardcore") {
            options.addAll(listOf("-d", "3", "-q", "1", "-M", "h"))
        }
        return options
    }
}
