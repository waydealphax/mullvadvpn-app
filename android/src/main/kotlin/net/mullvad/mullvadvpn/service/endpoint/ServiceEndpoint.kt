package net.mullvad.mullvadvpn.service.endpoint

import android.os.DeadObjectException
import android.os.Looper
import android.os.Messenger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ClosedReceiveChannelException
import kotlinx.coroutines.channels.SendChannel
import kotlinx.coroutines.channels.actor
import kotlinx.coroutines.channels.sendBlocking
import net.mullvad.mullvadvpn.ipc.DispatchingHandler
import net.mullvad.mullvadvpn.ipc.Event
import net.mullvad.mullvadvpn.ipc.Request
import net.mullvad.mullvadvpn.service.MullvadDaemon
import net.mullvad.mullvadvpn.util.Intermittent
import net.mullvad.talpid.ConnectivityListener

class ServiceEndpoint(
    looper: Looper,
    internal val intermittentDaemon: Intermittent<MullvadDaemon>,
    val connectivityListener: ConnectivityListener
) {
    private val listeners = mutableSetOf<Messenger>()
    private val registrationQueue: SendChannel<Messenger> = startRegistrator()

    internal val dispatcher = DispatchingHandler(looper) { message ->
        Request.fromMessage(message)
    }

    val messenger = Messenger(dispatcher)

    val settingsListener = SettingsListener(this)

    val keyStatusListener = KeyStatusListener(this)
    val locationInfoCache = LocationInfoCache(this)

    init {
        dispatcher.registerHandler(Request.RegisterListener::class) { request ->
            registrationQueue.sendBlocking(request.listener)
        }
    }

    fun onDestroy() {
        dispatcher.onDestroy()
        registrationQueue.close()

        keyStatusListener.onDestroy()
        locationInfoCache.onDestroy()
        settingsListener.onDestroy()
    }

    internal fun sendEvent(event: Event) {
        synchronized(this) {
            val deadListeners = mutableSetOf<Messenger>()

            for (listener in listeners) {
                try {
                    listener.send(event.message)
                } catch (_: DeadObjectException) {
                    deadListeners.add(listener)
                }
            }

            deadListeners.forEach { listeners.remove(it) }
        }
    }

    private fun startRegistrator() = GlobalScope.actor<Messenger>(
        Dispatchers.Default,
        Channel.UNLIMITED
    ) {
        try {
            while (true) {
                val listener = channel.receive()

                intermittentDaemon.await()

                registerListener(listener)
            }
        } catch (exception: ClosedReceiveChannelException) {
            // Registration queue closed; stop registrator
        }
    }

    private fun registerListener(listener: Messenger) {
        synchronized(this) {
            listeners.add(listener)

            val initialEvents = listOf(
                Event.SettingsUpdate(settingsListener.settings),
                Event.NewLocation(locationInfoCache.location),
                Event.WireGuardKeyStatus(keyStatusListener.keyStatus),
                Event.ListenerReady
            )

            initialEvents.forEach { event ->
                listener.send(event.message)
            }
        }
    }
}
