package jp.momeo

import android.annotation.TargetApi
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Region
import android.graphics.Typeface
import android.os.Build
import android.text.Selection
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.LineHeightSpan
import android.text.style.UpdateLayout
import android.util.TypedValue
import android.view.ContextThemeWrapper
import android.view.GestureDetector
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
//   右の縦線と日付の区切りの横線、スクロールつまみ、発話中の「.」はアプリ側で描く。
//   Dart 側は lib/widgets/native_memo_list.dart。
// ============================================================

// ---------------------------------
// 定数: Dart 側とのやり取り
// ---------------------------------

// Dart から呼ばれるメソッド
private const val METHOD_UPDATE = "update"
private const val METHOD_CLEAR_SELECTION = "clearSelection"

// Dart へ知らせるメソッド
private const val METHOD_THUMB = "thumb"

// Dart から値が届かなかったときの既定値
private const val DEFAULT_FONT_SIZE = 18f
private val DEFAULT_TEXT_COLOR = 0xff111827.toInt()
private val DEFAULT_RAIL_COLOR = 0xffcfd1d4.toInt()
private const val DEFAULT_COPY_SEPARATOR = "\n\n"

// ---------------------------------
// 定数: 本文（dp。iOS 側の pt とそろえる）
// ---------------------------------

// 本文の左右と上の余白（右も左と同じ。縦線は本文の後ろを通す）
private const val BODY_PADDING_LEFT_DP = 8
private const val BODY_PADDING_RIGHT_DP = 8
private const val BODY_PADDING_TOP_DP = 24

// 本文の下の余白（ナビゲーションバーに重なる分は、これに足す）
private const val BODY_PADDING_BOTTOM_DP = 24

// 本文1行の高さ（文字サイズに対する倍率）。iOS はヒラギノの leading が1.5倍の行高に上乗せされて約2倍に見えるため、それに合わせる
private const val LINE_HEIGHT_RATIO = 2f

// ブロックとブロックの間の余白
private const val BLOCK_SPACING_DP = 24

// 空のメモにも区切りと1行分の高さを持たせるために置く、幅の無い文字
private const val EMPTY_BLOCK_TEXT = "​"

// 一番下からこの距離までにいれば、一番下を見ているとみなす
private const val AT_BOTTOM_TOLERANCE_DP = 32

// 本文の書体（Flutter 側の pubspec.yaml で同梱している Noto Sans JP）
private const val REGULAR_FONT_ASSET = "assets/fonts/NotoSansJP-Regular.otf"

// ---------------------------------
// 定数: 右の縦線と、日付の区切りの横線（dp）
// ---------------------------------

// 縦線の位置（一覧の右端から）
private const val RAIL_X_FROM_RIGHT_DP = 18

// 縦線と横線の太さ
private const val RAIL_WIDTH_DP = 0.5f

// ブロックが1つだけのときに、区切りを1行目の文字の上端から離す距離
private const val SINGLE_BLOCK_BOUNDARY_GAP_DP = 12

// ---------------------------------
// 定数: スクロールつまみ（dp）
// ---------------------------------

// 横棒の幅と太さ
private const val THUMB_WIDTH_DP = 24
private const val THUMB_THICKNESS_DP = 0.5f

// つまみを掴める幅（一覧の右端から）と高さ。細い横棒でも掴めるよう、当たり判定は見た目より上下に広げる
private const val THUMB_TOUCH_WIDTH_DP = 40
private const val THUMB_TOUCH_HEIGHT_DP = 44

// つまみが動く範囲の上下の余白（下端がナビゲーションバーに重なるときは広めにとる）
private const val THUMB_TRACK_MARGIN_DP = 12
private const val THUMB_TRACK_MARGIN_ABOVE_NAV_BAR_DP = 24

// ---------------------------------
// 定数: 発話中の「.」
// ---------------------------------

// 0.5秒ごとに「.」を1つずつ増やし、行に収まる数（最大10個）まで増えたら0個に戻す
private const val SPEAKING_DOTS_INTERVAL_MS = 500L
private const val SPEAKING_DOTS_MAX_COUNT = 10

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
    // 表示する本文（文字選択中は、選択を始めた時点の本文を保つ）
    var text: String,
    // 文字選択の対象にするか（打ち出し中は対象にしない）
    var selectable: Boolean,
    // その日の最初のメモか（日付の区切りの横線は、その日の最初のメモの上にだけ引く）
    val startsDay: Boolean,
    // 文書の中での本文の範囲（start 以上 end 未満）
    var start: Int = 0,
    var end: Int = 0,
)

// 発話中の気配として「.」を出す場所
private enum class SpeakingDotsPlace(val key: String) {
    // 最新のブロックの本文の続き
    APPEND("append"),
    // 次のブロックの1行目
    NEW_BLOCK("newBlock");

    companion object {
        // Dart から届いた値に当たる場所（出さないときは null）
        fun fromKey(key: Any?): SpeakingDotsPlace? = values().firstOrNull { it.key == key }
    }
}

// 文書の中の位置を、どのブロックの何文字目かで表したもの（本文を差し替えても選択範囲を置き直せるようにする）
private data class BlockPosition(val blockId: Long, val offsetInBlock: Int)

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
        scroll.onThumbChanged = { blockId, y, scrolling ->
            channel.invokeMethod(METHOD_THUMB, mapOf("id" to blockId, "y" to y, "scrolling" to scrolling))
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_UPDATE -> {
                    document.update(call.arguments)
                    // 表示を作り直したときも、Flutter 側が日付を取りこぼさないように知らせ直す
                    scroll.post { scroll.reportThumb(force = true) }
                    result.success(null)
                }
                METHOD_CLEAR_SELECTION -> {
                    document.clearTextSelection()
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
        scroll.onThumbChanged = null
        document.clearFocus()
    }
}

// ---------------------------------
// 本文（メモ全件を1つにした文書）と、右の縦線・日付の区切りの横線、発話中の「.」
// ---------------------------------
private class MemoDocumentView(context: Context, private val scroll: MemoScrollView) : TextView(context) {
    private val density = resources.displayMetrics.density

    // --- 文書
    // 表示中のブロック（古い順）
    private var blocks = listOf<MemoBlock>()
    // 最後に Dart から届いた文書（文字選択が外れたときに、止めていた更新を反映し直す）
    private var latestArguments: Any? = null
    // 本文の文字サイズ（px）
    private var fontPixels = DEFAULT_FONT_SIZE
    // 最初の表示で、一番下（最新）までスクロールする前か
    private var initialScrollPending = true

    // --- 文字選択
    // 文字選択中に、選択を始めた時点の本文を保つ（メモ id → 本文）
    private val snapshots = mutableMapOf<Long, String>()
    // 文書を組み直している間は、選択の変化を OS の操作として扱わない
    private var updating = false
    // TextView の生成中にも選択の変化が届くため、生成が済むまでは扱わない
    private var initialized = false
    // アプリが置き直した選択範囲（OS がその端までスクロールしないようにする）
    private var selectionWithoutScrolling: Pair<Int, Int>? = null
    // 選択中の面に指を置いたときの選択範囲（1回タップによる解除の判定に使う）
    private var selectionAtTouchDown: Pair<Int, Int>? = null
    // ブロックをまたいでコピーしたときの区切り
    private var copySeparator = DEFAULT_COPY_SEPARATOR

    // --- 行高と、縦線・横線
    // ブロックごとに付けている行高の span（メモ id → span）
    private val lineHeightSpans = mutableMapOf<Long, MemoLineHeightSpan>()
    // 縦線と横線を描く絵の具（背景の波線と同じ色）
    private val railPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    // --- 発話中の「.」
    // 出す場所（出さないときは null）と、今の数・行に収まる数
    private var speakingDotsPlace: SpeakingDotsPlace? = null
    private var speakingDotCount = 0
    private var fittingDotCount = 0
    private val speakingDotsPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val advanceSpeakingDots = object : Runnable {
        override fun run() {
            speakingDotCount = if (fittingDotCount > 0) (speakingDotCount + 1) % (fittingDotCount + 1) else 0
            invalidate()
            postDelayed(this, SPEAKING_DOTS_INTERVAL_MS)
        }
    }

    // 選択中の面への1回タップを見分ける（長押し・ダブルタップ・ドラッグは TextView が扱う）
    private val selectionTapDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(event: MotionEvent): Boolean {
            selectionAtTouchDown = if (selectionContains(event.x, event.y)) currentSelection else null
            return true
        }

        override fun onSingleTapConfirmed(event: MotionEvent): Boolean {
            val selectionAtDown = selectionAtTouchDown
            selectionAtTouchDown = null
            // 指を置いてから選択が変わっていなければ、解除する
            if (selectionAtDown != null && selectionAtDown == currentSelection && isAttachedToWindow) {
                clearTextSelection()
            }
            return true
        }
    })

    init {
        // メモが少ないうちは、一覧を下に寄せる
        gravity = Gravity.BOTTOM or Gravity.START
        includeFontPadding = false
        setPadding(dp(BODY_PADDING_LEFT_DP), dp(BODY_PADDING_TOP_DP), dp(BODY_PADDING_RIGHT_DP), 0)
        setBackgroundColor(android.graphics.Color.TRANSPARENT)
        typeface = loadFlutterAssetFont(REGULAR_FONT_ASSET)
        setTextIsSelectable(true)
        // TextView のまま、文書の差分更新で OS の選択状態を保つ
        setSpannableFactory(object : Spannable.Factory() {
            override fun newSpannable(source: CharSequence): Spannable = SpannableStringBuilder(source)
        })
        setText("", BufferType.SPANNABLE)
        initialized = true
    }

    private fun dp(value: Int) = (value * density).roundToInt()

    // 今の選択範囲（前後の端の組）と、その前側・後側の位置
    private val currentSelection: Pair<Int, Int>
        get() = selectionStart to selectionEnd
    private val selectionFrom: Int
        get() = min(selectionStart, selectionEnd)
    private val selectionTo: Int
        get() = max(selectionStart, selectionEnd)

    // 文字選択とコピーの対象になるブロック（打ち出し中のメモと、本文が空のメモを除く）
    private fun copyableBlocks(): List<MemoBlock> = blocks.filter { it.selectable && it.text.isNotEmpty() }

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
    // 本文は変わったところから後ろだけを差し替え、OS の文字選択とスクロール位置を保つ
    fun update(arguments: Any?) {
        val data = arguments as? Map<*, *> ?: return
        val blockValues = data["blocks"] as? List<*> ?: return
        latestArguments = arguments
        copySeparator = data["copySeparator"] as? String ?: DEFAULT_COPY_SEPARATOR
        val incoming = parseBlocks(blockValues)

        // --- 差し替える前の文字選択とスクロール位置を覚えておく（選択範囲のメモが消えるなら、文字選択を解除する）
        val incomingIds = incoming.map { it.id }.toSet()
        if (blocks.any { selectionIntersects(it) && it.id !in incomingIds }) clearTextSelection(refresh = false)
        val selectionStartPosition = blockPositionAt(selectionFrom)
        val selectionEndPosition = blockPositionAt(selectionTo)
        val hadSelection = hasSelection()
        val wasAtBottom = scroll.scrollY >= height - scroll.height - dp(AT_BOTTOM_TOLERANCE_DP)
        val oldScrollY = scroll.scrollY

        // --- 文字の大きさ・色
        fontPixels = ((data["fontSize"] as? Number)?.toFloat() ?: DEFAULT_FONT_SIZE) * density
        val textColor = (data["textColor"] as? Number)?.toInt() ?: DEFAULT_TEXT_COLOR
        val railColor = (data["railColor"] as? Number)?.toInt() ?: DEFAULT_RAIL_COLOR
        changeSpeakingDotsPlace(SpeakingDotsPlace.fromKey(data["speakingDots"]))

        // --- 文字選択中のメモは、選択を始めた時点の本文のまま出す（その間の追記は、選択を解除すると出る）
        for (block in incoming) {
            val snapshot = snapshots[block.id] ?: continue
            block.text = snapshot
            block.selectable = true
        }
        blocks = incoming
        val newText = buildDocumentText()

        // --- 文書を差し替え、文字選択を置き直す
        updating = true
        applyTextSizeAndColor(textColor, railColor)
        val document = text as SpannableStringBuilder
        replaceChangedTail(document, newText)
        syncBlockSpans(document)
        // 次のブロックの1行目に「.」を出すあいだは、その分の高さを文書の下に空けておく
        updateBottomPadding()
        if (hadSelection && selectionStartPosition != null && selectionEndPosition != null) {
            restoreSelection(selectionStartPosition, selectionEndPosition)
        }
        updating = false
        requestLayout()
        invalidate()

        // --- 組み直した後の高さで、スクロール位置を決める（最初と、一番下を見ていたときは最新へ。文字選択中は動かさない）
        post {
            val scrollsToLatest = initialScrollPending || (wasAtBottom && !hadSelection)
            scroll.scrollToByApp(if (scrollsToLatest) max(0, height - scroll.height) else oldScrollY)
            initialScrollPending = false
        }
    }

    // Dart から届いたブロックの一覧（形の合わないものは飛ばす）
    private fun parseBlocks(values: List<*>): List<MemoBlock> = values.mapNotNull { value ->
        val item = value as? Map<*, *> ?: return@mapNotNull null
        val id = (item["id"] as? Number)?.toLong() ?: return@mapNotNull null
        MemoBlock(
            id = id,
            text = item["text"] as? String ?: "",
            selectable = item["selectable"] != false,
            startsDay = item["startsDay"] != false,
        )
    }

    // 各ブロックの本文を改行1つでつないだ文書を作り、ブロックごとの文書の中の範囲も記録する
    private fun buildDocumentText(): String {
        val builder = StringBuilder()
        for ((index, block) in blocks.withIndex()) {
            block.start = builder.length
            builder.append(block.text.ifEmpty { EMPTY_BLOCK_TEXT })
            block.end = builder.length
            if (index + 1 < blocks.size) builder.append('\n')
        }
        return builder.toString()
    }

    // 本文・縦線・横線・「.」・つまみの色と、本文の文字サイズ
    private fun applyTextSizeAndColor(textColor: Int, railColor: Int) {
        setTextSize(TypedValue.COMPLEX_UNIT_PX, fontPixels)
        setTextColor(textColor)
        railPaint.color = railColor
        speakingDotsPaint.color = textColor
        scroll.thumbColor = textColor
    }

    // 前と同じ先頭部分は置き直さず、変わったところから後ろだけを差し替える
    private fun replaceChangedTail(document: SpannableStringBuilder, newText: String) {
        if (document.toString() == newText) return
        val shorterLength = min(document.length, newText.length)
        var commonLength = 0
        while (commonLength < shorterLength && document[commonLength] == newText[commonLength]) commonLength++
        // サロゲートペアの途中で切らない
        if (commonLength > 0 && commonLength < document.length && Character.isLowSurrogate(document[commonLength])) {
            commonLength--
        }
        document.replace(commonLength, document.length, newText.substring(commonLength))
    }

    // 文書の下の余白を、ナビゲーションバーと発話中の「.」の分に合わせる
    fun updateBottomPadding() {
        val bottomPadding = scroll.documentPaddingBottom()
        if (paddingBottom != bottomPadding) setPadding(paddingLeft, paddingTop, paddingRight, bottomPadding)
    }

    // ---------------------------------
    // 文字選択
    // ---------------------------------
    // 文字選択を解除する（refresh なら、選択中に止めていた本文の更新も反映する）
    fun clearTextSelection(refresh: Boolean = true) {
        updating = true
        selectionWithoutScrolling = null
        Selection.removeSelection(text as Spannable)
        clearFocus()
        snapshots.clear()
        updating = false
        if (refresh) update(latestArguments)
    }

    // 文字選択の範囲に、ブロックが1文字でも掛かっているか
    private fun selectionIntersects(block: MemoBlock): Boolean =
        hasSelection() && block.end > selectionFrom && block.start < selectionTo

    // 文書の中の位置を、ブロックと、その中の何文字目かに直す
    private fun blockPositionAt(offset: Int): BlockPosition? =
        blocks.firstOrNull { offset in it.start..it.end }?.let { BlockPosition(it.id, offset - it.start) }

    // ブロックの中の位置を、今の文書の中の位置に直す（本文が縮んでいたら末尾に留める）
    private fun documentOffsetOf(position: BlockPosition): Int? =
        blocks.firstOrNull { it.id == position.blockId }
            ?.let { it.start + min(position.offsetInBlock, it.end - it.start) }

    // 差し替える前の選択範囲を、同じメモの同じ位置へ置き直す
    private fun restoreSelection(startPosition: BlockPosition, endPosition: BlockPosition) {
        val start = documentOffsetOf(startPosition) ?: return
        val end = documentOffsetOf(endPosition) ?: return
        if (end > start) setSelectionWithoutScrolling(start, end)
    }

    // 選択末尾を見せるための移動は、つまみなどで範囲を動かすまで抑える
    private fun setSelectionWithoutScrolling(start: Int, end: Int) {
        selectionWithoutScrolling = start to end
        Selection.setSelection(text as Spannable, start, end)
    }

    override fun bringPointIntoView(offset: Int): Boolean {
        if (selectionWithoutScrolling == currentSelection) return false
        return super.bringPointIntoView(offset)
    }

    @TargetApi(34)
    override fun bringPointIntoView(offset: Int, requestRectWithoutFocus: Boolean): Boolean {
        if (selectionWithoutScrolling == currentSelection) return false
        return super.bringPointIntoView(offset, requestRectWithoutFocus)
    }

    // OS が選択色を付けている面（ブロック間の余白も含む）に、点が入っているか
    private fun selectionContains(x: Float, y: Float): Boolean {
        val textLayout = layout ?: return false
        if (!hasSelection()) return false
        val path = Path()
        textLayout.getSelectionPath(selectionFrom, selectionTo, path)
        val region = Region()
        region.setPath(path, Region(0, 0, textLayout.width, textLayout.height))
        return region.contains((x - totalPaddingLeft + scrollX).toInt(), (y - totalPaddingTop + scrollY).toInt())
    }

    // OS の操作で文字選択が変わったとき
    override fun onSelectionChanged(start: Int, end: Int) {
        super.onSelectionChanged(start, end)
        if (!initialized || updating) return
        if (selectionWithoutScrolling != (start to end)) selectionWithoutScrolling = null
        val from = min(start, end)
        val to = max(start, end)
        val touchedBlocks = copyableBlocksIn(from, to)
        if (start != end && from >= 0 && touchedBlocks.isNotEmpty()) {
            fitSelectionToBlocks(from, to, touchedBlocks)
            // 選択を始めた時点の本文を保ち、選択している間は本文を差し替えない
            for (block in blocks) if (block.selectable) snapshots.putIfAbsent(block.id, block.text)
        } else if (snapshots.isNotEmpty() || (from >= 0 && start != end)) {
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

    // 選択が外れた（または本文に掛からない選択になった）ら、OS の処理を終えてから選択を畳み、止めていた本文の更新を反映する
    private fun collapseSelectionLater(start: Int, end: Int) {
        post {
            if (selectionStart != start || selectionEnd != end) return@post
            updating = true
            if (hasSelection()) Selection.setSelection(text as Spannable, max(0, start))
            snapshots.clear()
            updating = false
            update(latestArguments)
        }
    }

    // メニューの「コピー」「すべて選択」は、ブロックの区切りと打ち出し中のメモを踏まえてアプリ側で行う
    override fun onTextContextMenuItem(id: Int): Boolean {
        when (id) {
            android.R.id.copy -> copySelection()
            android.R.id.selectAll -> selectAllCopyableBlocks()
            else -> return super.onTextContextMenuItem(id)
        }
        return true
    }

    // 選択範囲に掛かる各メモの部分を取り出し、区切りでつないでクリップボードへ入れる
    private fun copySelection() {
        val from = selectionFrom
        val to = selectionTo
        val pieces = copyableBlocksIn(from, to)
            .map { it.text.substring(max(from, it.start) - it.start, min(to, it.end) - it.start) }
        if (pieces.isEmpty()) return
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("", pieces.joinToString(copySeparator)))
    }

    // 文字選択の対象になるメモ全件を、表示位置を保ったまま選ぶ
    private fun selectAllCopyableBlocks() {
        val copyable = copyableBlocks()
        if (copyable.isEmpty()) return
        setSelectionWithoutScrolling(copyable.first().start, copyable.last().end)
    }

    // ---------------------------------
    // 行高・ブロック間隔の span を、変わったブロックだけ付け直す
    // ---------------------------------
    // span の付け外しのたびに行が組み直されるため、全ブロックを毎回付け直すと表示の更新ごとに文書全体を組み直すことになる
    private fun syncBlockSpans(document: SpannableStringBuilder) {
        val lineHeight = bodyLineHeight
        // --- 一覧から消えたブロックの span を外す
        val blockIds = blocks.map { it.id }.toSet()
        for (removedId in lineHeightSpans.keys - blockIds) {
            lineHeightSpans.remove(removedId)?.let { document.removeSpan(it) }
        }
        // --- 各ブロックの span を、今の範囲と値に合わせる
        for ((index, block) in blocks.withIndex()) {
            val isLast = index + 1 == blocks.size
            // 最後のブロック以外は、後ろの改行まで含めてブロックの範囲とする
            val spanEnd = if (isLast) block.end else block.end + 1
            val spacing = if (isLast) 0 else dp(BLOCK_SPACING_DP)
            lineHeightSpans[block.id] =
                syncLineHeightSpan(document, lineHeightSpans[block.id], block.start, spanEnd, lineHeight, spacing)
        }
    }

    // 行高の span が今の範囲・値のままなら使い回し、違っていれば付け直す
    private fun syncLineHeightSpan(
        document: SpannableStringBuilder,
        current: MemoLineHeightSpan?,
        start: Int,
        end: Int,
        lineHeight: Int,
        spacing: Int,
    ): MemoLineHeightSpan {
        if (current != null && current.height == lineHeight && current.spacing == spacing &&
            document.getSpanStart(current) == start && document.getSpanEnd(current) == end
        ) {
            return current
        }
        current?.let { document.removeSpan(it) }
        return MemoLineHeightSpan(lineHeight, spacing).also {
            document.setSpan(it, start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    // ---------------------------------
    // ブロックの区切りの位置（上のブロックの最後の行の文字の下端と、このブロックの1行目の文字の上端のちょうど間）
    // ---------------------------------
    // 文字の上端・下端は、行高やブロック間隔の余白を含まない、フォントの ascent・descent の範囲
    private fun boundaryYs(): List<Float> {
        val textLayout = layout ?: return blocks.map { totalPaddingTop.toFloat() }
        val metrics = paint.fontMetrics
        fun baselineAt(offset: Int) =
            totalPaddingTop + textLayout.getLineBaseline(textLayout.getLineForOffset(offset)).toFloat()
        val glyphTops = blocks.map { baselineAt(it.start) + metrics.ascent }
        val boundaries = blocks.indices.map { index ->
            if (index == 0) {
                0f
            } else {
                val upperBottom = baselineAt(blocks[index - 1].end - 1) + metrics.descent
                (upperBottom + glyphTops[index]) / 2
            }
        }.toMutableList()
        // 一番上のブロックには上のブロックがないので、2番目のブロックと同じだけ文字の上端から離す
        if (blocks.isNotEmpty()) {
            val halfGap = if (blocks.size > 1) glyphTops[1] - boundaries[1] else dp(SINGLE_BLOCK_BOUNDARY_GAP_DP).toFloat()
            boundaries[0] = glyphTops[0] - halfGap
        }
        return boundaries
    }

    // 縦線の始まり（一番上のブロックの区切り）
    val railTop: Float?
        get() = boundaryYs().firstOrNull()

    // 高さ y より上で、一番近い区切りを持つブロック（どの区切りよりも上なら null）
    private fun blockWithBoundaryAbove(y: Float): MemoBlock? {
        val boundaries = boundaryYs()
        return blocks.indices.lastOrNull { boundaries[it] <= y }?.let { blocks[it] }
    }

    // 文書の高さ y にあるブロック（一番上の区切りより上なら、一番上のブロック）
    fun blockIdAt(y: Float): Long? = (blockWithBoundaryAbove(y) ?: blocks.firstOrNull())?.id

    // 最新のブロックと、その区切りの高さ（文書の座標）
    fun latestBlockBoundary(): Pair<Long, Float>? {
        val block = blocks.lastOrNull() ?: return null
        return block.id to boundaryYs().last()
    }

    // ---------------------------------
    // 発話中の「.」（最新のブロックの本文の続き、または次のブロックの1行目）
    // ---------------------------------
    // 本文1行の高さ（行高の span と同じ値）
    private val bodyLineHeight: Int
        get() = (fontPixels * LINE_HEIGHT_RATIO).roundToInt()

    // 次のブロックの1行目に出すあいだ、文書の下に空けておく高さ（ブロック間の余白 + 1行）
    val speakingDotsReservedHeight: Int
        get() = if (speakingDotsPlace == SpeakingDotsPlace.NEW_BLOCK) dp(BLOCK_SPACING_DP) + bodyLineHeight else 0

    private fun changeSpeakingDotsPlace(place: SpeakingDotsPlace?) {
        if (place == speakingDotsPlace) return
        speakingDotsPlace = place
        if (place == null) stopSpeakingDots() else startSpeakingDots()
    }

    // 0個から数え直す
    private fun startSpeakingDots() {
        removeCallbacks(advanceSpeakingDots)
        speakingDotCount = 0
        postDelayed(advanceSpeakingDots, SPEAKING_DOTS_INTERVAL_MS)
        invalidate()
    }

    private fun stopSpeakingDots() {
        removeCallbacks(advanceSpeakingDots)
        speakingDotCount = 0
        invalidate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (speakingDotsPlace != null) startSpeakingDots()
    }

    override fun onDetachedFromWindow() {
        removeCallbacks(advanceSpeakingDots)
        super.onDetachedFromWindow()
    }

    private fun drawSpeakingDots(canvas: Canvas) {
        val place = speakingDotsPlace ?: return
        val textLayout = layout ?: return
        // 文字選択中は本文の表示を止めているので、「.」も出さない
        if (hasSelection()) return
        val latestBlock = blocks.lastOrNull()
        speakingDotsPaint.textSize = paint.textSize
        val x: Float
        val baseline: Float
        val availableWidth: Float
        when (place) {
            SpeakingDotsPlace.APPEND -> {
                // 最後の行の文字の右端から、行の右端までに収める
                if (latestBlock == null || latestBlock.text.isEmpty()) return
                speakingDotsPaint.typeface = paint.typeface
                val textRight = textLayout.getPrimaryHorizontal(latestBlock.end)
                val line = textLayout.getLineForOffset(latestBlock.end)
                x = totalPaddingLeft + textRight
                baseline = totalPaddingTop + textLayout.getLineBaseline(line).toFloat()
                availableWidth = textLayout.width - textRight
            }
            SpeakingDotsPlace.NEW_BLOCK -> {
                speakingDotsPaint.typeface = paint.typeface
                // 本文の行と同じく、行高の余りを文字の上下に半分ずつ振り分けた位置にベースラインを置く
                val metrics = speakingDotsPaint.fontMetricsInt
                val extra = max(0, bodyLineHeight - (metrics.descent - metrics.ascent))
                val lineTop = totalPaddingTop + textLayout.height + (if (blocks.isEmpty()) 0 else dp(BLOCK_SPACING_DP))
                x = totalPaddingLeft.toFloat()
                baseline = (lineTop + extra / 2 - metrics.ascent).toFloat()
                availableWidth = textLayout.width.toFloat()
            }
        }
        // 折り返すと一覧の高さが変わって全体が上下するため、行に収まる数までしか増やさない
        val dotWidth = speakingDotsPaint.measureText(".")
        fittingDotCount = if (dotWidth > 0) min(SPEAKING_DOTS_MAX_COUNT, max(0, (availableWidth / dotWidth).toInt())) else 0
        if (speakingDotCount > fittingDotCount) speakingDotCount = 0
        if (speakingDotCount > 0) canvas.drawText(".".repeat(speakingDotCount), x, baseline, speakingDotsPaint)
    }

    // ---------------------------------
    // 描画
    // ---------------------------------
    override fun onDraw(canvas: Canvas) {
        // 縦線と横線は本文の後ろに描く
        drawRail(canvas)
        super.onDraw(canvas)
        drawSpeakingDots(canvas)
    }

    // 右の縦線と、日付の区切りの横線
    private fun drawRail(canvas: Canvas) {
        if (blocks.isEmpty()) return
        railPaint.strokeWidth = RAIL_WIDTH_DP * density
        // 親のスクロールでは描画が再実行されないため、見えていない部分も含めて全体を描く
        val boundaries = boundaryYs()
        // 縦線は、一番上のブロックの区切りから文書の下端まで1本で引く
        val x = width - dp(RAIL_X_FROM_RIGHT_DP).toFloat()
        canvas.drawLine(x, boundaries.first(), x, height.toFloat(), railPaint)
        // 横線は、その日の最初のブロックの区切りに、画面の端から端まで引く（一番上のブロックには引かない）
        for ((index, block) in blocks.withIndex()) {
            if (index == 0 || !block.startsDay) continue
            canvas.drawLine(0f, boundaries[index], width.toFloat(), boundaries[index], railPaint)
        }
    }

    // ---------------------------------
    // タッチ
    // ---------------------------------
    override fun onTouchEvent(event: MotionEvent): Boolean {
        // 判定だけを加え、長押し・ダブルタップ・ドラッグは TextView に渡す
        selectionTapDetector.onTouchEvent(event)
        return super.onTouchEvent(event)
    }

    // onTouchEvent を上書きしたときの lint の決まりに合わせて、performClick も上書きしておく
    override fun performClick(): Boolean = super.performClick()
}

// ---------------------------------
// 文書をスクロールし、右の縦線の上にスクロールつまみを重ねる。下端ではナビゲーションバーを避ける
// ---------------------------------
// つまみの上で指を置いてすぐ動かしたときだけドラッグとして奪う。それ以外（長押し・タップなど）は、文書側の文字選択の操作になる
private class MemoScrollView(context: Context) : ScrollView(context) {
    private val density = resources.displayMetrics.density
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private val longPressTimeout = ViewConfiguration.getLongPressTimeout()
    private val thumbPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    // --- つまみのドラッグ
    // つまみの上に指を置いた高さ（つまみの外に置いたときは null）
    private var thumbTouchDownY: Float? = null
    // ドラッグ中の、指の位置とつまみの中心のずれ
    private var thumbGrabOffset = 0f
    private var draggingThumb = false

    // --- つまみの位置の知らせ
    // つまみの高さと、その高さにあるブロックが変わったときに知らせる（背景の日付表示に使う。y は表示範囲の上端から測った dp）
    // scrolling は、指やつまみの操作でスクロールしたときだけ true
    var onThumbChanged: ((blockId: Long, y: Double, scrolling: Boolean) -> Unit)? = null
    // 最後に知らせたブロックと高さ（変わっていなければ知らせ直さない）
    private var reportedThumb: Pair<Long, Double>? = null
    // 最後に知らせたときのスクロール位置
    private var scrollYSeenByReport = 0
    // アプリ側がスクロールを動かしている最中か
    private var scrollingByApp = false

    // つまみの色（本文と同じ色）
    var thumbColor: Int = 0
        set(value) {
            field = value
            thumbPaint.color = value
            invalidate()
        }

    init {
        // 標準のスクロールバーの代わりに、つまみを出す
        isVerticalScrollBarEnabled = false
    }

    private fun dp(value: Int) = value * density

    private val documentView: MemoDocumentView?
        get() = getChildAt(0) as? MemoDocumentView

    private val scrollRange: Int
        get() = max(0, (documentView?.height ?: 0) - height)

    // ---------------------------------
    // つまみの位置（y は表示範囲の上端から測る）
    // ---------------------------------
    // 上端は、一番上までスクロールしたときの縦線の始まり（一番上のブロックの区切り）にそろえる
    private val trackTop: Float
        get() = documentView?.railTop ?: dp(THUMB_TRACK_MARGIN_DP)

    private val trackBottom: Float
        get() {
            val overlap = bottomSystemBarOverlap()
            val margin = if (overlap > 0) dp(THUMB_TRACK_MARGIN_ABOVE_NAV_BAR_DP) else dp(THUMB_TRACK_MARGIN_DP)
            return max(trackTop, height - overlap - margin)
        }

    private fun thumbCenterY(): Float {
        val progress = if (scrollRange > 0) scrollY.toFloat() / scrollRange else 0f
        return trackTop + (trackBottom - trackTop) * progress.coerceIn(0f, 1f)
    }

    // スクロールできないほど短いときは、つまみを出さない
    private fun thumbContains(x: Float, y: Float): Boolean =
        scrollRange > 0 && x >= width - dp(THUMB_TOUCH_WIDTH_DP) && abs(y - thumbCenterY()) <= dp(THUMB_TOUCH_HEIGHT_DP) / 2

    // ---------------------------------
    // ナビゲーションバーを避ける
    // ---------------------------------
    // 下端がナビゲーションバーに重なる高さ（ホームへ戻る操作の受付領域では掴みにくいため、つまみはその上までにする）
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

    // 文書の下の余白（ナビゲーションバーを避ける分と、発話中の「.」を次のブロックの位置に出す分）
    fun documentPaddingBottom(): Int {
        val speakingDotsHeight = documentView?.speakingDotsReservedHeight ?: 0
        return (bottomSystemBarOverlap() + dp(BODY_PADDING_BOTTOM_DP)).roundToInt() + speakingDotsHeight
    }

    // 一番下までスクロールしたときだけ、最新の行をナビゲーションバーの上へ離す（途中では下を通り抜けて流れる）
    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        documentView?.updateBottomPadding()
        reportThumb()
    }

    // 一番下を見ている間に一覧の高さが変わったときは、一番下のまま保つ
    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        val documentHeight = documentView?.height ?: 0
        val wasAtBottom = scrollY >= documentHeight - oldHeight - dp(AT_BOTTOM_TOLERANCE_DP)
        super.onSizeChanged(width, height, oldWidth, oldHeight)
        if (oldHeight > 0 && height != oldHeight && wasAtBottom) {
            post { scrollToByApp(max(0, (documentView?.height ?: 0) - this.height)) }
        }
    }

    // ---------------------------------
    // つまみの位置を Dart へ知らせる
    // ---------------------------------
    override fun onScrollChanged(left: Int, top: Int, oldLeft: Int, oldTop: Int) {
        super.onScrollChanged(left, top, oldLeft, oldTop)
        reportThumb()
    }

    // スクロールできないほど短いとき（つまみを出さないとき）は、最新のブロックの区切りの高さとする
    fun reportThumb(force: Boolean = false) {
        // 前回から表示位置が動いていれば、指やつまみの操作でスクロールしている
        val scrolling = !scrollingByApp && scrollY != scrollYSeenByReport
        scrollYSeenByReport = scrollY
        val document = documentView ?: return
        val (blockId, documentY) = if (scrollRange > 0) {
            val thumbY = scrollY + thumbCenterY()
            (document.blockIdAt(thumbY) ?: return) to thumbY
        } else {
            document.latestBlockBoundary() ?: return
        }
        val y = ((documentY - scrollY) / density).toDouble()
        val reported = reportedThumb
        if (!force && !scrolling && reported != null && reported.first == blockId && abs(reported.second - y) < 0.5) return
        reportedThumb = blockId to y
        onThumbChanged?.invoke(blockId, y, scrolling)
    }

    // アプリ側が動かすスクロール（新しいメモで末尾へ移るときなど）は、スクロール中の日付表示の対象にしない
    // scrollTo の中で onScrollChanged が呼ばれるので、その間だけ印を立てておく
    fun scrollToByApp(y: Int) {
        scrollingByApp = true
        scrollTo(0, y)
        scrollingByApp = false
    }

    // ---------------------------------
    // つまみのドラッグ
    // ---------------------------------
    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            thumbTouchDownY = if (thumbContains(event.x, event.y)) event.y else null
        }
        val downY = thumbTouchDownY ?: return super.onInterceptTouchEvent(event)
        when (event.actionMasked) {
            // 指を置いてすぐ動かしたときだけ掴む（動かさずに待てば、本文の長押しとして文字選択になる）
            MotionEvent.ACTION_MOVE -> {
                val moved = abs(event.y - downY) > touchSlop
                val beforeLongPress = event.eventTime - event.downTime < longPressTimeout
                if (moved && beforeLongPress) {
                    startThumbDrag(event, downY)
                    return true
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> thumbTouchDownY = null
        }
        // つまみの上では、OS のスクロールに奪わせない
        return false
    }

    private fun startThumbDrag(event: MotionEvent, downY: Float) {
        // 慣性スクロールが残っていると指の位置と取り合うため、指を置いてすぐ離した扱いにして止める
        val stop = MotionEvent.obtain(event)
        stop.action = MotionEvent.ACTION_DOWN
        super.onTouchEvent(stop)
        stop.action = MotionEvent.ACTION_CANCEL
        super.onTouchEvent(stop)
        stop.recycle()
        // 指を置いた位置とつまみの中心のずれを保ったまま動かす
        thumbGrabOffset = downY - thumbCenterY()
        draggingThumb = true
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!draggingThumb) return super.onTouchEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_MOVE -> {
                val trackLength = trackBottom - trackTop
                if (trackLength > 0) {
                    val progress = (event.y - thumbGrabOffset - trackTop) / trackLength
                    scrollTo(0, (progress.coerceIn(0f, 1f) * scrollRange).roundToInt())
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                draggingThumb = false
                thumbTouchDownY = null
            }
        }
        return true
    }

    // ---------------------------------
    // つまみの描画
    // ---------------------------------
    // つまみは本文の後ろに描くため、文書（子の View）より先に描く
    override fun dispatchDraw(canvas: Canvas) {
        drawThumb(canvas)
        super.dispatchDraw(canvas)
    }

    private fun drawThumb(canvas: Canvas) {
        if (scrollRange == 0) return
        // canvas は文書の座標なので、表示範囲の上端（scrollY）を足す
        val centerX = width - dp(RAIL_X_FROM_RIGHT_DP)
        val centerY = scrollY + thumbCenterY()
        val halfWidth = dp(THUMB_WIDTH_DP) / 2
        val halfThickness = THUMB_THICKNESS_DP * density / 2
        canvas.drawRect(centerX - halfWidth, centerY - halfThickness, centerX + halfWidth, centerY + halfThickness, thumbPaint)
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
