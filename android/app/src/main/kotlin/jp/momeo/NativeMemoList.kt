package jp.momeo

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.text.Selection
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.style.LineHeightSpan
import android.text.style.MetricAffectingSpan
import android.text.style.UpdateLayout
import android.util.TypedValue
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
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
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// ============================================================
// NativeMemoList — リスニング画面のメモ一覧（Android）
//
//   メモ全件を時系列順に並べた1つの TextView にし、文字選択・つまみ・メニュー・スクロールは OS に任せる。
//   右の縦線と丸はアプリ側で描く。
//   Dart 側は lib/widgets/native_memo_list.dart。
// ============================================================

// ---------------------------------
// 定数: Dart 側とのやり取り
// ---------------------------------

// Dart から呼ばれるメソッド
private const val METHOD_UPDATE = "update"

// Dart へ知らせるメソッド
private const val METHOD_TOGGLE_BLOCK = "toggleBlock"

// Dart から値が届かなかったときの既定値
private const val DEFAULT_FONT_SIZE = 18f
private val DEFAULT_TEXT_COLOR = 0xff111827.toInt()

// ---------------------------------
// 定数: 本文（dp。iOS 側の pt とそろえる）
// ---------------------------------

// 本文の左右と上の余白（右は丸と縦線の領域を含む）
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

// 本文の書体（Flutter 側の pubspec.yaml で同梱している Noto Sans JP。選択していないとき・選択中）
private const val REGULAR_FONT_ASSET = "assets/fonts/NotoSansJP-Regular.otf"
private const val BOLD_FONT_ASSET = "assets/fonts/NotoSansJP-Bold.otf"

// ---------------------------------
// 定数: 右の縦線と丸（dp）
// ---------------------------------

// 縦線と丸を押せる領域の幅（一覧の右端から）
private const val RAIL_TOUCH_WIDTH_DP = 40

// 縦線の位置（一覧の右端から）
private const val RAIL_X_FROM_RIGHT_DP = 18

// 縦線の太さと丸の半径（選択していないとき・選択中）
private const val RAIL_WIDTH_DP = 1.5f
private const val SELECTED_RAIL_WIDTH_DP = 2.5f
private const val CIRCLE_RADIUS_DP = 4f
private const val SELECTED_CIRCLE_RADIUS_DP = 5.5f

// ブロックが1つだけのときに、丸を1行目の文字の上端から離す距離
private const val SINGLE_BLOCK_CIRCLE_GAP_DP = 12

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
    // 丸で選ばれているか
    val selected: Boolean,
    // 文書の中での本文の範囲（start 以上 end 未満）
    var start: Int = 0,
    var end: Int = 0,
)

// ---------------------------------
// メモ一覧の View と、Dart とのやり取り
// ---------------------------------
private class NativeMemoList(context: Context, viewId: Int, messenger: BinaryMessenger, args: Any?) : PlatformView {
    private val channel = MethodChannel(messenger, "${NativeMemoListFactory.VIEW_TYPE}/$viewId")
    // 文字選択のつまみ・メニューが、OS 標準の見た目で出るようにする
    private val themedContext = ContextThemeWrapper(context, android.R.style.Theme_Material_Light_NoActionBar)
    private val scroll = MemoScrollView(themedContext)
    private val document = MemoDocumentView(themedContext, scroll)

    init {
        scroll.isFillViewport = true
        scroll.addView(
            document,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT),
        )
        document.onToggleBlock = { blockId -> channel.invokeMethod(METHOD_TOGGLE_BLOCK, blockId) }
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
        document.onToggleBlock = null
    }
}

// ---------------------------------
// 本文（メモ全件を1つにした文書）と、右の縦線・丸
// ---------------------------------
private class MemoDocumentView(context: Context, private val scroll: MemoScrollView) : TextView(context) {
    // 丸が押されたブロックのメモ id を知らせる
    var onToggleBlock: ((Long) -> Unit)? = null

    private val density = resources.displayMetrics.density

    // 表示中のブロック（古い順）
    private var blocks = listOf<MemoBlock>()
    // 本文の文字サイズ（px）
    private var fontPixels = DEFAULT_FONT_SIZE
    // 最初の表示で、一番下（最新）までスクロールする前か
    private var initialScrollPending = true
    // 選択中のブロックの本文に使う太字の書体
    private val boldTypeface = loadFlutterAssetFont(BOLD_FONT_ASSET)
    // 縦線と丸を描く絵の具
    private val railPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    // 縦線・丸の上で始まったタッチ（離したときに、動かさずに離したかを判定する）
    private var railTouchDown: MotionEvent? = null

    // --- 文字選択
    // 文書を組み直している間は、選択の変化を OS の操作として扱わない
    private var updating = false
    // TextView の生成中にも選択の変化が届くため、生成が済むまでは扱わない
    private var initialized = false

    init {
        // メモが少ないうちは、一覧を下に寄せる
        gravity = Gravity.BOTTOM or Gravity.START
        includeFontPadding = false
        setPadding(dp(BODY_PADDING_LEFT_DP), dp(BODY_PADDING_TOP_DP), dp(BODY_PADDING_RIGHT_DP), 0)
        setBackgroundColor(android.graphics.Color.TRANSPARENT)
        typeface = loadFlutterAssetFont(REGULAR_FONT_ASSET)
        setTextIsSelectable(true)
        initialized = true
    }

    private fun dp(value: Int) = (value * density).roundToInt()

    // 文字選択の対象になるブロック（本文が空のメモを除く）
    private fun copyableBlocks(): List<MemoBlock> = blocks.filter { it.text.isNotEmpty() }

    // 範囲（from 以上 to 未満）に1文字でも掛かる、文字選択の対象のブロック
    private fun copyableBlocksIn(from: Int, to: Int): List<MemoBlock> =
        copyableBlocks().filter { it.end > from && it.start < to }

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
        railPaint.color = textColor
        blocks = parseBlocks(blockValues)

        // --- 文書を差し替える
        updating = true
        text = buildDocument()
        updating = false
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

    // ---------------------------------
    // 文字選択
    // ---------------------------------
    // OS の操作で文字選択が変わったとき
    override fun onSelectionChanged(start: Int, end: Int) {
        super.onSelectionChanged(start, end)
        if (!initialized || updating) return
        val from = min(start, end)
        val to = max(start, end)
        val touchedBlocks = copyableBlocksIn(from, to)
        if (start != end && from >= 0 && touchedBlocks.isNotEmpty()) {
            fitSelectionToBlocks(from, to, touchedBlocks)
        } else if (from >= 0 && start != end) {
            collapseSelectionLater(start, end)
        }
    }

    // 選択範囲の両端を、掛かっているブロックの本文の端までに収める
    private fun fitSelectionToBlocks(from: Int, to: Int, touchedBlocks: List<MemoBlock>) {
        val fittedStart = max(from, touchedBlocks.first().start)
        val fittedEnd = min(to, touchedBlocks.last().end)
        if (fittedStart == from && fittedEnd == to) return
        updating = true
        Selection.setSelection(text as Spannable, fittedStart, fittedEnd)
        updating = false
    }

    // 本文に掛からない選択になったら、OS の処理を終えてから選択を畳む
    private fun collapseSelectionLater(start: Int, end: Int) {
        post {
            if (selectionStart != start || selectionEnd != end || !hasSelection()) return@post
            updating = true
            Selection.setSelection(text as Spannable, max(0, start))
            updating = false
        }
    }

    // Dart から届いたブロックの一覧（形の合わないものは飛ばす）
    private fun parseBlocks(values: List<*>): List<MemoBlock> = values.mapNotNull { value ->
        val item = value as? Map<*, *> ?: return@mapNotNull null
        val id = (item["id"] as? Number)?.toLong() ?: return@mapNotNull null
        MemoBlock(id = id, text = item["text"] as? String ?: "", selected = item["selected"] == true)
    }

    // 各ブロックの本文を改行1つでつなぎ、ブロックごとに行高・ブロック間隔・太字の span を付けた文書を作る（ブロックごとの文書の中の範囲も記録する）
    private fun buildDocument(): SpannableStringBuilder {
        val document = SpannableStringBuilder()
        val lineHeight = (fontPixels * LINE_HEIGHT_RATIO).roundToInt()
        for ((index, block) in blocks.withIndex()) {
            val isLast = index + 1 == blocks.size
            block.start = document.length
            document.append(block.text.ifEmpty { EMPTY_BLOCK_TEXT })
            block.end = document.length
            if (!isLast) document.append('\n')
            // 最後のブロック以外は、後ろの改行まで含めてブロックの範囲とする
            val spacing = if (isLast) 0 else dp(BLOCK_SPACING_DP)
            document.setSpan(MemoLineHeightSpan(lineHeight, spacing), block.start, document.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            if (block.selected) {
                document.setSpan(MemoTypefaceSpan(boldTypeface), block.start, document.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        }
        return document
    }

    // ---------------------------------
    // 丸の位置（上のブロックの最後の行の文字の下端と、このブロックの1行目の文字の上端のちょうど間）
    // ---------------------------------
    // 文字の上端・下端は、行高やブロック間隔の余白を含まない、フォントの ascent・descent の範囲
    private fun circleCenterYs(): List<Float> {
        val textLayout = layout ?: return blocks.map { totalPaddingTop.toFloat() }
        val metrics = paint.fontMetrics
        fun baselineAt(offset: Int) =
            totalPaddingTop + textLayout.getLineBaseline(textLayout.getLineForOffset(offset)).toFloat()
        val glyphTops = blocks.map { baselineAt(it.start) + metrics.ascent }
        val centers = blocks.indices.map { index ->
            if (index == 0) {
                0f
            } else {
                val upperBottom = baselineAt(blocks[index - 1].end - 1) + metrics.descent
                (upperBottom + glyphTops[index]) / 2
            }
        }.toMutableList()
        // 一番上のブロックには上のブロックがないので、2番目のブロックと同じだけ文字の上端から離す
        if (blocks.isNotEmpty()) {
            val halfGap = if (blocks.size > 1) glyphTops[1] - centers[1] else dp(SINGLE_BLOCK_CIRCLE_GAP_DP).toFloat()
            centers[0] = glyphTops[0] - halfGap
        }
        return centers
    }

    // 高さ y より上で、一番近い丸を持つブロック（どの丸よりも上なら null）
    private fun blockWithCircleAbove(y: Float): MemoBlock? {
        val circleCenters = circleCenterYs()
        return blocks.indices.lastOrNull { circleCenters[it] <= y }?.let { blocks[it] }
    }

    // ---------------------------------
    // 描画
    // ---------------------------------
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        drawRail(canvas)
    }

    // 右の縦線と丸（選択中のブロックは太い線と大きな丸）
    private fun drawRail(canvas: Canvas) {
        val x = width - dp(RAIL_X_FROM_RIGHT_DP).toFloat()
        // 親のスクロールでは描画が再実行されないため、全区間を記録する
        val circleCenters = circleCenterYs()
        for ((index, block) in blocks.withIndex()) {
            val top = circleCenters[index]
            val bottom = if (index + 1 < blocks.size) circleCenters[index + 1] else height.toFloat()
            val lineWidth = if (block.selected) SELECTED_RAIL_WIDTH_DP else RAIL_WIDTH_DP
            val radius = if (block.selected) SELECTED_CIRCLE_RADIUS_DP else CIRCLE_RADIUS_DP
            railPaint.strokeWidth = lineWidth * density
            canvas.drawLine(x, top, x, bottom, railPaint)
            canvas.drawCircle(x, top, radius * density, railPaint)
        }
    }

    // ---------------------------------
    // タッチ
    // ---------------------------------
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (handleRailTouch(event)) return true
        return super.onTouchEvent(event)
    }

    // 縦線・丸の上で始まったタッチを受け取り、動かさずに離したらそのブロックの選択を切り替える
    private fun handleRailTouch(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN && event.x >= width - dp(RAIL_TOUCH_WIDTH_DP)) {
            railTouchDown?.recycle()
            railTouchDown = MotionEvent.obtain(event)
            return true
        }
        val down = railTouchDown ?: return false
        when (event.actionMasked) {
            MotionEvent.ACTION_UP -> {
                val slop = ViewConfiguration.get(context).scaledTouchSlop
                val isTap = abs(event.y - down.y) < slop && abs(event.x - down.x) < slop
                if (isTap) {
                    blockWithCircleAbove(event.y)?.let { onToggleBlock?.invoke(it.id) }
                    performClick()
                }
                releaseRailTouch()
            }
            MotionEvent.ACTION_CANCEL -> releaseRailTouch()
        }
        return true
    }

    private fun releaseRailTouch() {
        railTouchDown?.recycle()
        railTouchDown = null
    }

    // onTouchEvent を上書きしたときの lint の決まりに合わせて、performClick も上書きしておく
    override fun performClick(): Boolean = super.performClick()
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
// 選択中のブロックの本文を、同梱した太字の書体で描く
// ---------------------------------
// 標準の StyleSpan(BOLD) では、太字の書体ではなく標準の太さを機械的に太らせて描いてしまうため
private class MemoTypefaceSpan(private val typeface: Typeface) : MetricAffectingSpan() {
    override fun updateDrawState(paint: TextPaint) {
        paint.typeface = typeface
    }

    override fun updateMeasureState(paint: TextPaint) {
        paint.typeface = typeface
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
