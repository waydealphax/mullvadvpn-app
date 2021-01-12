package net.mullvad.mullvadvpn.service.endpoint

import android.os.Looper
import android.os.Messenger
import net.mullvad.mullvadvpn.ipc.DispatchingHandler
import net.mullvad.mullvadvpn.ipc.Request
import net.mullvad.mullvadvpn.service.MullvadDaemon
import net.mullvad.mullvadvpn.util.Intermittent

class ServiceEndpoint(looper: Looper, intermittentDaemon: Intermittent<MullvadDaemon>) {
    internal val dispatcher = DispatchingHandler(looper) { message ->
        Request.fromMessage(message)
    }

    val messenger = Messenger(dispatcher)

    val settingsListener = SettingsListener(intermittentDaemon)

    fun onDestroy() {
        dispatcher.onDestroy()
        settingsListener.onDestroy()
    }
}
