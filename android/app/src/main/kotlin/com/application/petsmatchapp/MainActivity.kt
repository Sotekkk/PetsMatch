package com.application.petsmatchapp

import android.app.Activity
import android.app.Application
import android.graphics.Color
import android.os.Bundle
import android.view.View
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity: FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        installerCorrectifRecadrage(application)
    }

    companion object {
        private var correctifInstalle = false

        // Recadrage photo (uCrop, image_cropper) : depuis Android 15 l'affichage
        // bord à bord est imposé (et l'opt-out ignoré en ciblant le SDK 36) —
        // la barre « Valider » de uCrop passait sous la barre d'état, impossible
        // à toucher. On décale l'écran de recadrage des barres système (haut,
        // bas, encoche), quel que soit le téléphone.
        private fun installerCorrectifRecadrage(app: Application) {
            if (correctifInstalle) return
            correctifInstalle = true
            app.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
                override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
                override fun onActivityStarted(activity: Activity) {
                    if (!activity.javaClass.name.startsWith("com.yalantis.ucrop")) return
                    val contenu = activity.findViewById<View>(android.R.id.content) ?: return
                    contenu.setBackgroundColor(Color.parseColor("#0C5C6C"))
                    WindowCompat.getInsetsController(activity.window, activity.window.decorView).apply {
                        isAppearanceLightStatusBars = false
                        isAppearanceLightNavigationBars = false
                    }
                    ViewCompat.setOnApplyWindowInsetsListener(contenu) { v, insets ->
                        val b = insets.getInsets(
                            WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
                        v.setPadding(b.left, b.top, b.right, b.bottom)
                        insets
                    }
                    ViewCompat.requestApplyInsets(contenu)
                }
                override fun onActivityResumed(activity: Activity) {}
                override fun onActivityPaused(activity: Activity) {}
                override fun onActivityStopped(activity: Activity) {}
                override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
                override fun onActivityDestroyed(activity: Activity) {}
            })
        }
    }
}
