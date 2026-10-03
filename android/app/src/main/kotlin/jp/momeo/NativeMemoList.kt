package jp.momeo

import android.content.Context
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.LineHeightSpan
import android.text.style.UpdateLayout
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.widget.FrameLayout
import android.widget.ScrollView
import android.widget.TextView
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.max
import kotlin.math.roundToInt

// ============================================================
// NativeMemoList — リスニング画面のメモ一覧（Android）
//
//   メモ全件を時系列順に並べた1つの TextView にし、表示とスクロールは OS に任せる。
//   Dart 側は lib/widgets/native_memo_list.dart。
// ============================================================

// ---------------------------------
// 定数: Dart 側とのやり取り
// ---------------------------------

// Dart から呼ばれるメソッド
private const val METHOD_UPDATE = "update"

// Dart から値が届かなかったときの既定値
private const val DEFAULT_FONT_SIZE = 18f
private val DEFAULT_TEXT_COLOR = 0xff111827.toInt()

// ---------------------------------
// 定数: 本文（dp。iOS 側の pt とそろえる）
// ---------------------------------

// 本文の左右と上の余白（右は、縦線と丸を置く場所を空けておく）
private const val BODY_PADDING_LEFT_DP = 12
private const val BODY_PADDING_RIGHT_DP = 34
private const val BODY_PADDING_TOP_DP = 24

// 本文の下の余白（ナビゲーションバーに重なる分は、これに足す）
private const val BODY_PADDING_BOTTOM_DP = 24

// 本文1行の高さ（文字サイズに対する倍率）。iOS はヒラギノの leading が1.5倍の行高に上乗せされて約2倍に見えるため、それに合わせる
private const val LINE_HEIGHT_RATIO = 2f

// ブロックとブロックの間の余白
private const val BLOCK_SPACING_DP = 24

// 空のメモにも1行分の高さを持たせるために置く、幅の無い文字
private const val EMPTY_BLOCK_TEXT = "​"

// 一番下からこの距離までにいれば、一番下を見ているとみなす
private const val AT_BOTTOM_TOLERANCE_DP = 32

// 本文の書体（Flutter 側の pubspec.yaml で同梱している Noto Sans JP）
private const val REGULAR_FONT_ASSET = "assets/fonts/NotoSansJP-Regular.otf"

// ---------------------------------
// MainActivity から登録する、メモ一覧の作り手
// ---------------------------------
class NativeMemoListFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        NativeMemoList(context, viewId, messenger, args)

    companion object {
        // Dart 側（native_memo_list.dart）の View の種類名とそろえる
        const val VIEW_TYPE = "jp.momeo/native_memo_list"
    }
}

// 1件のメモを、文書の中の1ブロックとして扱うための情報
private data class MemoBlock(
    val id: Long,
    // 表示する本文
    val text: String,
)

// ---------------------------------
// メモ一覧の View と、Dart とのやり取り
// ---------------------------------
private class NativeMemoList(context: Context, viewId: Int, messenger: BinaryMessenger, args: Any?) : PlatformView {
    private val channel = MethodChannel(messenger, "${NativeMemoListFactory.VIEW_TYPE}/$viewId")
    private val scroll = MemoScrollView(context)
    private val document = MemoDocumentView(context, scroll)

    init {
        scroll.isFillViewport = true
        scroll.addView(
            document,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT),
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_UPDATE -> {
                    document.update(call.arguments)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        document.update(args)
    }

    override fun getView(): View = scroll

    override fun dispose() {
        channel.setMethodCallHandler(null)
    }
}

// ---------------------------------
// 本文（メモ全件を1つにした文書）
// ---------------------------------
private class MemoDocumentView(context: Context, private val scroll: MemoScrollView) : TextView(context) {
    private val density = resources.displayMetrics.density

    // 表示中のブロック（古い順）
    private var blocks = listOf<MemoBlock>()
    // 本文の文字サイズ（px）
    private var fontPixels = DEFAULT_FONT_SIZE
    // 最初の表示で、一番下（最新）までスクロールする前か
    private var initialScrollPending = true

    init {
        // メモが少ないうちは、一覧を下に寄せる
        gravity = Gravity.BOTTOM or Gravity.START
        includeFontPadding = false
        setPadding(dp(BODY_PADDING_LEFT_DP), dp(BODY_PADDING_TOP_DP), dp(BODY_PADDING_RIGHT_DP), 0)
        setBackgroundColor(android.graphics.Color.TRANSPARENT)
        typeface = loadFlutterAssetFont(REGULAR_FONT_ASSET)
    }

    private fun dp(value: Int) = (value * density).roundToInt()

    // Flutter の assets に同梱した書体を読み込む（読めなければ端末の標準の書体）
    private fun loadFlutterAssetFont(assetPath: String): Typeface {
        val assetKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)
        return runCatching { Typeface.createFromAsset(context.assets, assetKey) }.getOrDefault(Typeface.DEFAULT)
    }

    // ---------------------------------
    // Dart から届いた文書で、表示を更新する
    // ---------------------------------
    fun update(arguments: Any?) {
        val data = arguments as? Map<*, *> ?: return
        val blockValues = data["blocks"] as? List<*> ?: return

        // --- 差し替える前のスクロール位置を覚えておく
        val wasAtBottom = scroll.scrollY >= height - scroll.height - dp(AT_BOTTOM_TOLERANCE_DP)
        val oldScrollY = scroll.scrollY

        // --- 文字の大きさ・色と、ブロック
        fontPixels = ((data["fontSize"] as? Number)?.toFloat() ?: DEFAULT_FONT_SIZE) * density
        val textColor = (data["textColor"] as? Number)?.toInt() ?: DEFAULT_TEXT_COLOR
        setTextSize(TypedValue.COMPLEX_UNIT_PX, fontPixels)
        setTextColor(textColor)
        blocks = parseBlocks(blockValues)

        // --- 文書を差し替える
        text = buildDocument()
        updateBottomPadding()

        // --- 組み直した後の高さで、スクロール位置を決める（最初と、一番下を見ていたときは最新へ）
        post {
            val scrollsToLatest = initialScrollPending || wasAtBottom
            scroll.scrollTo(0, if (scrollsToLatest) max(0, height - scroll.height) else oldScrollY)
            initialScrollPending = false
        }
    }

    // 文書の下の余白を、ナビゲーションバーの分に合わせる
    fun updateBottomPadding() {
        val bottomPadding = scroll.documentPaddingBottom()
        if (paddingBottom != bottomPadding) setPadding(paddingLeft, paddingTop, paddingRight, bottomPadding)
    }

    // Dart から届いたブロックの一覧（形の合わないものは飛ばす）
    private fun parseBlocks(values: List<*>): List<MemoBlock> = values.mapNotNull { value ->
        val item = value as? Map<*, *> ?: return@mapNotNull null
        val id = (item["id"] as? Number)?.toLong() ?: return@mapNotNull null
        MemoBlock(id = id, text = item["text"] as? String ?: "")
    }

    // 各ブロックの本文を改行1つでつなぎ、ブロックごとに行高とブロック間隔の span を付けた文書を作る
    private fun buildDocument(): SpannableStringBuilder {
        val document = SpannableStringBuilder()
        val lineHeight = (fontPixels * LINE_HEIGHT_RATIO).roundToInt()
        for ((index, block) in blocks.withIndex()) {
            val isLast = index + 1 == blocks.size
            val start = document.length
            document.append(block.text.ifEmpty { EMPTY_BLOCK_TEXT })
            if (!isLast) document.append('\n')
            // 最後のブロック以外は、後ろの改行まで含めてブロックの範囲とする
            val spacing = if (isLast) 0 else dp(BLOCK_SPACING_DP)
            document.setSpan(MemoLineHeightSpan(lineHeight, spacing), start, document.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        return document
    }
}

// ---------------------------------
// 文書をスクロールし、下端ではナビゲーションバーを避ける
// ---------------------------------
private class MemoScrollView(context: Context) : ScrollView(context) {
    private val density = resources.displayMetrics.density

    private val documentView: MemoDocumentView?
        get() = getChildAt(0) as? MemoDocumentView

    // 下端がナビゲーションバーに重なる高さ
    private fun bottomSystemBarOverlap(): Float {
        val insets = rootWindowInsets ?: return 0f
        val systemBarHeight = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            insets.getInsets(WindowInsets.Type.navigationBars()).bottom
        } else {
            @Suppress("DEPRECATION")
            insets.systemWindowInsetBottom
        }
        val location = IntArray(2)
        getLocationInWindow(location)
        val spaceBelow = rootView.height - (location[1] + height)
        return max(0, systemBarHeight - spaceBelow).toFloat()
    }

    // 文書の下の余白（ナビゲーションバーを避ける分を足す）
    fun documentPaddingBottom(): Int = (bottomSystemBarOverlap() + BODY_PADDING_BOTTOM_DP * density).roundToInt()

    // 一番下までスクロールしたときだけ、最新の行をナビゲーションバーの上へ離す（途中では下を通り抜けて流れる）
    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        documentView?.updateBottomPadding()
    }

    // 一番下を見ている間に一覧の高さが変わったとき（選択バーの出入りなど）は、一番下のまま保つ
    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        val documentHeight = documentView?.height ?: 0
        val wasAtBottom = scrollY >= documentHeight - oldHeight - AT_BOTTOM_TOLERANCE_DP * density
        super.onSizeChanged(width, height, oldWidth, oldHeight)
        if (oldHeight > 0 && height != oldHeight && wasAtBottom) {
            post { scrollTo(0, max(0, (documentView?.height ?: 0) - this.height)) }
        }
    }
}

// ---------------------------------
// 行高とブロック間隔を本文のレイアウトに含める
// ---------------------------------
// UpdateLayout を付けないと、付け外ししても TextView が行を組み直さず指定が反映されない
private class MemoLineHeightSpan(val height: Int, val spacing: Int) : LineHeightSpan, UpdateLayout {
    override fun chooseHeight(text: CharSequence, start: Int, end: Int, spanstartv: Int, v: Int, fm: Paint.FontMetricsInt) {
        // 行高の余りを、文字の上下に半分ずつ振り分ける
        val extra = max(0, height - (fm.descent - fm.ascent))
        fm.ascent -= extra / 2
        fm.descent += extra - extra / 2
        // ブロックの最後の行の下に、ブロック間の余白を足す（本文の追加で範囲が伸びても追えるよう、末尾は span の現在位置から求める）
        val blockEnd = (text as? Spanned)?.getSpanEnd(this) ?: -1
        if (blockEnd >= 0 && end >= blockEnd) fm.descent += spacing
        fm.top = fm.ascent
        fm.bottom = fm.descent
    }
}
