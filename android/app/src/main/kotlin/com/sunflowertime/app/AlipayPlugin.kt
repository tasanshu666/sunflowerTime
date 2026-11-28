package com.sunflowertime.app

import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import com.alipay.sdk.app.PayTask
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 支付宝 App 内支付的 **唯一原生代码**（Android-only）。
 *
 * 设计边界（增量架构设计 §1.3 / §2.2）：
 *  - 只做 `PayTask(activity).payV2(orderStr, true)` → `Map<String,String>` 的薄桥；
 *  - **私钥 / 订单签名 / 回调验签全在服务端**，本类零密钥；
 *  - 同步返回码只作「可能已付」信号，是否发货由服务端 `redeem` 决定；
 *  - 任何异常一律收敛为 `resultStatus=4000`，**绝不裸抛**到 Dart 侧；
 *  - `payV2` 是阻塞调用，必须在后台线程执行，回调用主线程投递。
 *
 * 注册点：`MainActivity.configureFlutterEngine` 里一行
 * `AlipayPlugin.register(flutterEngine, this)`（本类不写 pubspec 插件声明，
 * 避免 GeneratedPluginRegistrant 把任何符号带进 iOS 工程）。
 */
class AlipayPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        /** Dart 侧 `AlipayBridge` 使用的同一通道名（单点，勿改）。 */
        private const val CHANNEL = "sunfocus/alipay"

        /** 支付宝 App 包名（与 AndroidManifest queries 声明一致）。 */
        private const val ALIPAY_PACKAGE = "com.eg.android.AlipayGphone"

        /** 支付失败 / 未安装 / 异常的统一同步返回码（对齐支付宝官方 4000）。 */
        private const val RESULT_FAILED = "4000"

        /**
         * 从 [FlutterEngine] 注册 MethodChannel handler。
         *
         * 幂等：同一个 engine 重复调用只会覆盖 handler，不产生重复监听。
         */
        @JvmStatic
        fun register(engine: FlutterEngine, activity: Activity) {
            AlipayPlugin(activity, engine.dartExecutor.binaryMessenger)
        }
    }

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pay" -> pay(call.argument<String>("orderString"), result)
                "isInstalled" -> result.success(isInstalled())
                else -> result.notImplemented()
            }
        }
    }

    /** 支付宝 App 是否安装；任何异常都当「未安装」（失败安全）。 */
    private fun isInstalled(): Boolean = try {
        @Suppress("DEPRECATION")
        activity.packageManager.getPackageInfo(ALIPAY_PACKAGE, 0) != null
    } catch (_: PackageManager.NameNotFoundException) {
        false
    } catch (_: Exception) {
        false
    }

    /**
     * 唤起收银台。后台线程跑 `payV2`，主线程投递结果。
     *
     * 返回的 Map 固定含三个键（`resultStatus` / `memo` / `result`），
     * 缺失字段补空串，保证 Dart 侧 `Map<String,String>` 转换不会因 null 崩溃。
     */
    private fun pay(orderString: String?, result: MethodChannel.Result) {
        if (orderString.isNullOrBlank()) {
            result.success(
                mapOf(
                    "resultStatus" to RESULT_FAILED,
                    "memo" to "empty order string",
                    "result" to "",
                ),
            )
            return
        }

        Thread {
            val payload: Map<String, String> = try {
                val raw: Map<String, String> = PayTask(activity).payV2(orderString, true)
                mapOf(
                    "resultStatus" to (raw["resultStatus"]?.takeIf { it.isNotBlank() } ?: RESULT_FAILED),
                    "memo" to (raw["memo"] ?: ""),
                    "result" to (raw["result"] ?: ""),
                )
            } catch (e: Exception) {
                // 失败安全：SDK 抛错绝不跨 MethodChannel 传播，统一 4000 让 Dart 回「待支付」。
                mapOf(
                    "resultStatus" to RESULT_FAILED,
                    "memo" to (e.message ?: "pay failed"),
                    "result" to "",
                )
            }
            Handler(Looper.getMainLooper()).post { result.success(payload) }
        }.apply { isDaemon = true }.start()
    }
}
