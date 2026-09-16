package com.example.sunflower_time

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "sunfocus/dnd"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isDndPolicyGranted" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    result.success(nm.isNotificationPolicyAccessGranted)
                }
                "openDndSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("OPEN_DND_SETTINGS_FAILED", e.message, null)
                    }
                }
                "setDnd" -> {
                    try {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        // 未授权时 setInterruptionFilter(NONE) 会抛 SecurityException，catch 后
                        // 返回 -1 作为「未生效」自证（B30 诊断用），不影响专注主流程。
                        nm.setInterruptionFilter(
                            if (enabled) NotificationManager.INTERRUPTION_FILTER_NONE
                            else NotificationManager.INTERRUPTION_FILTER_ALL
                        )
                        // 读回当前生效的过滤档位作为「是否真生效」的自证（B30）。
                        val actual = nm.currentInterruptionFilter
                        android.util.Log.d(
                            "SunFocusDND",
                            "setDnd enabled=$enabled actualFilter=$actual"
                        )
                        result.success(actual)
                    } catch (e: Exception) {
                        android.util.Log.e(
                            "SunFocusDND",
                            "setDnd failed enabled=${call.argument<Boolean>("enabled")} err=${e.message}"
                        )
                        result.success(-1) // -1：未生效（如未授权）
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
