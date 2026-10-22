package com.example.petalquest

import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import kotlinx.coroutines.delay

/** Celebration runs once for a newly observed server approval, never for local intent. */
@Composable
internal fun ConfirmedMascot(event: Int) {
 val context=LocalContext.current
 val lifecycle=(context as? ComponentActivity)?.lifecycle
 var resumed by remember { mutableStateOf(lifecycle?.currentState?.isAtLeast(Lifecycle.State.RESUMED)==true) }
 var reduced by rememberSaveable { mutableStateOf(false) }
 var frame by remember { mutableIntStateOf(-1) }
 val frames=remember { intArrayOf(R.drawable.pq_dog_celebrate_00,R.drawable.pq_dog_celebrate_01,R.drawable.pq_dog_celebrate_02,R.drawable.pq_dog_celebrate_03,R.drawable.pq_dog_celebrate_04,R.drawable.pq_dog_celebrate_05,R.drawable.pq_dog_celebrate_06,R.drawable.pq_dog_celebrate_07) }
 DisposableEffect(lifecycle) {
  val observer=LifecycleEventObserver { _, change -> resumed=change==Lifecycle.Event.ON_RESUME; if(!resumed) frame=-1 }
  lifecycle?.addObserver(observer)
  onDispose { lifecycle?.removeObserver(observer) }
 }
 LaunchedEffect(event) {
  frame=-1
  if(event>0 && resumed && !reduced && Settings.Global.getFloat(context.contentResolver,Settings.Global.ANIMATOR_DURATION_SCALE,1f)>0f) {
   for(i in frames.indices) {
    if(!resumed || reduced || Settings.Global.getFloat(context.contentResolver,Settings.Global.ANIMATOR_DURATION_SCALE,1f)<=0f) break
    frame=i;delay(125)
   }
   frame=-1
  }
 }
 Image(ImageBitmap.imageResource(if(frame in frames.indices) frames[frame] else R.drawable.pq_dog_static),"Petal Quest companion",Modifier.size(96.dp),filterQuality=FilterQuality.None)
 Row { Switch(reduced,{reduced=it;if(it) frame=-1});Text("Reduced motion") }
}
