import Flutter
import UIKit

// ============================================================
// NativeMemoList — リスニング画面のメモ一覧（iOS）
//
//   メモ全件を時系列順に並べた1つの UITextView にし、表示とスクロールは OS に任せる。
//   右の縦線と丸はアプリ側で描く。
//   Dart 側は lib/widgets/native_memo_list.dart。
// ============================================================

// ---------------------------------
// 定数: Dart 側とのやり取り
// ---------------------------------
private enum ChannelMethod {
    // Dart から呼ばれるメソッド
    static let update = "update"
}

// Dart から値が届かなかったときの既定値
private enum DefaultValue {
    static let fontSize: Double = 18
    static let textColor: UInt32 = 0xff111827
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
    // 書体
    static let regularFontName = "HiraginoSans-W3"
}

// ---------------------------------
// 定数: 右の縦線と丸（pt）
// ---------------------------------
private enum RailLayout {
    // 縦線と丸を置く領域の幅（一覧の右端から）
    static let touchWidth: CGFloat = 40
    // 縦線の位置（一覧の右端から）
    static let xFromRight: CGFloat = 18
    // 縦線の太さと丸の半径
    static let lineWidth: CGFloat = 1.5
    static let circleRadius: CGFloat = 4
    // ブロックが1つだけのときに、丸を1行目の文字の上端から離す距離
    static let singleBlockCircleGap: CGFloat = 12
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
    // 表示する本文
    let text: String
    // 文書の中での本文の範囲
    var range = NSRange(location: 0, length: 0)
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
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(nil); return }
            switch call.method {
            case ChannelMethod.update:
                self.documentView.update(call.arguments)
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
// 本文（メモ全件を1つにした文書）と、右の縦線・丸
// ---------------------------------
private final class MemoDocumentView: UITextView {
    // 表示中のブロック（古い順）
    private var blocks: [MemoBlock] = []
    // 本文の文字サイズと色
    private var bodySize = CGFloat(DefaultValue.fontSize)
    private var bodyColor = UIColor.label
    // まだ一度もレイアウトしていないか（最初の表示では、一番下（最新）までスクロールする）
    private var isFirstLayout = true
    // 前回のレイアウトでの大きさ
    private var lastLayoutSize = CGSize.zero
    // 文書の高さと丸の位置を測り直すか
    private var needsDocumentLayout = true

    // --- 右の縦線と丸
    private let rail = MemoRailView()
    // 丸の中心の高さ（メモ id → 文書の座標）
    private var circleCenterYs: [Int64: CGFloat] = [:]

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        // TextKit 1（NSLayoutManager）で組み、文書全体の高さを同じレイアウトから求める
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        super.init(frame: frame, textContainer: container)
        isEditable = false
        isSelectable = false
        backgroundColor = .clear
        contentInsetAdjustmentBehavior = .never
        self.textContainer.lineFragmentPadding = 0
        textContainerInset = UIEdgeInsets(top: BodyLayout.minPaddingTop, left: BodyLayout.paddingLeft,
                                          bottom: BodyLayout.paddingBottom, right: BodyLayout.paddingRight)
        alwaysBounceVertical = true
        rail.document = self
        addSubview(rail)
    }

    required init?(coder: NSCoder) { fatalError("ストーリーボードからは生成しません") }

    // ---------------------------------
    // Dart から届いた文書で、表示を更新する
    // ---------------------------------
    func update(_ arguments: Any?) {
        guard let data = arguments as? [String: Any],
              let blockValues = data["blocks"] as? [[String: Any]] else { return }

        // --- 差し替える前のスクロール位置を覚えておく
        let wasAtBottom = contentOffset.y >= contentSize.height - bounds.height - BodyLayout.atBottomTolerance
        let oldOffsetY = contentOffset.y

        // --- 文字の大きさ・色と、ブロック
        bodySize = CGFloat((data["fontSize"] as? NSNumber)?.doubleValue ?? DefaultValue.fontSize)
        bodyColor = Self.opaqueColor(argb: (data["textColor"] as? NSNumber)?.uint32Value ?? DefaultValue.textColor)
        blocks = Self.parseBlocks(blockValues)

        // --- 文書を差し替える（中身が同じなら何もしない）
        let document = buildDocument()
        if document.isEqual(to: textStorage) { return }
        textStorage.setAttributedString(document)

        // --- 組み直した後の高さで、スクロール位置を決める（最初と、一番下を見ていたときは最新へ）
        needsDocumentLayout = true
        setNeedsLayout()
        layoutIfNeeded()
        if isFirstLayout || (wasAtBottom && !isDragging) {
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
            return MemoBlock(id: id.int64Value, text: text)
        }
    }

    // Dart から届いた ARGB の値を、不透明の色にする（アルファは使わない）
    private static func opaqueColor(argb: UInt32) -> UIColor {
        UIColor(red: CGFloat((argb >> 16) & 255) / 255,
                green: CGFloat((argb >> 8) & 255) / 255,
                blue: CGFloat(argb & 255) / 255, alpha: 1)
    }

    // 本文の書体
    private func bodyFont() -> UIFont {
        UIFont(name: BodyLayout.regularFontName, size: bodySize) ?? UIFont.systemFont(ofSize: bodySize)
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
                attributes: [.font: bodyFont(), .foregroundColor: bodyColor, .paragraphStyle: paragraph])
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
        // 最初と、一番下を見ている間に一覧の高さが変わったとき（選択バーの出入りなど）は、一番下へ
        if isFirstLayout || (oldSize != bounds.size && wasAtBottom) {
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

    // 一番下までスクロールしたときの位置
    private var scrollableHeight: CGFloat { max(0, contentSize.height - bounds.height) }

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

    // ---------------------------------
    // 右の縦線と丸（縦線の View の上に、見えている区間だけを描く）
    // ---------------------------------
    fileprivate func drawRail() {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        defer { context.restoreGState() }
        // 文書の座標で描けるよう、表示範囲の上端の分だけずらす
        context.translateBy(x: 0, y: -contentOffset.y)
        bodyColor.setStroke()
        bodyColor.setFill()
        context.setLineWidth(RailLayout.lineWidth)
        let x = RailLayout.touchWidth - RailLayout.xFromRight
        let radius = RailLayout.circleRadius
        for index in blocks.indices {
            let block = blocks[index]
            let top = circleCenterY(block)
            let bottom = index + 1 < blocks.count ? circleCenterY(blocks[index + 1]) : contentSize.height
            guard bottom >= contentOffset.y, top <= contentOffset.y + bounds.height else { continue }
            context.move(to: CGPoint(x: x, y: top))
            context.addLine(to: CGPoint(x: x, y: bottom))
            context.strokePath()
            context.fillEllipse(in: CGRect(x: x - radius, y: top - radius, width: radius * 2, height: radius * 2))
        }
    }
}

// ---------------------------------
// 右の縦線と丸を描く View
// ---------------------------------
private final class MemoRailView: UIView {
    weak var document: MemoDocumentView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("ストーリーボードからは生成しません") }

    override func draw(_ rect: CGRect) {
        document?.drawRail()
    }
}
