import Flutter
import UIKit

// ============================================================
// NativeMemoList — リスニング画面のメモ一覧（iOS）
//
//   メモ全件を時系列順に並べた1つの UITextView にし、文字選択・つまみ・メニュー・スクロールは OS に任せる。
//   右の縦線と丸（ブロック選択）、スクロールつまみはアプリ側で描く。
//   Dart 側は lib/widgets/native_memo_list.dart。
// ============================================================

// ---------------------------------
// 定数: Dart 側とのやり取り
// ---------------------------------
private enum ChannelMethod {
    // Dart から呼ばれるメソッド
    static let update = "update"
    static let clearSelection = "clearSelection"
    // Dart へ知らせるメソッド
    static let toggleBlock = "toggleBlock"
}

// Dart から値が届かなかったときの既定値
private enum DefaultValue {
    static let fontSize: Double = 18
    static let textColor: UInt32 = 0xff111827
    static let copySeparator = "\n\n"
}

// ---------------------------------
// 定数: 本文（pt。Android 側の dp とそろえる）
// ---------------------------------
private enum BodyLayout {
    // 本文の左右の余白（右は丸と縦線の領域を含む）
    static let paddingLeft: CGFloat = 12
    static let paddingRight: CGFloat = 34
    // 本文の上の余白の下限（メモが少ないうちは、残りを上に空けて一覧を下に寄せる）
    static let minPaddingTop: CGFloat = 24
    // 本文の下の余白（ホームインジケーターに重なる分は、これに足す）
    static let paddingBottom: CGFloat = 24
    // 本文1行の高さ（文字サイズに対する倍率）。ヒラギノの leading が上乗せされ、見た目は約2倍になる
    static let lineHeightRatio: CGFloat = 1.5
    // ブロックとブロックの間の余白
    static let blockSpacing: CGFloat = 24
    // 空のメモにも1行分の高さを持たせるために置く、幅の無い文字
    static let emptyBlockText = "\u{200B}"
    // 一番下からこの距離までにいれば、一番下を見ているとみなす
    static let atBottomTolerance: CGFloat = 32
    // 書体（選択していないとき・選択中）
    static let regularFontName = "HiraginoSans-W3"
    static let boldFontName = "HiraginoSans-W6"
}

// ---------------------------------
// 定数: 右の縦線と丸（pt）
// ---------------------------------
private enum RailLayout {
    // 縦線と丸を押せる領域の幅（一覧の右端から）
    static let touchWidth: CGFloat = 40
    // 縦線の位置（一覧の右端から）
    static let xFromRight: CGFloat = 18
    // 縦線の太さと丸の半径（選択していないとき・選択中）
    static let lineWidth: CGFloat = 1.5
    static let selectedLineWidth: CGFloat = 2.5
    static let circleRadius: CGFloat = 4
    static let selectedCircleRadius: CGFloat = 5.5
    // ブロックが1つだけのときに、丸を1行目の文字の上端から離す距離
    static let singleBlockCircleGap: CGFloat = 12
}

// ---------------------------------
// 定数: スクロールつまみ（pt）
// ---------------------------------
private enum ScrollThumbLayout {
    // 横棒の幅と太さ
    static let width: CGFloat = 24
    static let thickness: CGFloat = 1.5
    // 細い横棒でも掴めるよう、当たり判定は見た目より上下に広げる
    static let touchHeight: CGFloat = 44
    // つまみが動く範囲の上下の余白（下端がホームインジケーターに重なるときは広めにとる）
    static let trackMargin: CGFloat = 12
    static let trackMarginAboveHomeIndicator: CGFloat = 24
}

// ---------------------------------
// AppDelegate から登録する、メモ一覧の作り手
// ---------------------------------
final class NativeMemoListFactory: NSObject, FlutterPlatformViewFactory {
    // Dart 側（native_memo_list.dart）の View の種類名とそろえる
    static let viewType = "jp.momeo/native_memo_list"

    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        NativeMemoList(frame: frame, viewId: viewId, messenger: messenger, arguments: args)
    }
}

// 1件のメモを、文書の中の1ブロックとして扱うための情報
private struct MemoBlock {
    let id: Int64
    // 表示する本文（文字選択中は、選択を始めた時点の本文を保つ）
    var text: String
    // 丸で選ばれているか
    let selected: Bool
    // 文書の中での本文の範囲
    var range = NSRange(location: 0, length: 0)
}

// 文書の中の位置を、どのブロックの何文字目かで表したもの（本文を差し替えても選択範囲を置き直せるようにする）
private struct BlockPosition {
    let blockId: Int64
    let offsetInBlock: Int
}

// ---------------------------------
// メモ一覧の View と、Dart とのやり取り
// ---------------------------------
private final class NativeMemoList: NSObject, FlutterPlatformView {
    private let container = UIView()
    private let documentView = MemoDocumentView(frame: .zero, textContainer: nil)
    private let channel: FlutterMethodChannel

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, arguments: Any?) {
        channel = FlutterMethodChannel(name: "\(NativeMemoListFactory.viewType)/\(viewId)", binaryMessenger: messenger)
        super.init()
        container.frame = frame
        documentView.frame = container.bounds
        documentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(documentView)
        documentView.onToggleBlock = { [weak self] blockId in
            self?.channel.invokeMethod(ChannelMethod.toggleBlock, arguments: blockId)
        }
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(nil); return }
            switch call.method {
            case ChannelMethod.update:
                self.documentView.update(call.arguments)
                result(nil)
            case ChannelMethod.clearSelection:
                self.documentView.clearTextSelection()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        documentView.update(arguments)
    }

    func view() -> UIView { container }

    deinit { channel.setMethodCallHandler(nil) }
}

// ---------------------------------
// 本文（メモ全件を1つにした文書）と、右の縦線・丸、スクロールつまみ
// ---------------------------------
private final class MemoDocumentView: UITextView, UITextViewDelegate {
    // 丸が押されたブロックのメモ id を知らせる
    var onToggleBlock: ((Int64) -> Void)?

    // --- 文書
    // 表示中のブロック（古い順）
    private var blocks: [MemoBlock] = []
    // 最後に Dart から届いた文書（文字選択が外れたときに、止めていた更新を反映し直す）
    private var latestArguments: Any?
    // 本文の文字サイズと色
    private var bodySize = CGFloat(DefaultValue.fontSize)
    private var bodyColor = UIColor.label
    // まだ一度もレイアウトしていないか（最初の表示では、一番下（最新）までスクロールする）
    private var isFirstLayout = true
    // 前回のレイアウトでの大きさ
    private var lastLayoutSize = CGSize.zero
    // 文書の高さと丸の位置を測り直すか
    private var needsDocumentLayout = true

    // --- 文字選択
    // 文字選択中に、選択を始めた時点の本文を保つ（メモ id → 本文）
    private var snapshots: [Int64: String] = [:]
    // 文書を組み直している間は、選択の変化を OS の操作として扱わない
    private var updating = false
    // ブロックをまたいでコピーしたときの区切り
    private var copySeparator = DefaultValue.copySeparator

    // --- 右の縦線・丸と、スクロールつまみ
    private let rail = MemoRailView()
    // 丸の中心の高さ（メモ id → 文書の座標）
    private var circleCenterYs: [Int64: CGFloat] = [:]
    // ドラッグ中の、指の位置とつまみの中心のずれ
    private var scrollThumbGrabOffset: CGFloat = 0

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        // TextKit 1（NSLayoutManager）で組み、文書全体の高さを同じレイアウトから求める
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        super.init(frame: frame, textContainer: container)
        isEditable = false
        isSelectable = true
        backgroundColor = .clear
        contentInsetAdjustmentBehavior = .never
        self.textContainer.lineFragmentPadding = 0
        textContainerInset = UIEdgeInsets(top: BodyLayout.minPaddingTop, left: BodyLayout.paddingLeft,
                                          bottom: BodyLayout.paddingBottom, right: BodyLayout.paddingRight)
        alwaysBounceVertical = true
        // 標準のスクロールバーの代わりに、縦線の上のつまみを出す
        showsVerticalScrollIndicator = false
        delegate = self
        rail.document = self
        addSubview(rail)
        rail.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapRail(_:))))
        rail.addGestureRecognizer(MemoScrollThumbPan(document: self))
        addGestureRecognizer(MemoSelectionDismissTap(document: self))
    }

    required init?(coder: NSCoder) { fatalError("ストーリーボードからは生成しません") }

    // 文字選択の対象になるブロック（本文が空のメモを除く）
    private var copyableBlocks: [MemoBlock] {
        blocks.filter { !$0.text.isEmpty }
    }

    // ---------------------------------
    // Dart から届いた文書で、表示を更新する
    // ---------------------------------
    // 本文は変わったところから後ろだけを差し替え、OS の文字選択とスクロール位置を保つ
    func update(_ arguments: Any?) {
        guard let data = arguments as? [String: Any],
              let blockValues = data["blocks"] as? [[String: Any]] else { return }
        latestArguments = arguments
        let incoming = Self.parseBlocks(blockValues)

        // --- 差し替える前の文字選択とスクロール位置を覚えておく（選択範囲のメモが消えるなら、文字選択を解除する）
        let incomingIds = Set(incoming.map(\.id))
        let sameMemoIds = blocks.map(\.id) == incoming.map(\.id)
        let selectedBlocks = blocks.filter { NSIntersectionRange($0.range, selectedRange).length > 0 }
        if selectedBlocks.contains(where: { !incomingIds.contains($0.id) }) {
            clearTextSelection(refresh: false)
        }
        let selectionStartPosition = blockPosition(at: selectedRange.location)
        let selectionEndPosition = blockPosition(at: NSMaxRange(selectedRange))
        let hadSelection = selectedRange.length > 0
        let wasAtBottom = contentOffset.y >= contentSize.height - bounds.height - BodyLayout.atBottomTolerance
        let oldOffsetY = contentOffset.y

        // --- 文字の大きさ・色と、コピーの区切り
        copySeparator = data["copySeparator"] as? String ?? DefaultValue.copySeparator
        bodySize = CGFloat((data["fontSize"] as? NSNumber)?.doubleValue ?? DefaultValue.fontSize)
        bodyColor = Self.opaqueColor(argb: (data["textColor"] as? NSNumber)?.uint32Value ?? DefaultValue.textColor)

        // --- 文字選択中のメモは、選択を始めた時点の本文のまま出す（その間の追記は、選択を解除すると出る）
        blocks = incoming.map { block in
            guard let snapshot = snapshots[block.id] else { return block }
            var shownBlock = block
            shownBlock.text = snapshot
            return shownBlock
        }

        // --- 文書を差し替え、文字選択を置き直す（中身が同じなら何もしない）
        updating = true
        let document = buildDocument()
        if sameMemoIds && document.isEqual(to: textStorage) {
            updating = false
            return
        }
        replaceChangedTail(with: document)
        if hadSelection, let selectionStartPosition, let selectionEndPosition {
            restoreSelection(from: selectionStartPosition, to: selectionEndPosition)
        }
        updating = false

        // --- 組み直した後の高さで、スクロール位置を決める（最初と、一番下を見ていたときは最新へ。文字選択中は動かさない）
        needsDocumentLayout = true
        setNeedsLayout()
        layoutIfNeeded()
        if isFirstLayout || (wasAtBottom && !hadSelection && !isDragging) {
            contentOffset = CGPoint(x: 0, y: scrollableHeight)
        } else {
            contentOffset = CGPoint(x: 0, y: min(oldOffsetY, scrollableHeight))
        }
        rail.setNeedsDisplay()
    }

    // Dart から届いたブロックの一覧（形の合わないものは飛ばす）
    private static func parseBlocks(_ values: [[String: Any]]) -> [MemoBlock] {
        values.compactMap { value -> MemoBlock? in
            guard let id = value["id"] as? NSNumber, let text = value["text"] as? String else { return nil }
            return MemoBlock(id: id.int64Value, text: text, selected: value["selected"] as? Bool ?? false)
        }
    }

    // Dart から届いた ARGB の値を、不透明の色にする（アルファは使わない）
    private static func opaqueColor(argb: UInt32) -> UIColor {
        UIColor(red: CGFloat((argb >> 16) & 255) / 255,
                green: CGFloat((argb >> 8) & 255) / 255,
                blue: CGFloat(argb & 255) / 255, alpha: 1)
    }

    // 本文の書体（選択中のブロックは太字）
    private func bodyFont(selected: Bool) -> UIFont {
        UIFont(name: selected ? BodyLayout.boldFontName : BodyLayout.regularFontName, size: bodySize)
            ?? UIFont.systemFont(ofSize: bodySize, weight: selected ? .bold : .regular)
    }

    // 各ブロックの本文を改行1つでつないだ文書を作り、ブロックごとの文書の中の範囲も記録する
    private func buildDocument() -> NSMutableAttributedString {
        let document = NSMutableAttributedString(string: "")
        for index in blocks.indices {
            let block = blocks[index]
            let isLast = index + 1 == blocks.count
            let visibleText = block.text.isEmpty ? BodyLayout.emptyBlockText : block.text
            blocks[index].range = NSRange(location: document.length, length: (visibleText as NSString).length)
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = bodySize * BodyLayout.lineHeightRatio
            paragraph.maximumLineHeight = bodySize * BodyLayout.lineHeightRatio
            let segment = NSMutableAttributedString(
                string: visibleText + (isLast ? "" : "\n"),
                attributes: [.font: bodyFont(selected: block.selected), .foregroundColor: bodyColor, .paragraphStyle: paragraph])
            // ブロックの最後の段落の下に、ブロック間の余白を空ける
            let lastParagraph = (segment.string as NSString).paragraphRange(
                for: NSRange(location: max(0, (visibleText as NSString).length - 1), length: 0))
            let lastParagraphStyle = paragraph.mutableCopy() as! NSMutableParagraphStyle
            lastParagraphStyle.paragraphSpacing = isLast ? 0 : BodyLayout.blockSpacing
            segment.addAttribute(.paragraphStyle, value: lastParagraphStyle, range: lastParagraph)
            document.append(segment)
        }
        return document
    }

    // 前と同じ先頭部分は置き直さず、変わったところから後ろだけを差し替える（本文の追加だけなら OS の選択状態を保てる）
    private func replaceChangedTail(with document: NSAttributedString) {
        textStorage.beginEditing()
        let oldText = textStorage.string as NSString
        let newText = document.string as NSString
        if oldText != newText {
            var commonLength = 0
            while commonLength < min(oldText.length, newText.length),
                  oldText.character(at: commonLength) == newText.character(at: commonLength) {
                commonLength += 1
            }
            // 絵文字などの文字の途中で切らない
            if commonLength > 0, commonLength < oldText.length {
                commonLength = oldText.rangeOfComposedCharacterSequence(at: commonLength).location
            }
            textStorage.replaceCharacters(
                in: NSRange(location: commonLength, length: oldText.length - commonLength),
                with: document.attributedSubstring(from: NSRange(location: commonLength, length: document.length - commonLength)))
        }
        // 文字が同じところも、太字や行高などの属性は付け直す
        document.enumerateAttributes(in: NSRange(location: 0, length: document.length)) { attributes, range, _ in
            self.textStorage.setAttributes(attributes, range: range)
        }
        textStorage.endEditing()
    }

    // ---------------------------------
    // 文字選択
    // ---------------------------------
    // 文字選択を解除する（refresh なら、選択中に止めていた本文の更新も反映する）
    func clearTextSelection(refresh: Bool = true) {
        updating = true
        selectedRange = NSRange(location: 0, length: 0)
        resignFirstResponder()
        snapshots.removeAll()
        updating = false
        if refresh { update(latestArguments) }
    }

    // 文書の中の位置を、ブロックと、その中の何文字目かに直す
    private func blockPosition(at offset: Int) -> BlockPosition? {
        guard let block = blocks.first(where: { offset >= $0.range.location && offset <= NSMaxRange($0.range) }) else {
            return nil
        }
        return BlockPosition(blockId: block.id, offsetInBlock: offset - block.range.location)
    }

    // ブロックの中の位置を、今の文書の中の位置に直す（本文が縮んでいたら末尾に留める）
    private func documentOffset(of position: BlockPosition) -> Int? {
        guard let block = blocks.first(where: { $0.id == position.blockId }) else { return nil }
        return block.range.location + min(position.offsetInBlock, block.range.length)
    }

    // 差し替える前の選択範囲を、同じメモの同じ位置へ置き直す
    private func restoreSelection(from startPosition: BlockPosition, to endPosition: BlockPosition) {
        guard let start = documentOffset(of: startPosition), let end = documentOffset(of: endPosition), end > start else {
            return
        }
        let restored = NSRange(location: start, length: end - start)
        if selectedRange != restored { selectedRange = restored }
    }

    // OS が選択色を付けている面（ブロック間の余白も含む）に、点が入っているか
    fileprivate func selectionContains(_ point: CGPoint) -> Bool {
        guard point.x < bounds.width - RailLayout.touchWidth, let range = selectedTextRange, !range.isEmpty else {
            return false
        }
        return selectionRects(for: range).contains { $0.rect.contains(point) }
    }

    // OS の操作で文字選択が変わったとき
    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !updating else { return }
        let intersections = copyableBlocks
            .map { NSIntersectionRange($0.range, selectedRange) }
            .filter { $0.length > 0 }
        if let first = intersections.first, let last = intersections.last {
            // 選択範囲の両端を、掛かっているブロックの本文の端までに収める
            let fitted = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
            if fitted != selectedRange {
                updating = true
                selectedRange = fitted
                updating = false
            }
            // 選択を始めた時点の本文を保ち、選択している間は本文を差し替えない
            for block in blocks where snapshots[block.id] == nil {
                snapshots[block.id] = block.text
            }
        } else if !snapshots.isEmpty || selectedRange.length > 0 {
            collapseSelectionLater()
        }
    }

    // 選択が外れた（または本文に掛からない選択になった）ら、UIKit の選択通知を終えてから選択を畳み、止めていた本文の更新を反映する
    private func collapseSelectionLater() {
        let expected = selectedRange
        DispatchQueue.main.async { [weak self] in
            guard let self, self.selectedRange == expected else { return }
            self.updating = true
            if self.selectedRange.length > 0 {
                self.selectedRange = NSRange(location: self.selectedRange.location, length: 0)
            }
            self.snapshots.removeAll()
            self.updating = false
            self.update(self.latestArguments)
        }
    }

    // 文字選択の対象になるメモ全件の範囲（対象が無ければ nil）
    private var allCopyableRange: NSRange? {
        let copyable = copyableBlocks
        guard let first = copyable.first, let last = copyable.last else { return nil }
        return NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
    }

    // 選択範囲に掛かる各メモの部分を取り出し、区切りでつないでクリップボードへ入れる
    override func copy(_ sender: Any?) {
        let pieces = copyableBlocks.compactMap { block -> String? in
            let intersection = NSIntersectionRange(block.range, selectedRange)
            guard intersection.length > 0 else { return nil }
            return (block.text as NSString).substring(with: NSRange(
                location: intersection.location - block.range.location, length: intersection.length))
        }
        if !pieces.isEmpty { UIPasteboard.general.string = pieces.joined(separator: copySeparator) }
    }

    // 文字選択の対象になるメモ全件を選ぶ（選んだ後のメニューは OS の全選択に出させ、範囲は本文の端までに収める）
    override func selectAll(_ sender: Any?) {
        super.selectAll(sender)
        textViewDidChangeSelection(self)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copy(_:)) { return selectedRange.length > 0 }
        // すでに全件を選んでいるときは「すべてを選択」を出さない
        if action == #selector(selectAll(_:)) {
            guard let range = allCopyableRange else { return false }
            return selectedRange != range
        }
        return super.canPerformAction(action, withSender: sender)
    }

    // ---------------------------------
    // レイアウト
    // ---------------------------------
    override func layoutSubviews() {
        let oldSize = lastLayoutSize
        let wasAtBottom = contentOffset.y >= contentSize.height - oldSize.height - BodyLayout.atBottomTolerance
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        // 一番下までスクロールしたときだけ、最新の行をホームインジケーターの上へ離す（途中では下を通り抜けて流れる）
        let bottomInset = safeAreaInsets.bottom + BodyLayout.paddingBottom
        if abs(textContainerInset.bottom - bottomInset) > 0.5 {
            textContainerInset.bottom = bottomInset
            needsDocumentLayout = true
        }
        if needsDocumentLayout || oldSize != bounds.size {
            needsDocumentLayout = false
            layoutDocument()
        }
        // 最初と、一番下を見ている間に一覧の高さが変わったとき（選択バーの出入りなど）は、一番下へ（文字選択中は動かさない）
        if isFirstLayout || (oldSize != bounds.size && wasAtBottom && selectedRange.length == 0) {
            contentOffset = CGPoint(x: 0, y: scrollableHeight)
        }
        layoutRail()
        isFirstLayout = false
        lastLayoutSize = bounds.size
    }

    // メモが少ないうちは上の余白を広げて一覧を下に寄せ、丸の位置を求め直す
    private func layoutDocument() {
        layoutManager.ensureLayout(for: textContainer)
        let documentHeight = layoutManager.usedRect(for: textContainer).height
        let topInset = max(BodyLayout.minPaddingTop, bounds.height - documentHeight - textContainerInset.bottom)
        if abs(textContainerInset.top - topInset) > 0.5 { textContainerInset.top = topInset }
        layoutCircleCenters(top: topInset)
    }

    // 縦線の View は、スクロールしても表示範囲の右端に留め、一番手前に置く
    private func layoutRail() {
        rail.frame = CGRect(x: bounds.width - RailLayout.touchWidth, y: contentOffset.y,
                            width: RailLayout.touchWidth, height: bounds.height)
        bringSubviewToFront(rail)
        rail.setNeedsDisplay()
    }


    // ---------------------------------
    // 丸の位置（上のブロックの最後の行の文字の下端と、このブロックの1行目の文字の上端のちょうど間）
    // ---------------------------------
    private func layoutCircleCenters(top: CGFloat) {
        let glyphTops = blocks.map { glyphTopAndBottom(atCharacter: $0.range.location).top + top }
        var centers: [Int64: CGFloat] = [:]
        for index in blocks.indices.dropFirst() {
            let upperLastCharacter = NSMaxRange(blocks[index - 1].range) - 1
            let upperBottom = glyphTopAndBottom(atCharacter: upperLastCharacter).bottom + top
            centers[blocks[index].id] = (upperBottom + glyphTops[index]) / 2
        }
        // 一番上のブロックには上のブロックがないので、2番目のブロックと同じだけ文字の上端から離す
        if let first = blocks.first {
            let halfGap = blocks.count > 1
                ? glyphTops[1] - (centers[blocks[1].id] ?? glyphTops[1])
                : RailLayout.singleBlockCircleGap
            centers[first.id] = glyphTops[0] - halfGap
        }
        circleCenterYs = centers
    }

    // 文字の上端・下端（行高やブロック間隔の余白を含まない、フォントの ascender・descender の範囲）
    private func glyphTopAndBottom(atCharacter index: Int) -> (top: CGFloat, bottom: CGFloat) {
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = lineRect.minY + layoutManager.location(forGlyphAt: glyph).y
        let font = textStorage.attribute(.font, at: index, effectiveRange: nil) as? UIFont
            ?? UIFont.systemFont(ofSize: bodySize)
        return (baseline - font.ascender, baseline - font.descender)
    }

    private func circleCenterY(_ block: MemoBlock) -> CGFloat {
        circleCenterYs[block.id] ?? textContainerInset.top
    }

    // 高さ y（文書の座標）より上で、一番近い丸を持つブロック（どの丸よりも上なら nil）
    private func blockWithCircleAbove(_ y: CGFloat) -> MemoBlock? {
        blocks.last(where: { circleCenterY($0) <= y })
    }

    // ---------------------------------
    // 右の縦線と丸
    // ---------------------------------
    @objc private func didTapRail(_ recognizer: UITapGestureRecognizer) {
        let y = recognizer.location(in: rail).y + contentOffset.y
        guard let block = blockWithCircleAbove(y) else { return }
        onToggleBlock?(block.id)
    }

    // 選択中のブロックは太い線と大きな丸にする（縦線の View の上に、見えている区間だけを描く）
    fileprivate func drawRail() {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        defer { context.restoreGState() }
        // 文書の座標で描けるよう、表示範囲の上端の分だけずらす
        context.translateBy(x: 0, y: -contentOffset.y)
        bodyColor.setStroke()
        bodyColor.setFill()
        let x = RailLayout.touchWidth - RailLayout.xFromRight
        for index in blocks.indices {
            let block = blocks[index]
            let top = circleCenterY(block)
            let bottom = index + 1 < blocks.count ? circleCenterY(blocks[index + 1]) : contentSize.height
            guard bottom >= contentOffset.y, top <= contentOffset.y + bounds.height else { continue }
            context.setLineWidth(block.selected ? RailLayout.selectedLineWidth : RailLayout.lineWidth)
            context.move(to: CGPoint(x: x, y: top))
            context.addLine(to: CGPoint(x: x, y: bottom))
            context.strokePath()
            let radius = block.selected ? RailLayout.selectedCircleRadius : RailLayout.circleRadius
            context.fillEllipse(in: CGRect(x: x - radius, y: top - radius, width: radius * 2, height: radius * 2))
        }
    }

    // ---------------------------------
    // スクロールつまみ（縦線の上を、表示範囲の中だけ動く。y は表示範囲の上端から測る）
    // ---------------------------------
    private var scrollableHeight: CGFloat { max(0, contentSize.height - bounds.height) }

    // 下端がホームインジケーターに重なるときは、その上に広めの余白をとる（ホームへ戻る操作の受付領域では掴みにくいため）
    private var scrollThumbTrack: ClosedRange<CGFloat> {
        // 上端は、一番上までスクロールしたときの線の始まり（一番上のブロックの丸）にそろえる
        let top = blocks.first.map { circleCenterY($0) } ?? ScrollThumbLayout.trackMargin
        let bottomMargin = safeAreaInsets.bottom > 0
            ? ScrollThumbLayout.trackMarginAboveHomeIndicator
            : ScrollThumbLayout.trackMargin
        let bottom = bounds.height - safeAreaInsets.bottom - bottomMargin
        return top...max(top, bottom)
    }

    private var scrollThumbCenterY: CGFloat {
        let track = scrollThumbTrack
        let progress = scrollableHeight > 0 ? min(max(contentOffset.y / scrollableHeight, 0), 1) : 0
        return track.lowerBound + (track.upperBound - track.lowerBound) * progress
    }

    // スクロールできないほど短いときは、つまみを出さない
    private var showsScrollThumb: Bool { scrollableHeight > 0.5 }

    fileprivate func scrollThumbContains(_ point: CGPoint) -> Bool {
        let y = point.y - contentOffset.y
        return showsScrollThumb && point.x >= bounds.width - RailLayout.touchWidth
            && abs(y - scrollThumbCenterY) <= ScrollThumbLayout.touchHeight / 2
    }

    // 縦線の View の上に描く
    fileprivate func drawScrollThumb() {
        guard showsScrollThumb else { return }
        let centerX = RailLayout.touchWidth - RailLayout.xFromRight
        let rect = CGRect(x: centerX - ScrollThumbLayout.width / 2,
                          y: scrollThumbCenterY - ScrollThumbLayout.thickness / 2,
                          width: ScrollThumbLayout.width, height: ScrollThumbLayout.thickness)
        bodyColor.setFill()
        UIRectFill(rect)
    }

    @objc fileprivate func draggedScrollThumb(_ recognizer: MemoScrollThumbPan) {
        let y = recognizer.location(in: self).y - contentOffset.y
        switch recognizer.state {
        case .began:
            // 慣性スクロールを止め、指を置いた位置とつまみの中心のずれを保ったまま動かす
            setContentOffset(contentOffset, animated: false)
            scrollThumbGrabOffset = recognizer.touchDownY - scrollThumbCenterY
        case .changed:
            let track = scrollThumbTrack
            let trackLength = track.upperBound - track.lowerBound
            guard trackLength > 0 else { return }
            let progress = (y - scrollThumbGrabOffset - track.lowerBound) / trackLength
            contentOffset = CGPoint(x: 0, y: min(max(progress, 0), 1) * scrollableHeight)
        default:
            break
        }
    }
}

// ---------------------------------
// 右の縦線・丸とスクロールつまみを描き、タップとドラッグを受け取る View
// ---------------------------------
private final class MemoRailView: UIView {
    weak var document: MemoDocumentView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        accessibilityLabel = "メモのブロック選択"
    }

    required init?(coder: NSCoder) { fatalError("ストーリーボードからは生成しません") }

    override func draw(_ rect: CGRect) {
        document?.drawRail()
        document?.drawScrollThumb()
    }
}

// ---------------------------------
// つまみの上で指が動いたときだけ、一覧のスクロールより先にドラッグとして受け取る
// ---------------------------------
// 動かさずに離したときは失敗するので、下の丸・線のタップ（ブロック選択）に届く
private final class MemoScrollThumbPan: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    private weak var document: MemoDocumentView?
    // 指を置いた位置（表示範囲の上端から測る）。パンが始まるまでに動いた分も、つまみに反映するために使う
    private(set) var touchDownY: CGFloat = 0

    init(document: MemoDocumentView) {
        self.document = document
        super.init(target: document, action: #selector(MemoDocumentView.draggedScrollThumb(_:)))
        delegate = self
        maximumNumberOfTouches = 1
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let document else { return false }
        let point = touch.location(in: document)
        touchDownY = point.y - document.contentOffset.y
        return document.scrollThumbContains(point)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other === document?.panGestureRecognizer
    }
}

// ---------------------------------
// 選択中の面への1回タップだけを、選択解除として扱う
// ---------------------------------
private final class MemoSelectionDismissTap: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    private weak var document: MemoDocumentView?
    // 指を置いたときの選択範囲（それから選択が変わっていなければ解除する）
    private var selectionAtTouchDown = NSRange(location: 0, length: 0)

    init(document: MemoDocumentView) {
        self.document = document
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(dismissSelection))
        delegate = self
        cancelsTouchesInView = false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let document, document.selectionContains(touch.location(in: document)) else { return false }
        selectionAtTouchDown = document.selectedRange
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    // OS の長押し・ダブルタップ・ドラッグの認識を優先する
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        if let tap = other as? UITapGestureRecognizer { return tap.numberOfTapsRequired > 1 }
        return other is UILongPressGestureRecognizer || other is UIPanGestureRecognizer
    }

    // OS の1回タップ（メニューが隠れていれば出す）は、解除のタップと確定したら動かさない（出かけたメニューが解除で消えてちらつくため）
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        guard let tap = other as? UITapGestureRecognizer, tap !== self, tap.view === document else { return false }
        return tap.numberOfTapsRequired == 1
    }

    @objc private func dismissSelection() {
        let selected = selectionAtTouchDown
        // UIKit のタップ処理を終えてから、メニューと選択をまとめて閉じる
        DispatchQueue.main.async { [weak document] in
            guard let document, document.selectedRange == selected else { return }
            document.clearTextSelection()
        }
    }
}
