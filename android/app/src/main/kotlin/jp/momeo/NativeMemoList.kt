package jp.momeo

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.Typeface
import android.text.Editable
import android.text.InputFilter
import android.text.InputType
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.TextWatcher
import android.text.style.LineHeightSpan
import android.text.style.UpdateLayout
import android.util.TypedValue
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.view.WindowInsets
import android.view.WindowInsetsAnimation
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ScrollView
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
//   メモ全件を時系列順に並べた1つの EditText にし、文字選択・つまみ・メニュー・スクロール・編集は OS に任せる。
//   1つのメモが1つの段落で、改行が段落の区切り。本文をタップすると、メモ帳のように書き直せる。
//   右の縦線と日付の区切りの横線、スクロールつまみ、発話中の「.」はアプリ側で描く。
//   Dart 側は lib/widgets/native_memo_list.dart。
// ============================================================

// ---------------------------------
// 定数: Dart 側とのやり取り
// ---------------------------------

// Dart から呼ばれるメソッド
private const val METHOD_UPDATE = "update"

// Dart へ知らせるメソッド
private const val METHOD_EDITING_STARTED = "editingStarted"
private const val METHOD_EDITING_ENDED = "editingEnded"

// Dart から値が届かなかったときの既定値
private const val DEFAULT_FONT_SIZE = 18f
private val DEFAULT_TEXT_COLOR = 0xff111827.toInt()
private val DEFAULT_RAIL_COLOR = 0xffcfd1d4.toInt()
private const val DEFAULT_COPY_SEPARATOR = "\n\n"

// ---------------------------------
// 定数: 本文（dp。iOS 側の pt とそろえる）
// ---------------------------------

// 本文の左右の余白（右も左と同じ。縦線は本文の後ろを通す）
private const val BODY_PADDING_LEFT_DP = 8
private const val BODY_PADDING_RIGHT_DP = 8

// 本文の上の余白（ステータスバーに重なる分は、これに足す）
private const val BODY_PADDING_TOP_DP = 24

// 本文の下の余白（ナビゲーションバーに重なる分は、これに足す）
private const val BODY_PADDING_BOTTOM_DP = 24

// 本文1行の高さ（文字サイズに対する倍率）。iOS はヒラギノの leading が1.5倍の行高に上乗せされて約2倍に見えるため、それに合わせる
private const val LINE_HEIGHT_RATIO = 2f

// ブロックとブロックの間の余白
private const val BLOCK_SPACING_DP = 24
// カーソルの高さ（文字サイズに対する倍率。iOS の、文字の上端から下端までの高さ×1.4 と見た目をそろえる）
private const val CURSOR_HEIGHT_RATIO = 1.4f

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
// ---------------------------------
// 定数: キーボードをしまう丸いボタン（dp。iOS とそろえる）
// ---------------------------------
// ボタンの直径と、キーボード・画面の右端からの距離
private const val KEYBOARD_DISMISS_DIAMETER_DP = 48
private const val KEYBOARD_DISMISS_MARGIN_DP = 8
// ボタンの影の高さ
private const val KEYBOARD_DISMISS_ELEVATION_DP = 4f

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

// Dart から届いたメモ1件
private data class IncomingMemo(
    val id: Long,
    val text: String,
    // 書き直せるか（打ち出し中は書き直せない）
    val selectable: Boolean,
    // その日の最初のメモか（日付の区切りの横線は、その日の最初のメモの上にだけ引く）
    val startsDay: Boolean,
)

// 文書の中の1段落（編集の間は、分けたりつなげたりした後の段落）
private data class MemoBlock(
    // 段落の文字が元々どのメモの文字だったか（出てくる順。手で書き足しただけの文字には無い）
    val sourceIds: List<Long>,
    // 表示している本文
    val text: String,
    // その日の最初の段落か
    val startsDay: Boolean,
    // 文書の中での本文の範囲（start 以上 end 未満。区切りの改行を含まない）
    val start: Int,
    val end: Int,
)

// 1回の編集（書き始めてから、保存した文書が Dart から届くまで）
private data class EditSession(
    // 書き始めた時点で書き直せたメモ（打ち出し中のメモを除く）。これ以外のメモは、文書の末尾に Dart の本文のまま出す
    val editableIds: Set<Long>,
    // 保存を頼んだあと、届くのを待っている文書の editRevision（書いている間は null）
    var awaitedRevision: Int? = null,
) {
    // 書き終えて、保存した文書が届くのを待っているか
    val isWaitingForSave: Boolean
        get() = awaitedRevision != null
}

// 文字に付ける印: その文字が元々どのメモの文字だったか
private class MemoIdSpan(val id: Long)

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

// ---------------------------------
// メモ一覧の View と、Dart とのやり取り
// ---------------------------------
private class NativeMemoList(context: Context, viewId: Int, messenger: BinaryMessenger, args: Any?) : PlatformView {
    private val channel = MethodChannel(messenger, "${NativeMemoListFactory.VIEW_TYPE}/$viewId")
    // 文字選択のつまみ・メニューが、OS 標準の見た目で出るようにする
    private val themedContext = ContextThemeWrapper(context, android.R.style.Theme_Material_Light_NoActionBar)
    private val scroll = MemoScrollView(themedContext)
    private val document = MemoDocumentView(themedContext, scroll)
    // 一覧と、書いている間だけ一覧の右下（キーボードのすぐ上）に重ねて出す、キーボードをしまうボタン
    private val container = FrameLayout(themedContext)
    private val keyboardDismissButton = MemoKeyboardDismissButton(themedContext)

    init {
        scroll.isFillViewport = true
        scroll.addView(
            document,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT),
        )
        container.addView(scroll, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        addKeyboardDismissButton()
        followKeyboard()
        document.onEditingStarted = {
            keyboardDismissButton.visibility = View.VISIBLE
            channel.invokeMethod(METHOD_EDITING_STARTED, null)
        }
        document.onEditingEnded = { edited ->
            keyboardDismissButton.visibility = View.GONE
            channel.invokeMethod(METHOD_EDITING_ENDED, edited)
        }
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

    override fun getView(): View = container

    // ボタンは一覧の右下に置き、キーボードが出ている間はキーボードの上端まで持ち上げる（→ applyKeyboardInsets）
    //   ボタンの外は一覧そのものなので、本文はボタンの横にも出て、これまでどおり触れる
    private fun addKeyboardDismissButton() {
        val density = themedContext.resources.displayMetrics.density
        val diameter = (KEYBOARD_DISMISS_DIAMETER_DP * density).roundToInt()
        val margin = (KEYBOARD_DISMISS_MARGIN_DP * density).roundToInt()
        val params = FrameLayout.LayoutParams(diameter, diameter, Gravity.BOTTOM or Gravity.END)
        params.setMargins(margin, margin, margin, margin)
        keyboardDismissButton.visibility = View.GONE
        keyboardDismissButton.setOnClickListener { document.finishEditing() }
        container.addView(keyboardDismissButton, params)
    }

    // ---------------------------------
    // キーボードとの重なり
    // ---------------------------------
    // 一覧の大きさは変えず（Flutter に縮めさせると、閉じるときに本文が何回かに分けてずれる）、
    // キーボードの動きに1コマずつ合わせて、隠れる分だけ一覧の下を空け、ボタンを持ち上げる
    private var keyboardAnimating = false

    private fun followKeyboard() {
        container.setWindowInsetsAnimationCallback(object :
            WindowInsetsAnimation.Callback(DISPATCH_MODE_CONTINUE_ON_SUBTREE) {
            override fun onPrepare(animation: WindowInsetsAnimation) {
                if (animation.typeMask and WindowInsets.Type.ime() != 0) keyboardAnimating = true
            }

            override fun onProgress(insets: WindowInsets, runningAnimations: MutableList<WindowInsetsAnimation>): WindowInsets {
                if (runningAnimations.any { it.typeMask and WindowInsets.Type.ime() != 0 }) applyKeyboardInsets(insets)
                return insets
            }

            override fun onEnd(animation: WindowInsetsAnimation) {
                if (animation.typeMask and WindowInsets.Type.ime() == 0) return
                keyboardAnimating = false
                container.rootWindowInsets?.let { applyKeyboardInsets(it) }
            }
        })
        // 動きを伴わない変化（キーボードの高さの切り替えなど）は、届いた値をそのまま使う。動いている間は、動きの終わりの値が先に届くので使わない
        container.setOnApplyWindowInsetsListener { _, insets ->
            if (!keyboardAnimating) applyKeyboardInsets(insets)
            insets
        }
    }

    private fun applyKeyboardInsets(insets: WindowInsets) {
        val keyboardBottom = insets.getInsets(WindowInsets.Type.ime()).bottom
        val location = IntArray(2)
        container.getLocationInWindow(location)
        val spaceBelow = container.rootView.height - (location[1] + container.height)
        val overlap = max(0, keyboardBottom - spaceBelow)
        keyboardDismissButton.translationY = -overlap.toFloat()
        scroll.updateKeyboardOverlap(overlap)
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        document.onEditingStarted = null
        document.onEditingEnded = null
        document.clearFocus()
    }
}

// ---------------------------------
// 本文（メモ全件を1つにした文書）と、右の縦線・日付の区切りの横線、発話中の「.」
// ---------------------------------
private class MemoDocumentView(context: Context, private val scroll: MemoScrollView) : EditText(context) {
    // 書き始めたことを知らせる
    var onEditingStarted: (() -> Unit)? = null
    // 書き終えた文書を知らせる（editedIds と、段落ごとの text・sourceIds）
    var onEditingEnded: ((Map<String, Any>) -> Unit)? = null

    private val density = resources.displayMetrics.density

    // --- 文書
    // 表示中の段落（上から順）
    private var blocks = listOf<MemoBlock>()
    // 最後に Dart から届いたメモ（古い順）
    private var incomingMemos = listOf<IncomingMemo>()
    // 最後に Dart から届いた文書の editRevision（編集を保存し終えるたびに Dart 側で増える）
    private var editRevision = 0
    // 本文の文字サイズ（px）
    private var fontPixels = DEFAULT_FONT_SIZE
    // 最初の表示で、一番下（最新）までスクロールする前か
    private var initialScrollPending = true

    // --- 編集
    // 編集の途中か（書き始めてから、保存した文書が届くまで）
    private var editSession: EditSession? = null
    // 日本語入力の変換中に届いて、出し直しを後回しにした末尾の段落があるか
    private var pendingLiveTail = false
    // 文書をアプリが組み直している間は、書き換えを断る決まりと、書き換えの知らせを素通りさせる
    private var updating = false
    // 段落をまたいでコピーしたときの区切り
    private var copySeparator = DEFAULT_COPY_SEPARATOR
    // キーボードが出ていたか（下ろされたら編集を終える）
    private var imeWasVisible = false

    // --- 行高と、縦線・横線
    // 文書全体に付けている行高の span
    private var lineHeightSpan: MemoLineHeightSpan? = null
    // 縦線と横線を描く絵の具（背景の波線と同じ色）
    private val dayDividerPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    // --- 選択の色（OS の色の帯は段落の上の余白まで塗るので透明にし、自前で塗る）
    private val selectionPaint = Paint()

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

    // キーボードが下ろされたら、編集を終える（戻るの操作で下ろしても、EditText は focus を持ったままになるため）
    private val imeWatcher = ViewTreeObserver.OnGlobalLayoutListener {
        val imeVisible = rootWindowInsets?.isVisible(WindowInsets.Type.ime()) == true
        if (imeWasVisible && !imeVisible && isFocused) clearFocus()
        imeWasVisible = imeVisible
    }

    init {
        // メモが少ないうちは、一覧を下に寄せる
        gravity = Gravity.BOTTOM or Gravity.START
        // 複数行の文章として書く。話した言葉には辞書に無い言葉が多いので、候補による下線は出さない
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or
            InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        // 横向きでも、キーボードの上に全画面の入力欄を出さない
        imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI
        includeFontPadding = false
        setPadding(dp(BODY_PADDING_LEFT_DP), dp(BODY_PADDING_TOP_DP), dp(BODY_PADDING_RIGHT_DP), 0)
        // EditText の下線を出さない
        setBackgroundColor(android.graphics.Color.TRANSPARENT)
        typeface = loadFlutterAssetFont(REGULAR_FONT_ASSET)
        // カーソルは、OS の絵を文字の高さに縮めて描く
        textCursorDrawable?.let { setTextCursorDrawable(MemoCursorDrawable(it, this)) }
        selectionPaint.color = highlightColor
        highlightColor = android.graphics.Color.TRANSPARENT
        setText("", BufferType.EDITABLE)
        // 書き直せるのは、末尾の書き直せない段落より前だけ
        filters = arrayOf(InputFilter { _, _, _, dest, dstart, dend -> filterChange(dest, dstart, dend) })
        addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(text: CharSequence, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(text: CharSequence, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(editable: Editable) {
                if (!updating) onUserEdited()
            }
        })
    }

    private fun dp(value: Int) = (value * density).roundToInt()

    // Flutter の assets に同梱した書体を読み込む（読めなければ端末の標準の書体）
    private fun loadFlutterAssetFont(assetPath: String): Typeface {
        val assetKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)
        return runCatching { Typeface.createFromAsset(context.assets, assetKey) }.getOrDefault(Typeface.DEFAULT)
    }

    private val document: SpannableStringBuilder
        get() = text as SpannableStringBuilder

    // ---------------------------------
    // Dart から届いた文書で、表示を更新する
    // ---------------------------------
    fun update(arguments: Any?) {
        val data = arguments as? Map<*, *> ?: return
        val blockValues = data["blocks"] as? List<*> ?: return
        incomingMemos = parseMemos(blockValues)
        editRevision = (data["editRevision"] as? Number)?.toInt() ?: 0
        copySeparator = data["copySeparator"] as? String ?: DEFAULT_COPY_SEPARATOR

        // --- 文字の大きさ・色
        fontPixels = ((data["fontSize"] as? Number)?.toFloat() ?: DEFAULT_FONT_SIZE) * density
        val textColor = (data["textColor"] as? Number)?.toInt() ?: DEFAULT_TEXT_COLOR
        val railColor = (data["railColor"] as? Number)?.toInt() ?: DEFAULT_RAIL_COLOR
        changeSpeakingDotsPlace(SpeakingDotsPlace.fromKey(data["speakingDots"]))
        applyTextSizeAndColor(textColor, railColor)

        // --- 保存を頼んだ文書が届いたら、編集を終える
        val awaited = editSession?.awaitedRevision
        if (awaited != null && editRevision >= awaited) editSession = null

        // --- 編集の途中は、書き直している段落を置き換えず、末尾の書き直せない段落だけを出し直す
        if (editSession != null) {
            applyLiveTail()
            return
        }
        applyWholeDocument()
        // 保存を待っている間にまた触れていたら、そのまま次の編集を始める
        if (isFocused) beginEditing()
    }

    // Dart から届いたメモの一覧（形の合わないものは飛ばす）
    private fun parseMemos(values: List<*>): List<IncomingMemo> = values.mapNotNull { value ->
        val item = value as? Map<*, *> ?: return@mapNotNull null
        val id = (item["id"] as? Number)?.toLong() ?: return@mapNotNull null
        IncomingMemo(
            id = id,
            text = item["text"] as? String ?: "",
            selectable = item["selectable"] != false,
            startsDay = item["startsDay"] != false,
        )
    }

    // 本文・縦線・横線・「.」・つまみの色と、本文の文字サイズ
    private fun applyTextSizeAndColor(textColor: Int, railColor: Int) {
        setTextSize(TypedValue.COMPLEX_UNIT_PX, fontPixels)
        setTextColor(textColor)
        dayDividerPaint.color = railColor
        speakingDotsPaint.color = textColor
        scroll.railColor = railColor
        scroll.thumbColor = textColor
    }

    // メモを改行1つでつないだ文字列と、メモごとの本文の範囲（start 以上 end 未満）
    //   leadingSeparator なら、前に別の段落が続く前提で、先頭にも区切りの改行を置く
    private fun buildText(memos: List<IncomingMemo>, leadingSeparator: Boolean = false): Pair<String, List<IntRange>> {
        val builder = StringBuilder()
        val ranges = mutableListOf<IntRange>()
        for ((index, memo) in memos.withIndex()) {
            if (index > 0 || leadingSeparator) builder.append('\n')
            val start = builder.length
            // 空のメモにも1行分の高さを持たせる
            builder.append(memo.text.ifEmpty { EMPTY_BLOCK_TEXT })
            ranges.add(start until builder.length)
        }
        return builder.toString() to ranges
    }

    // Dart から届いたメモで、文書全体を組み直す（本文は変わったところから後ろだけを差し替え、スクロール位置を保つ）
    private fun applyWholeDocument() {
        val wasAtBottom = scroll.scrollY >= scroll.maxScrollY - dp(AT_BOTTOM_TOLERANCE_DP)
        val oldScrollY = scroll.scrollY
        val (newText, ranges) = buildText(incomingMemos)

        updating = true
        replaceChangedTail(newText)
        // メモの印を付け直す（メモの境目で書き足した文字が、隣のメモの印に入ったままにならないように）
        for (span in memoIdSpans()) document.removeSpan(span)
        setMemoIdSpans(incomingMemos, ranges, offset = 0, flags = Spanned.SPAN_INCLUSIVE_INCLUSIVE)
        syncLineHeightSpan()
        // 次のブロックの1行目に「.」を出すあいだは、その分の高さを文書の下に空けておく
        updateVerticalPadding()
        updating = false
        rebuildBlocksFromText()
        requestLayout()
        invalidate()

        // --- 組み直した後の高さで、スクロール位置を決める（最初と、一番下を見ていたときは最新へ）
        val scrollsToLatest = initialScrollPending || wasAtBottom
        initialScrollPending = false
        scrollBeforeNextDraw(toLatest = scrollsToLatest, keptScrollY = oldScrollY)
    }

    // 新しい高さを測り終えて描く直前にスクロールする（post だと測る前の高さで位置を決めてしまい、一度ずれて描かれてから跳ねる）
    private fun scrollBeforeNextDraw(toLatest: Boolean, keptScrollY: Int) {
        scroll.viewTreeObserver.addOnPreDrawListener(object : ViewTreeObserver.OnPreDrawListener {
            override fun onPreDraw(): Boolean {
                scroll.viewTreeObserver.removeOnPreDrawListener(this)
                scroll.scrollTo(0, if (toLatest) scroll.maxScrollY else keptScrollY)
                return true
            }
        })
    }

    // 前と同じ先頭部分は置き直さず、変わったところから後ろだけを差し替える
    private fun replaceChangedTail(newText: String) {
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

    // 行高と段落の間の余白の span を、文書全体に1つだけ付ける（値と範囲が変わったときだけ付け直す。付け直すと文書全体を組み直すため）
    private fun syncLineHeightSpan() {
        val lineHeight = bodyLineHeight
        val spacing = dp(BLOCK_SPACING_DP)
        val current = lineHeightSpan
        if (current != null && current.height == lineHeight && current.spacing == spacing &&
            document.getSpanStart(current) == 0 && document.getSpanEnd(current) == document.length
        ) {
            return
        }
        current?.let { document.removeSpan(it) }
        lineHeightSpan = MemoLineHeightSpan(lineHeight, spacing).also {
            document.setSpan(it, 0, document.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
        }
    }

    // 文書に付いているメモの印（全部）
    private fun memoIdSpans(): Array<MemoIdSpan> = document.getSpans(0, document.length, MemoIdSpan::class.java)

    // メモごとの本文の範囲（offset だけずらした位置）に、メモの印を付ける
    private fun setMemoIdSpans(memos: List<IncomingMemo>, ranges: List<IntRange>, offset: Int, flags: Int) {
        for ((index, memo) in memos.withIndex()) {
            val range = ranges[index]
            document.setSpan(MemoIdSpan(memo.id), offset + range.first, offset + range.last + 1, flags)
        }
    }

    // 今の文書を段落に分け、段落ごとの範囲と、元のメモを求め直す
    private fun rebuildBlocksFromText() {
        val content = document.toString()
        if (content.isEmpty()) {
            blocks = emptyList()
            return
        }
        val startsDayById = incomingMemos.associate { it.id to it.startsDay }
        val seenFirstIds = mutableSetOf<Long>()
        val rebuilt = mutableListOf<MemoBlock>()
        var start = 0
        for (part in content.split('\n')) {
            val end = start + part.length
            // 段落に1文字でも掛かる印（出てくる順）
            val sourceIds = if (end > start) {
                document.getSpans(start, end, MemoIdSpan::class.java)
                    .filter { document.getSpanStart(it) < document.getSpanEnd(it) }
                    .sortedBy { document.getSpanStart(it) }
                    .map { it.id }
                    .distinct()
            } else {
                emptyList()
            }
            // 段落を分けたときは、同じメモから来た段落のうち、最初の段落にだけ日付の区切りを引く
            val firstId = sourceIds.firstOrNull()
            val startsDay = firstId != null && seenFirstIds.add(firstId) && startsDayById[firstId] == true
            rebuilt.add(MemoBlock(sourceIds, part, startsDay, start, end))
            start = end + 1
        }
        blocks = rebuilt
    }

    // 文書の上下の余白を、ステータスバー・ナビゲーションバーと発話中の「.」の分に合わせる
    fun updateVerticalPadding() {
        val topPadding = scroll.documentPaddingTop()
        val bottomPadding = scroll.documentPaddingBottom()
        if (paddingTop != topPadding || paddingBottom != bottomPadding) {
            setPadding(paddingLeft, topPadding, paddingRight, bottomPadding)
        }
    }

    // ---------------------------------
    // 編集: 始まりと終わり
    // ---------------------------------
    override fun onFocusChanged(focused: Boolean, direction: Int, previouslyFocusedRect: Rect?) {
        super.onFocusChanged(focused, direction, previouslyFocusedRect)
        if (focused) beginEditing() else endEditing()
    }

    // 書き始める（保存を待っている間は、待ち終えてから始める）
    private fun beginEditing() {
        if (editSession != null) return
        val editableIds = incomingMemos.filter { it.selectable }.map { it.id }.toSet()
        editSession = EditSession(editableIds)
        onEditingStarted?.invoke()
    }

    // 書き終えたら、書き直せた範囲の段落を Dart へ渡して保存を頼む（保存した文書が届くまでは、書いた本文を出し続ける）
    private fun endEditing() {
        val session = editSession ?: return
        if (session.isWaitingForSave) return
        if (pendingLiveTail) applyLiveTail()
        rebuildBlocksFromText()
        session.awaitedRevision = editRevision + 1
        onEditingEnded?.invoke(editedDocument(session.editableIds))
    }

    // Dart へ渡す、書き終えた文書（editedIds と、書き直せた範囲の段落ごとの text・sourceIds）
    private fun editedDocument(editableIds: Set<Long>): Map<String, Any> {
        val end = editableEnd()
        val paragraphs = blocks.filter { it.end <= end }.map { block ->
            mapOf("text" to block.text.replace(EMPTY_BLOCK_TEXT, ""), "sourceIds" to block.sourceIds)
        }
        return mapOf("editedIds" to editableIds.toList(), "paragraphs" to paragraphs)
    }

    // キーボードをしまうボタン: キーボードを下ろし、編集を終える
    fun finishEditing() {
        val inputMethodManager = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        inputMethodManager.hideSoftInputFromWindow(windowToken, 0)
        if (isFocused) clearFocus()
    }

    // 背面に回ったら、編集を終えて書いた分を保存する
    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        if (visibility != View.VISIBLE && isFocused) clearFocus()
    }

    // ---------------------------------
    // 編集: 書き直せる範囲と、末尾の書き直せない段落
    // ---------------------------------
    // 書き直せる範囲の終わり（その後ろは、打ち出し中のメモと、編集の間に増えたメモ。区切りの改行もそちらに含める）
    private fun editableEnd(): Int {
        val session = editSession ?: return document.length
        val liveStart = memoIdSpans()
            .filter { it.id !in session.editableIds }
            .minOfOrNull { document.getSpanStart(it) } ?: return document.length
        return if (liveStart > 0 && document[liveStart - 1] == '\n') liveStart - 1 else liveStart
    }

    // 書き換えの決まり（InputFilter）。認めるなら null、断るなら書き換え前の文字列を返す
    private fun filterChange(dest: Spanned, dstart: Int, dend: Int): CharSequence? {
        if (updating || allowsChange(dest, dend)) return null
        return if (dstart == dend) "" else dest.subSequence(dstart, dend)
    }

    // 書き換えてよいか（書いている間で、末尾の書き直せない段落に掛からないときだけ）
    private fun allowsChange(dest: Spanned, dend: Int): Boolean {
        val session = editSession ?: return false
        if (session.isWaitingForSave) return false
        val end = editableEnd()
        // 書き直せる段落が無いときに打つと、書き直せない段落の頭につながってしまうので打たせない
        if (end == 0 && dest.isNotEmpty()) return false
        return dend <= end
    }

    // 編集の途中に Dart から届いたメモのうち、書き直せないもの（打ち出し中・編集の間に増えたもの）を、文書の末尾に出し直す
    private fun applyLiveTail() {
        val session = editSession ?: return
        // 変換中に文書を差し替えると変換が崩れるので、変換を終えてから出し直す
        if (isComposing()) {
            pendingLiveTail = true
            return
        }
        pendingLiveTail = false
        val liveMemos = incomingMemos.filter { it.id !in session.editableIds }
        val end = editableEnd()
        val (tailText, ranges) = buildText(liveMemos, leadingSeparator = end > 0)
        val liveSpans = memoIdSpans().filter { it.id !in session.editableIds }
        if (document.substring(end) != tailText || liveSpans.size != liveMemos.size) {
            // 書き直せる段落の印は末尾の書き足しで伸びるので、差し替えた後に元の終わりへ戻す
            val editableSpansAtEnd = memoIdSpans().filter { it.id in session.editableIds && document.getSpanEnd(it) == end }
            updating = true
            for (span in liveSpans) document.removeSpan(span)
            document.replace(end, document.length, tailText)
            for (span in editableSpansAtEnd) {
                document.setSpan(span, document.getSpanStart(span), end, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            }
            setMemoIdSpans(liveMemos, ranges, offset = end, flags = Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            syncLineHeightSpan()
            updateVerticalPadding()
            updating = false
        }
        rebuildBlocksFromText()
        requestLayout()
        invalidate()
    }

    // 日本語入力の変換中か
    private fun isComposing(): Boolean = BaseInputConnection.getComposingSpanStart(document) >= 0

    // 利用者が文字を書き換えたとき
    private fun onUserEdited() {
        if (pendingLiveTail && !isComposing()) applyLiveTail()
        updating = true
        syncLineHeightSpan()
        updating = false
        rebuildBlocksFromText()
        invalidate()
    }

    // ---------------------------------
    // コピー
    // ---------------------------------
    // メニューの「コピー」は、段落の間に区切りを入れてアプリ側で行う
    override fun onTextContextMenuItem(id: Int): Boolean {
        if (id != android.R.id.copy) return super.onTextContextMenuItem(id)
        copySelection()
        return true
    }

    // 選択範囲を、段落の間に区切りを入れてクリップボードへ入れる
    private fun copySelection() {
        val from = min(selectionStart, selectionEnd)
        val to = max(selectionStart, selectionEnd)
        if (from < 0 || from == to) return
        val selected = document.substring(from, to).replace(EMPTY_BLOCK_TEXT, "")
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("", selected.split('\n').joinToString(copySeparator)))
    }

    // ---------------------------------
    // 段落の区切りの位置（上の段落の最後の行の文字の下端と、この段落の1行目の文字の上端のちょうど間）
    // ---------------------------------
    // 文字の上端・下端は、行高やブロック間隔の余白を含まない、フォントの ascent・descent の範囲
    private fun boundaryYs(): List<Float> {
        val textLayout = layout ?: return blocks.map { totalPaddingTop.toFloat() }
        val metrics = paint.fontMetrics
        fun baselineAt(offset: Int) =
            totalPaddingTop + textLayout.getLineBaseline(textLayout.getLineForOffset(max(0, offset))).toFloat()
        val glyphTops = blocks.map { baselineAt(it.start) + metrics.ascent }
        val boundaries = blocks.indices.map { index ->
            if (index == 0) {
                0f
            } else {
                // 空の段落は、その段落の位置で測る
                val upper = blocks[index - 1]
                val upperBottom = baselineAt(max(upper.start, upper.end - 1)) + metrics.descent
                (upperBottom + glyphTops[index]) / 2
            }
        }.toMutableList()
        // 一番上の段落には上の段落がないので、2番目の段落と同じだけ文字の上端から離す
        if (blocks.isNotEmpty()) {
            val halfGap = if (blocks.size > 1) glyphTops[1] - boundaries[1] else dp(SINGLE_BLOCK_BOUNDARY_GAP_DP).toFloat()
            boundaries[0] = glyphTops[0] - halfGap
        }
        return boundaries
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
        viewTreeObserver.addOnGlobalLayoutListener(imeWatcher)
        if (speakingDotsPlace != null) startSpeakingDots()
    }

    override fun onDetachedFromWindow() {
        viewTreeObserver.removeOnGlobalLayoutListener(imeWatcher)
        removeCallbacks(advanceSpeakingDots)
        super.onDetachedFromWindow()
    }

    private fun drawSpeakingDots(canvas: Canvas) {
        val place = speakingDotsPlace ?: return
        val textLayout = layout ?: return
        // 文字を選んでいる間は、「.」を出さない
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
        // 横線は本文の後ろに描く（縦線は一覧の枠の一部なので、スクロール側が描く）
        drawDayDividers(canvas)
        drawSelection(canvas)
        super.onDraw(canvas)
        drawSpeakingDots(canvas)
    }

    // ---------------------------------
    // カーソルと選択の色（段落の上の余白の分まで伸ばさない）
    // ---------------------------------
    // 行の下端から1行分の高さの真ん中（段落の上の余白は行の上に足しているので、どの行でも文字の上下の真ん中になる）
    //   文書の末尾の空の行は、行高が付かず1行分より低いので、その行の上下の真ん中
    fun textCenterY(lineTop: Int, lineBottom: Int): Int = lineBottom - min(bodyLineHeight, lineBottom - lineTop) / 2

    val cursorHeight: Int
        get() = (fontPixels * CURSOR_HEIGHT_RATIO).roundToInt()

    // 選んだ範囲を、本文の後ろに塗る
    //   1行目は文字の行の高さだけ塗り、2行目からは行の上端（段落の上の余白を含む）から塗って、上の行とつなげる
    private fun drawSelection(canvas: Canvas) {
        val textLayout = layout ?: return
        val from = min(selectionStart, selectionEnd)
        val to = max(selectionStart, selectionEnd)
        if (from < 0 || from == to) return
        val firstLine = textLayout.getLineForOffset(from)
        val lastLine = textLayout.getLineForOffset(to)
        val left = totalPaddingLeft.toFloat()
        val top = totalPaddingTop.toFloat()
        for (line in firstLine..lastLine) {
            val startX = if (line == firstLine) textLayout.getPrimaryHorizontal(from) else 0f
            val endX = if (line == lastLine) textLayout.getPrimaryHorizontal(to) else textLayout.width.toFloat()
            val lineBottom = textLayout.getLineBottom(line)
            val lineTop = if (line == firstLine) lineBottom - bodyLineHeight else textLayout.getLineTop(line)
            canvas.drawRect(left + startX, top + lineTop, left + endX, top + lineBottom, selectionPaint)
        }
    }

    // 日付の区切りの横線（その日の最初の段落の区切りに、画面の端から端まで引く。一番上の段落には引かない）
    private fun drawDayDividers(canvas: Canvas) {
        if (blocks.isEmpty()) return
        dayDividerPaint.strokeWidth = RAIL_WIDTH_DP * density
        // 親のスクロールでは描画が再実行されないため、見えていない部分も含めて全体を描く
        val boundaries = boundaryYs()
        for ((index, block) in blocks.withIndex()) {
            if (index == 0 || !block.startsDay) continue
            canvas.drawLine(0f, boundaries[index], width.toFloat(), boundaries[index], dayDividerPaint)
        }
    }
}


// ---------------------------------
// 文書をスクロールし、右の縦線（つまみのレール）とスクロールつまみを描く。下端ではナビゲーションバーを避ける
// ---------------------------------
// つまみの上で指を置いてすぐ動かしたときだけドラッグとして奪う。それ以外（長押し・タップなど）は、文書側の文字選択・編集の操作になる
private class MemoScrollView(context: Context) : ScrollView(context) {
    private val density = resources.displayMetrics.density
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private val longPressTimeout = ViewConfiguration.getLongPressTimeout()
    private val railPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val thumbPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    // --- つまみのドラッグ
    // つまみの上に指を置いた高さ（つまみの外に置いたときは null）
    private var thumbTouchDownY: Float? = null
    // ドラッグ中の、指の位置とつまみの中心のずれ
    private var thumbGrabOffset = 0f
    private var draggingThumb = false

    // 縦線の色（背景の波線と同じ色）
    var railColor: Int = 0
        set(value) {
            field = value
            railPaint.color = value
            invalidate()
        }

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
        // キーボードに隠れる分として下を空けたところにも、本文を描いて通り抜けさせる
        clipToPadding = false
    }

    private fun dp(value: Int) = value * density

    private val documentView: MemoDocumentView?
        get() = getChildAt(0) as? MemoDocumentView

    private val scrollRange: Int
        get() = maxScrollY

    // 一番下までスクロールしたときの位置（キーボードに隠れる分も、その上へスクロールできる）
    val maxScrollY: Int
        get() = max(0, (documentView?.height ?: 0) - (height - paddingBottom))

    // キーボードに隠れる高さ（ナビゲーションバーの分は、文書の下の余白で避けているので含めない）
    private var keyboardOverlap = 0

    // キーボードに隠れる分だけ一覧の下を空ける（閉じるときは、空きが縮むにつれて本文がなめらかに下りる）
    //   書いている間は、カーソルの行がキーボードに隠れないようにスクロールを合わせる
    fun updateKeyboardOverlap(overlapIncludingNavigationBar: Int) {
        val overlap = max(0, overlapIncludingNavigationBar - bottomSystemBarOverlap().roundToInt())
        if (overlap == keyboardOverlap) return
        keyboardOverlap = overlap
        setPadding(0, 0, 0, overlap)
        scrollTo(scrollX, min(scrollY, maxScrollY))
        val document = documentView ?: return
        val textLayout = document.layout ?: return
        if (!document.isFocused) return
        val line = textLayout.getLineForOffset(max(0, document.selectionEnd))
        val caretBottom = document.top + document.totalPaddingTop + textLayout.getLineBottom(line)
        val visibleBottom = scrollY + height - overlap
        if (caretBottom > visibleBottom) scrollTo(scrollX, min(maxScrollY, scrollY + caretBottom - visibleBottom))
    }

    // 打った文字やカーソルを見せるためのスクロールで、キーボードの裏を見えている範囲に数えない
    override fun computeScrollDeltaToGetChildRectOnScreen(rect: Rect): Int {
        val extended = Rect(rect)
        extended.bottom += keyboardOverlap
        return super.computeScrollDeltaToGetChildRectOnScreen(extended)
    }

    // ---------------------------------
    // つまみの位置（y は表示範囲の上端から測る）
    // ---------------------------------
    // 上端はステータスバーの下から動かす
    private val trackTop: Float
        get() = topSystemBarOverlap() + dp(THUMB_TRACK_MARGIN_DP)

    private val trackBottom: Float
        get() {
            // キーボードが出ている間は、キーボードの上端までにする
            val overlap = bottomSystemBarOverlap() + keyboardOverlap
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
    // ステータスバー・ナビゲーションバーを避ける
    // ---------------------------------
    // 上端がステータスバーに重なる高さ
    private fun topSystemBarOverlap(): Float {
        val insets = rootWindowInsets ?: return 0f
        val systemBarHeight = insets.getInsets(WindowInsets.Type.statusBars()).top
        val location = IntArray(2)
        getLocationInWindow(location)
        return max(0, systemBarHeight - location[1]).toFloat()
    }

    // 下端がナビゲーションバーに重なる高さ（ホームへ戻る操作の受付領域では掴みにくいため、つまみはその上までにする）
    private fun bottomSystemBarOverlap(): Float {
        val insets = rootWindowInsets ?: return 0f
        val systemBarHeight = insets.getInsets(WindowInsets.Type.navigationBars()).bottom
        val location = IntArray(2)
        getLocationInWindow(location)
        val spaceBelow = rootView.height - (location[1] + height)
        return max(0, systemBarHeight - spaceBelow).toFloat()
    }

    // 文書の上の余白（ステータスバーを避ける分）
    fun documentPaddingTop(): Int = (topSystemBarOverlap() + dp(BODY_PADDING_TOP_DP)).roundToInt()

    // 文書の下の余白（ナビゲーションバーを避ける分と、発話中の「.」を次のブロックの位置に出す分）
    fun documentPaddingBottom(): Int {
        val speakingDotsHeight = documentView?.speakingDotsReservedHeight ?: 0
        return (bottomSystemBarOverlap() + dp(BODY_PADDING_BOTTOM_DP)).roundToInt() + speakingDotsHeight
    }

    // 一番上・一番下までスクロールしたときだけ、端の行をステータスバー・ナビゲーションバーから離す
    // （途中では裏を通り抜けて流れる）
    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        documentView?.updateVerticalPadding()
    }

    // 一番下を見ている間に一覧の高さが変わったときは、一番下のまま保つ
    // 書いている間（画面の向きが変わったときなど）は、カーソルの行が見えるようにする
    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        val documentHeight = documentView?.height ?: 0
        val wasAtBottom = scrollY >= documentHeight - (oldHeight - paddingBottom) - dp(AT_BOTTOM_TOLERANCE_DP)
        super.onSizeChanged(width, height, oldWidth, oldHeight)
        if (oldHeight <= 0 || height == oldHeight) return
        val document = documentView ?: return
        if (document.isFocused) {
            post { document.bringPointIntoView(document.selectionEnd) }
        } else if (wasAtBottom) {
            post { scrollTo(0, maxScrollY) }
        }
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
    // 縦線とつまみの描画
    // ---------------------------------
    // 本文の後ろに描くため、文書（子の View）より先に描く
    override fun dispatchDraw(canvas: Canvas) {
        drawRail(canvas)
        drawThumb(canvas)
        super.dispatchDraw(canvas)
    }

    // 縦線は一覧の枠の一部として、スクロールしても動かさず、一覧の上端から下端まで引く（メモが無くても出す）
    private fun drawRail(canvas: Canvas) {
        railPaint.strokeWidth = RAIL_WIDTH_DP * density
        // canvas は文書の座標なので、表示範囲の上端（scrollY）を足す
        val x = width - dp(RAIL_X_FROM_RIGHT_DP)
        canvas.drawLine(x, scrollY.toFloat(), x, (scrollY + height).toFloat(), railPaint)
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
// 行高と段落の間の余白を本文のレイアウトに含める（文書全体に1つだけ付ける）
// ---------------------------------
// UpdateLayout を付けないと、付け外ししても TextView が行を組み直さず指定が反映されない
// 行高は、渡される fm ではなく書体そのものの値から求める（OS は直前の行で書き換えた fm を、同じ段落の次の行の初期値に使い回すため、
// そのまま足すと段落の上の余白が、折り返した2行目以降にも乗ってしまう）
private class MemoLineHeightSpan(val height: Int, val spacing: Int) : LineHeightSpan.WithDensity, UpdateLayout {
    override fun chooseHeight(
        text: CharSequence, start: Int, end: Int, spanstartv: Int, v: Int, fm: Paint.FontMetricsInt, paint: TextPaint,
    ) {
        val fontMetrics = paint.fontMetricsInt
        // 行高の余りを、文字の上下に半分ずつ振り分ける
        val extra = max(0, height - (fontMetrics.descent - fontMetrics.ascent))
        fm.ascent = fontMetrics.ascent - extra / 2
        fm.descent = fontMetrics.descent + extra - extra / 2
        // 段落の最初の行（改行の直後から始まる行）の上に、段落の間の余白を足す（文書の最初の段落の上には足さない）
        //   OS はカーソル・選択の色・つまみを行の上端から下端まで使って描くので、下に足すと、段落の最後の行だけそれらが余白の下まで伸びる
        if (start > 0 && text[start - 1] == '\n') fm.ascent -= spacing
        fm.top = fm.ascent
        fm.bottom = fm.descent
    }

    // OS は書体を渡せる上の方を呼ぶ。こちらは決まりとして実装するだけ
    override fun chooseHeight(text: CharSequence, start: Int, end: Int, spanstartv: Int, v: Int, fm: Paint.FontMetricsInt) {
        chooseHeight(text, start, end, spanstartv, v, fm, TextPaint())
    }
}

// ---------------------------------
// カーソル: OS のカーソルの絵を、行の上端から下端までではなく、文字の上下の真ん中に文字の高さ×倍率で描く
// ---------------------------------
// OS はこの絵の範囲を、行の上端（段落の上の余白を含む）から下端までにして渡してくる
private class MemoCursorDrawable(private val bar: Drawable, private val document: MemoDocumentView) : Drawable() {
    private val padding = Rect()

    override fun draw(canvas: Canvas) {
        bar.getPadding(padding)
        val centerY = document.textCenterY(bounds.top + padding.top, bounds.bottom - padding.bottom)
        val halfHeight = document.cursorHeight / 2
        bar.setBounds(bounds.left, centerY - halfHeight - padding.top, bounds.right, centerY + halfHeight + padding.bottom)
        bar.draw(canvas)
    }

    override fun getIntrinsicWidth(): Int = bar.intrinsicWidth
    override fun getPadding(padding: Rect): Boolean = bar.getPadding(padding)
    override fun setAlpha(alpha: Int) { bar.alpha = alpha }
    override fun setColorFilter(colorFilter: ColorFilter?) { bar.colorFilter = colorFilter }
    @Deprecated("Drawable の決まりで実装する")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}

// ---------------------------------
// キーボードをしまう丸いボタン（白い丸に影を付け、本文と同じ色のアイコンを載せる）
// ---------------------------------
private class MemoKeyboardDismissButton(context: Context) : ImageButton(context) {
    init {
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(android.graphics.Color.WHITE)
        }
        elevation = KEYBOARD_DISMISS_ELEVATION_DP * resources.displayMetrics.density
        setImageResource(R.drawable.ic_keyboard_hide)
        imageTintList = android.content.res.ColorStateList.valueOf(DEFAULT_TEXT_COLOR)
        scaleType = ScaleType.CENTER
        contentDescription = if (resources.configuration.locales[0].language == "ja") "キーボードを閉じる" else "Hide keyboard"
    }
}
