package net.mullvad.mullvadvpn.service

import net.mullvad.mullvadvpn.model.DnsOptions
import net.mullvad.mullvadvpn.model.RelaySettings
import net.mullvad.mullvadvpn.model.Settings
import net.mullvad.talpid.util.EventNotifier
import net.mullvad.talpid.util.EventSubscriber

class SettingsListener(val daemon: MullvadDaemon, val initialSettings: Settings) {
    var settings: Settings = initialSettings
        private set(value) {
            settingsNotifier.notify(value)
            field = value
        }

    private val accountNumberNotifier = EventNotifier(initialSettings.accountToken)
    private val dnsOptionsNotifier = EventNotifier(initialSettings.tunnelOptions.dnsOptions)
    private val settingsNotifier: EventNotifier<Settings> = EventNotifier(settings)

    val onAccountNumberChange: EventSubscriber<String?> by ::accountNumberNotifier
    val onDnsOptionsChange: EventSubscriber<DnsOptions> by ::dnsOptionsNotifier
    val onSettingsChange: EventSubscriber<Settings> by ::settingsNotifier

    var onRelaySettingsChange: ((RelaySettings?) -> Unit)? = null
        set(value) {
            synchronized(this) {
                field = value
                value?.invoke(settings.relaySettings)
            }
        }

    init {
        daemon.onSettingsChange.subscribe(this) { maybeSettings ->
            maybeSettings?.let { settings -> handleNewSettings(settings) }
        }
    }

    fun onDestroy() {
        daemon.onSettingsChange.unsubscribe(this)

        accountNumberNotifier.unsubscribeAll()
        settingsNotifier.unsubscribeAll()
    }

    private fun handleNewSettings(newSettings: Settings) {
        synchronized(this) {
            if (settings.accountToken != newSettings.accountToken) {
                accountNumberNotifier.notify(newSettings.accountToken)
            }

            if (settings.tunnelOptions.dnsOptions != newSettings.tunnelOptions.dnsOptions) {
                dnsOptionsNotifier.notify(newSettings.tunnelOptions.dnsOptions)
            }

            if (settings.relaySettings != newSettings.relaySettings) {
                onRelaySettingsChange?.invoke(newSettings.relaySettings)
            }

            settings = newSettings
        }
    }
}
