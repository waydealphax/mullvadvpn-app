package net.mullvad.talpid.util

import kotlin.properties.Delegates.observable

// Implementation of `EventSubscriber` to allow notifying listeners of events
//
// Provides a `notify` method that allows notifying all subscribed listeners of an event of type T.
// It also provides a helper `notifiable` method that returns a property delegate that calls
// `notify` when the value is set.
class EventNotifier<T>(private val initialValue: T) : EventSubscriber<T>(initialValue) {
    fun notify(event: T) {
        notifyListeners(event)
    }

    fun notifiable() = observable(latestEvent) { _, _, newValue ->
        notify(newValue)
    }
}

fun <T> autoSubscribable(id: Any, fallback: T, listener: (T) -> Unit) =
    observable<EventNotifier<T>?>(null) { _, old, new ->
        if (old != new) {
            old?.unsubscribe(id)

            if (new == null) {
                listener.invoke(fallback)
            } else {
                new.subscribe(id, listener)
            }
        }
    }
