package com.petalquest.parent
import android.os.Bundle
import android.view.WindowManager
import androidx.compose.foundation.layout.*
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.runtime.remember
import com.petalquest.core.model.ServiceConfig
import com.petalquest.core.data.LocalData
import com.petalquest.core.ui.FamilyAccessScreen
class MainActivity : ComponentActivity() {
 private val localData by lazy { LocalData.getInstance(this) }
 override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState)
 window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
 setContent { MaterialTheme { Scaffold { inset -> Column(Modifier.padding(inset)) { ParentPushSetup(); FamilyAccessScreen(true, ServiceConfig(BuildConfig.SERVICE_URL, BuildConfig.SERVICE_PUBLIC_KEY, BuildConfig.BUILD_TYPE), localData, Modifier.weight(1f)) } } } }
 }
}
