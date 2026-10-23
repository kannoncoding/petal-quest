package com.petalquest.core.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.petalquest.core.sync.FamilySync

/** Requests a fresh read after returning from another app; never dispatches queued mutations. */
@Composable
fun FamilyForegroundRefresh(onBackground: () -> Unit, onReturn: () -> Unit) {
    val lifecycle = (LocalContext.current as? LifecycleOwner)?.lifecycle
    val background = rememberUpdatedState(onBackground)
    val returned = rememberUpdatedState(onReturn)
    DisposableEffect(lifecycle) {
        var wasAway = false
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) {
                FamilySync.get()?.onBackground()
                wasAway = true
                background.value()
            } else if (event == Lifecycle.Event.ON_RESUME) {
                FamilySync.get()?.onForeground()
                if(wasAway) { wasAway = false; returned.value() }
            }
        }
        lifecycle?.addObserver(observer)
        if(lifecycle?.currentState?.isAtLeast(Lifecycle.State.RESUMED)==true) FamilySync.get()?.onForeground()
        onDispose { lifecycle?.removeObserver(observer); FamilySync.get()?.onBackground() }
    }
}
