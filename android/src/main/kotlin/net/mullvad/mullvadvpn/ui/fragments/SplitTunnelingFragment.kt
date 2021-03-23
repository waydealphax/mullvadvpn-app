package net.mullvad.mullvadvpn.ui.fragments

import android.os.Build
import android.os.Bundle
import android.view.KeyCharacterMap
import android.view.KeyEvent
import android.view.View
import android.view.ViewConfiguration
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.appbar.CollapsingToolbarLayout
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.consumeAsFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.onEach
import net.mullvad.mullvadvpn.R
import net.mullvad.mullvadvpn.applist.ViewIntent
import net.mullvad.mullvadvpn.di.APPS_SCOPE
import net.mullvad.mullvadvpn.model.ListItemData
import net.mullvad.mullvadvpn.ui.ListItemDividerDecoration
import net.mullvad.mullvadvpn.ui.ListItemListener
import net.mullvad.mullvadvpn.ui.ListItemsAdapter
import net.mullvad.mullvadvpn.util.setMargins
import net.mullvad.mullvadvpn.viewmodel.SplitTunnelingViewModel
import org.koin.android.ext.android.getKoin
import org.koin.androidx.viewmodel.ViewModelOwner
import org.koin.androidx.viewmodel.scope.viewModel
import org.koin.core.qualifier.named
import org.koin.core.scope.Scope

class SplitTunnelingFragment : BaseFragment(R.layout.collapsed_title_layout) {
    private val listItemsAdapter = ListItemsAdapter()

    private val scope: Scope = getKoin().createScope(APPS_SCOPE, named(APPS_SCOPE))
    private val viewModel by scope.viewModel<SplitTunnelingViewModel>(
        owner = {
            ViewModelOwner.from(this, this)
        }
    )
    private val toggleExcludeChannel = Channel<ListItemData>(Channel.BUFFERED)
    private val listItemListener = object : ListItemListener {
        override fun onItemAction(item: ListItemData) {
            toggleExcludeChannel.offer(item)
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        (view.findViewById(R.id.collapsing_toolbar) as CollapsingToolbarLayout).apply {
            title = resources.getString(R.string.split_tunneling)
        }
        listItemsAdapter.listItemListener = listItemListener
        listItemsAdapter.setHasStableIds(true)
        view.findViewById<RecyclerView>(R.id.recyclerView).apply {
            adapter = listItemsAdapter
            addItemDecoration(
                ListItemDividerDecoration(
                    topOffset = resources.getDimensionPixelSize(R.dimen.list_item_divider)
                )
            )
            tweakMargin(this)
        }
        view.findViewById<View>(R.id.back).setOnClickListener {
            requireActivity().onBackPressed()
        }

        lifecycleScope.launchWhenStarted {
            viewModel.listItems
                .onEach {
                    listItemsAdapter.setItems(it)
                }
                .catch { }
                .collect()
        }
        lifecycleScope.launchWhenResumed {
            // pass view intent to view model
            intents()
                .onEach { viewModel.processIntent(it) }
                .collect()
        }
    }

    override fun onStop() {
        super.onStop()
        view?.findViewById<RecyclerView>(R.id.recyclerView)?.adapter = null
    }

    override fun onDestroy() {
        listItemsAdapter.listItemListener = null
        scope.close()
        super.onDestroy()
    }

    private fun intents(): Flow<ViewIntent> = merge(
        transitionFinishedFlow.map { ViewIntent.ViewIsReady },
        toggleExcludeChannel.consumeAsFlow().map { ViewIntent.ChangeApplicationGroup(it) }
    )

    private fun tweakMargin(view: View) {
        if (!hasNavigationBar()) {
            view.setMargins(b = 0)
        }
    }

    private fun hasNavigationBar(): Boolean {
        // Emulator
        if (Build.FINGERPRINT.contains("generic")) {
            return true
        }

        val hasMenuKey = ViewConfiguration.get(requireContext()).hasPermanentMenuKey()
        val hasBackKey = KeyCharacterMap.deviceHasKey(KeyEvent.KEYCODE_BACK)
        val hasNoCapacitiveKeys = !hasMenuKey && !hasBackKey

        val id = resources.getIdentifier("config_showNavigationBar", "bool", "android")
        val hasOnScreenNavBar = id > 0 && resources.getBoolean(id)

        return hasOnScreenNavBar || hasNoCapacitiveKeys
    }
}
