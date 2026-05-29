package de.scoopsoftware.cardlink.demo.ui

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import de.scoopsoftware.cardlink.demo.BuildConfig
import de.scoopsoftware.cardlink.demo.ui.model.ScanHistory
import de.scoopsoftware.cardlink.demo.ui.screens.ChartsScreen
import de.scoopsoftware.cardlink.demo.ui.screens.PoppScreen
import de.scoopsoftware.cardlink.demo.ui.screens.ScanScreen
import de.scoopsoftware.cardlink.demo.ui.screens.SettingsScreen
import de.scoopsoftware.cardlink.demo.ui.screens.UploadScreen

/**
 * Bottom navigation destinations.
 */
sealed class Screen(val route: String, val title: String, val icon: ImageVector) {
    data object Scan : Screen("scan", "Scan", Icons.Default.Home)
    data object Charts : Screen("charts", "Charts", Icons.Default.List)
    data object Upload : Screen("upload", "Upload", Icons.AutoMirrored.Filled.Send)
    data object Popp : Screen("popp", "PoPP", Icons.Default.Place)
    data object Settings : Screen("settings", "Settings", Icons.Default.Settings)
}

private val screens = listOf(Screen.Scan, Screen.Charts, Screen.Upload, Screen.Popp, Screen.Settings)

/**
 * Main app composable with bottom navigation.
 */
@Composable
fun CardlinkApp(
    scanHistory: ScanHistory,
    onThemeChanged: (de.scoopsoftware.cardlink.demo.ui.theme.BrandTheme) -> Unit = {},
) {
    val navController = rememberNavController()
    val context = LocalContext.current
    val activity = context as? Activity

    // Hoisted credentials — shared between all tabs
    var username by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var credentialsLoadedFromStorage by remember { mutableStateOf(false) }

    // Load saved credentials on first launch — try system Credential Manager, fall back to local
    LaunchedEffect(Unit) {
        if (activity != null && username.isEmpty() && password.isEmpty()) {
            val helper = de.scoopsoftware.cardlink.demo.auth.CredentialManagerHelper.create(context)
            val result = try {
                helper.getCredential(activity)
            } catch (_: Exception) {
                // System credential manager failed at runtime — fall back to local storage
                try {
                    val local = de.scoopsoftware.cardlink.demo.auth.LocalCredentialStorage(context)
                    val usernames = local.getSavedUsernames()
                    if (usernames.isNotEmpty()) {
                        val u = usernames.first()
                        val p = local.getPassword(u)
                        if (p != null) de.scoopsoftware.cardlink.demo.auth.CredentialResult.Success(u, p)
                        else de.scoopsoftware.cardlink.demo.auth.CredentialResult.NoCredentials
                    } else de.scoopsoftware.cardlink.demo.auth.CredentialResult.NoCredentials
                } catch (_: Exception) {
                    de.scoopsoftware.cardlink.demo.auth.CredentialResult.NoCredentials
                }
            }
            when (result) {
                is de.scoopsoftware.cardlink.demo.auth.CredentialResult.Success -> {
                    username = result.username
                    password = result.password
                    credentialsLoadedFromStorage = true
                }
                else -> {}
            }
        }
    }

    // Save credentials only when the user changes them (not on initial load)
    LaunchedEffect(username, password) {
        if (credentialsLoadedFromStorage) {
            // Skip the first change triggered by loading from storage
            credentialsLoadedFromStorage = false
            return@LaunchedEffect
        }
        if (activity != null && username.isNotEmpty() && password.isNotEmpty()) {
            try {
                val helper = de.scoopsoftware.cardlink.demo.auth.CredentialManagerHelper.create(context)
                helper.saveCredential(activity, username, password)
            } catch (_: Exception) {
                // Credential Manager unavailable — save locally
            }
            // Always save to local storage as well (works without Play Services)
            try {
                de.scoopsoftware.cardlink.demo.auth.LocalCredentialStorage(context)
                    .saveCredential(username, password)
            } catch (_: Exception) {}
        }
    }

    Scaffold(
        bottomBar = {
            Box(modifier = Modifier.fillMaxWidth()) {
                NavigationBar {
                    val navBackStackEntry by navController.currentBackStackEntryAsState()
                    val currentDestination = navBackStackEntry?.destination

                    screens.forEach { screen ->
                        NavigationBarItem(
                            icon = { Icon(screen.icon, contentDescription = screen.title) },
                            label = { Text(screen.title) },
                            selected = currentDestination?.hierarchy?.any { it.route == screen.route } == true,
                            onClick = {
                                navController.navigate(screen.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            }
                        )
                    }
                }
                // Version number in bottom right corner of navigation bar
                Text(
                    text = BuildConfig.VERSION_NAME,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(end = 4.dp, bottom = 0.dp)
                )
            }
        }
    ) { innerPadding ->
        Box(modifier = Modifier.fillMaxSize()) {
            NavHost(
                navController = navController,
                startDestination = Screen.Popp.route,
                modifier = Modifier.padding(innerPadding)
            ) {
                composable(Screen.Scan.route) {
                    ScanScreen(
                        scanHistory = scanHistory,
                        activity = activity,
                        username = username,
                        onUsernameChange = { username = it },
                        password = password,
                        onPasswordChange = { password = it },
                    )
                }
                composable(Screen.Charts.route) {
                    ChartsScreen(scanHistory = scanHistory)
                }
                composable(Screen.Upload.route) {
                    UploadScreen(
                        activity = activity,
                        username = username,
                        password = password,
                    )
                }
                composable(Screen.Popp.route) {
                    PoppScreen(
                        activity = activity,
                        username = username,
                        onUsernameChange = { username = it },
                        password = password,
                        onPasswordChange = { password = it },
                        scanHistory = scanHistory,
                    )
                }
                composable(Screen.Settings.route) {
                    SettingsScreen(onThemeChanged = onThemeChanged)
                }
            }

            // Orange DEV marker for debug builds (top right)
            if (BuildConfig.DEBUG) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(top = 8.dp, end = 8.dp)
                        .size(6.dp)
                        .clip(CircleShape)
                        .background(Color(0xFFFF9500))
                )
            }
        }
    }
}