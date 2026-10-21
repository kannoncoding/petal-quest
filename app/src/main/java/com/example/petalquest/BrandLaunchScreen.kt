package com.example.petalquest

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp

/** The approved prototype branding, with no onboarding copy or controls. */
@Composable
internal fun BrandLaunchScreen() {
    BoxWithConstraints(
        modifier = Modifier.fillMaxSize().background(Color(0xFF101520))
            .safeDrawingPadding().padding(24.dp),
        contentAlignment = Alignment.Center
    ) {
        val logoSize = minOf(maxWidth, maxHeight, 342.dp)
        Image(
            painter = painterResource(R.drawable.petal_quest_teen_launcher_art),
            contentDescription = "Petal Quest Teen Version",
            contentScale = ContentScale.Fit,
            modifier = Modifier.width(logoSize).aspectRatio(1f)
        )
    }
}
