package com.sunflowertime.app

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
        private const val TONE_CHANNEL = "sunfocus/tone"
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
                        // 2026-10-08 修复：NONE（完全静音）会把**媒体音量也静音**——
                        // 玄参小米 14 实测「专注中有收集动画、无收集音效」的根因。
                        // 改用 PRIORITY（仅屏蔽通知/铃声，媒体照常出声），
                        // 「专注期屏蔽通知」的原目标不变。
                        nm.setInterruptionFilter(
                            if (enabled) NotificationManager.INTERRUPTION_FILTER_PRIORITY
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
        val toneChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TONE_CHANNEL
        )
        toneChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "playDing" -> {
                    // 专注结束 3s 倒计时的「叮」提示音（玄参 2026-10-08：先用系统音填充，
                    // 后续再换正式素材）。用系统 ToneGenerator 内置提示音：
                    // - STREAM_MUSIC → 跟随媒体音量（勿扰 PRIORITY 档下照常出声）；
                    // - TONE_PROP_BEEP ≈ 一声短「叮」（约 150ms）；
                    // - 播完即释放，不留常驻资源；任何异常静默降级不影响主流程。
                    var tone: android.media.ToneGenerator? = null
                    try {
                        tone = android.media.ToneGenerator(android.media.AudioManager.STREAM_MUSIC, 80)
                        tone.startTone(android.media.ToneGenerator.TONE_PROP_BEEP, 200)
                        result.success(null)
                    } catch (e: Exception) {
                        android.util.Log.e("SunFocusTone", "playDing failed: ${e.message}")
                        result.success(null) // 静默降级：提示音失败不影响专注主流程
                    } finally {
                        // ToneGenerator 需在发音结束后释放；延迟释放避免截断提示音。
                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            try { tone?.release() } catch (_: Exception) {}
                        }, 400L)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
