package jp.momeo

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.android.play.core.assetpacks.AssetPackManager
import com.google.android.play.core.assetpacks.AssetPackManagerFactory
import com.google.android.play.core.assetpacks.AssetPackState
import com.google.android.play.core.assetpacks.AssetPackStateUpdateListener
import com.google.android.play.core.assetpacks.model.AssetPackStatus
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// ============================================================
// Play Asset Delivery（アセットパックの自動DL）を Flutter から操作するための橋渡し。
//
//   Android の AssetPackManager の機能を、余計な加工をせずそのまま Dart へ中継する役。
//   Dart からは2つの通信路で呼べる:
//     - MethodChannel … Dart から呼ぶたびに1回ずつ返事する（実パス取得・状態取得・取得開始/再試行）
//     - EventChannel … DL状態が変わるたびに Dart へ通知し続ける（進捗が刻々と変わるため）
//
//   この橋渡しは特定のモデルを知らない。扱うのは「パック名（packName）」だけなので、
//   どんなアセットパックにも使い回せる（呼ぶ側がパック名を渡す）。
//
//   ※ チャンネル名・メソッド名・辞書のキーは、Dart 側（lib/platform/asset_pack_delivery.dart）と
//     必ず一致させること。
// ============================================================
class AssetPackDeliveryChannel(context: Context, messenger: BinaryMessenger) {

    companion object {
        // 呼ぶたびに1回ずつ返事する通信路と、そのメソッド名
        private const val METHOD_CHANNEL = "jp.momeo/asset_pack"
        private const val METHOD_GET_ASSETS_PATH = "getAssetsPath" // 完了後の実パスを取る
        private const val METHOD_GET_STATE = "getState"            // 今の状態を1回だけ取る
        private const val METHOD_FETCH = "fetch"                   // 取得開始・再試行

        // DL状態が変わるたびに通知し続ける通信路
        private const val EVENT_CHANNEL = "jp.momeo/asset_pack/events"

        // メソッドの引数キー
        private const val ARG_PACK_NAME = "packName"
    }

    // 自動DLを操作する本体。アプリ全体で1つ使えればよいので生成して保持する。
    private val assetPackManager: AssetPackManager = AssetPackManagerFactory.getInstance(context)

    // イベント通知は必ずメインスレッドから行う必要があるため、メインスレッドへ橋渡しする係。
    private val mainHandler = Handler(Looper.getMainLooper())

    // 現在 EventChannel を購読している相手（いなければ null）。
    private var eventSink: EventChannel.EventSink? = null

    // DL状態が変わるたびに呼ばれるリスナー。購読中だけ登録し、更新を Dart へ流す。
    private val stateListener = AssetPackStateUpdateListener { state ->
        val snapshot = toSnapshot(state)
        mainHandler.post { eventSink?.success(snapshot) }
    }

    init {
        // Dart から呼ばれたときの処理を登録する（呼ばれるたびに1回ずつ返事する）。
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            handleMethodCall(call.method, call.argument<String>(ARG_PACK_NAME), result)
        }

        // DL状態を通知し続けるための登録。購読が始まったらリスナー登録、終わったら解除。
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                assetPackManager.registerListener(stateListener)
            }

            override fun onCancel(arguments: Any?) {
                assetPackManager.unregisterListener(stateListener)
                eventSink = null
            }
        })
    }

    // ---------------------------------
    // Dart から呼ばれたときの処理本体（呼ばれるたびに1回ずつ返事する）
    // ---------------------------------

    private fun handleMethodCall(method: String, packName: String?, result: MethodChannel.Result) {
        // どのメソッドもパック名が必須。無ければ呼び出し側の誤りとして弾く。
        if (packName == null) {
            result.error("missing_pack_name", "packName が指定されていません", null)
            return
        }

        when (method) {
            // 完了後の実パス。まだ無ければ null（パックが未到着）。
            METHOD_GET_ASSETS_PATH -> {
                val location = assetPackManager.getPackLocation(packName)
                result.success(location?.assetsPath())
            }

            // 今の状態を1回だけ取得（getPackStates は非同期なので完了を待って返す）。
            METHOD_GET_STATE -> {
                assetPackManager.getPackStates(listOf(packName))
                    .addOnSuccessListener { states ->
                        result.success(toSnapshot(states.packStates()[packName]))
                    }
                    .addOnFailureListener { error ->
                        result.error("get_state_failed", error.message, null)
                    }
            }

            // 取得開始・再試行。fast-follow は自動DLだが、未到着や失敗時の保険として明示的に促せる。
            METHOD_FETCH -> {
                assetPackManager.fetch(listOf(packName))
                    .addOnSuccessListener { result.success(null) }
                    .addOnFailureListener { error ->
                        result.error("fetch_failed", error.message, null)
                    }
            }

            else -> result.notImplemented()
        }
    }

    // ---------------------------------
    // AssetPackState を Dart へ渡せる辞書に変換する
    //   state が null（その名前のパックが無い）なら null を返す。
    // ---------------------------------

    private fun toSnapshot(state: AssetPackState?): Map<String, Any?>? {
        if (state == null) return null
        return mapOf(
            "packName" to state.name(),
            "status" to statusToName(state.status()), // 数値ではなく分かる名前で渡す
            "bytesDownloaded" to state.bytesDownloaded(),
            "totalBytes" to state.totalBytesToDownload(),
            "transferProgress" to state.transferProgressPercentage(),
            "errorCode" to state.errorCode(),
        )
    }

    // 状態の数値定数を、Dart 側が解釈しやすい文字列に直す。
    private fun statusToName(status: Int): String = when (status) {
        AssetPackStatus.PENDING -> "pending"
        AssetPackStatus.DOWNLOADING -> "downloading"
        AssetPackStatus.TRANSFERRING -> "transferring"
        AssetPackStatus.COMPLETED -> "completed"
        AssetPackStatus.FAILED -> "failed"
        AssetPackStatus.CANCELED -> "canceled"
        AssetPackStatus.WAITING_FOR_WIFI -> "waitingForWifi"
        AssetPackStatus.NOT_INSTALLED -> "notInstalled"
        else -> "unknown"
    }
}
