import Flutter
import UIKit

// ============================================================
// NativeMemoList — リスニング画面のメモ一覧（iOS）
//
//   メモ全件を時系列順に並べた1つの UITextView にし、文字選択・つまみ・メニュー・スクロール・編集は OS に任せる。
//   1つのメモが1つの段落で、改行が段落の区切り。本文をタップすると、メモ帳のように書き直せる。
//   右の縦線と日付の区切りの横線、スクロールつまみ、発話中の「.」はアプリ側で描く。
//   Dart 側は lib/widgets/native_memo_list.dart。
// ============================================================

// ---------------------------------
// 定数: Dart 側とのやり取り
// ---------------------------------
private enum ChannelMethod {
    // Dart から呼ばれるメソッド
    static let update = "update"
    // Dart へ知らせるメソッド
    static let editingStarted = "editingStarted"
    static let editingEnded = "editingEnded"
}

// Dart から値が届かなかったときの既定値
private enum DefaultValue {
    static let fontSize: Double = 18
    static let textColor: UInt32 = 0xff111827
    static let railColor: UInt32 = 0xffcfd1d4
    static let copySeparator = "\n\n"
}

// 文字ごとに付ける印: その文字が元々どのメモの文字だったか（NSNumber）
private extension NSAttributedString.Key {
    static let memoId = NSAttributedString.Key("jp.momeo.memoId")
}

// 段落の区切りの改行（NSString の1文字）
private let newlineCharacter = unichar(10)

// ---------------------------------
// 定数: 本文（pt。Android 側の dp とそろえる）
// ---------------------------------
private enum BodyLayout {
    // 本文の左右の余白（右も左と同じ。縦線は本文の後ろを通す）
    static let paddingLeft: CGFloat = 8
    static let paddingRight: CGFloat = 8
    // 本文の上の余白の下限（ステータスバーに重なる分は、これに足す。メモが少ないうちは、残りを上に空けて一覧を下に寄せる）
    static let minPaddingTop: CGFloat = 24
    // 本文の下の余白（ホームインジケーターに重なる分は、これに足す）
    static let paddingBottom: CGFloat = 24
    // 本文1行の高さ（文字サイズに対する倍率）。ヒラギノの leading が上乗せされ、見た目は約2倍になる
    static let lineHeightRatio: CGFloat = 1.5
    // 本文がまだ無いときに見込む1行の高さ（文字サイズに対する倍率。本文の行の見た目とそろえる）
    static let emptyLineHeightRatio: CGFloat = 2
    // ブロックとブロックの間の余白
    static let blockSpacing: CGFloat = 24
    // 空のメモにも区切りと1行分の高さを持たせるために置く、幅の無い文字
    static let emptyBlockText = "\u{200B}"
    // 一番下からこの距離までにいれば、一番下を見ているとみなす
    static let atBottomTolerance: CGFloat = 32
    // 書体
    static let fontName = "HiraginoSans-W3"
    // カーソルの高さ（文字の上端から下端までの高さに対する倍率。上下に同じだけ伸ばす）
    static let caretHeightRatio: CGFloat = 1.4
}

// ---------------------------------
// 定数: 右の縦線と、日付の区切りの横線（pt）
// ---------------------------------
private enum RailLayout {
    // 縦線の位置（一覧の右端から）
    static let xFromRight: CGFloat = 18
    // 縦線と横線の太さ
    static let lineWidth: CGFloat = 0.5
    // ブロックが1つだけのときに、区切りを1行目の文字の上端から離す距離
    static let singleBlockBoundaryGap: CGFloat = 12
}

// ---------------------------------
// 定数: スクロールつまみ（pt）
// ---------------------------------
private enum ScrollThumbLayout {
    // 横棒の幅と太さ
    static let width: CGFloat = 24
    static let thickness: CGFloat = 0.5
    // つまみを掴める幅（一覧の右端から）と高さ。細い横棒でも掴めるよう、当たり判定は見た目より上下に広げる
    static let touchWidth: CGFloat = 40
    static let touchHeight: CGFloat = 44
    // 文字選択の両端の、OS のつまみを掴めるとみなす広さ（ここではスクロールつまみより OS のつまみを優先する）
    static let selectionEdgeTouchMargin: CGFloat = 22
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

// Dart から届いたメモ1件
private struct IncomingMemo {
    let id: Int64
    let text: String
    // 書き直せるか（打ち出し中は書き直せない）
    let selectable: Bool
    // その日の最初のメモか（日付の区切りの横線は、その日の最初のメモの上にだけ引く）
    let startsDay: Bool
}

// 文書の中の1段落（編集の間は、分けたりつなげたりした後の段落）
private struct MemoBlock {
    // 段落の文字が元々どのメモの文字だったか（出てくる順。手で書き足しただけの文字には無い）
    let sourceIds: [Int64]
    // 表示している本文
    let text: String
    // その日の最初の段落か
    let startsDay: Bool
    // 文書の中での本文の範囲（区切りの改行を含まない）
    let range: NSRange
}

// 1回の編集（書き始めてから、保存した文書が Dart から届くまで）
private struct EditSession {
    // 書き始めた時点で書き直せたメモ（打ち出し中のメモを除く）。これ以外のメモは、文書の末尾に Dart の本文のまま出す
    let editableIds: Set<Int64>
    // 保存を頼んだあと、届くのを待っている文書の editRevision（書いている間は nil）
    var awaitedRevision: Int?

    // 書き終えて、保存した文書が届くのを待っているか
    var isWaitingForSave: Bool { awaitedRevision != nil }
}

// 発話中の気配として「.」を出す場所
private enum SpeakingDotsPlace: String {
    // 最新のブロックの本文の続き
    case append
    // 次のブロックの1行目
    case newBlock
}

// ---------------------------------
// メモ一覧の View と、Dart とのやり取り
// ---------------------------------
private final class NativeMemoList: NSObject, FlutterPlatformView {
    private let container = UIView()
    private let documentView = MemoDocumentView(frame: .zero, textContainer: nil)
    // 書いている間だけ、一覧の右下（キーボードのすぐ上）に重ねて出す、キーボードをしまうボタン
    private let keyboardDismissButton = MemoKeyboardDismissButton()
    private let channel: FlutterMethodChannel

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, arguments: Any?) {
        channel = FlutterMethodChannel(name: "\(NativeMemoListFactory.viewType)/\(viewId)", binaryMessenger: messenger)
        super.init()
        container.frame = frame
        documentView.frame = container.bounds
        documentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(documentView)
        addKeyboardDismissButton()
        documentView.onEditingStarted = { [weak self] in
            self?.keyboardDismissButton.isHidden = false
            self?.channel.invokeMethod(ChannelMethod.editingStarted, arguments: nil)
        }
        documentView.onEditingEnded = { [weak self] document in
            self?.keyboardDismissButton.isHidden = true
            self?.channel.invokeMethod(ChannelMethod.editingEnded, arguments: document)
        }
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

    // 一覧はキーボードの裏まで広がったままなので、ボタンはキーボードの上端に合わせ、キーボードと一緒に動かす
    //   ボタンの外は一覧そのものなので、本文はボタンの横にも出て、これまでどおり触れる
    private func addKeyboardDismissButton() {
        keyboardDismissButton.isHidden = true
        keyboardDismissButton.addTarget(documentView, action: #selector(MemoDocumentView.finishEditing), for: .touchUpInside)
        keyboardDismissButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(keyboardDismissButton)
        NSLayoutConstraint.activate([
            keyboardDismissButton.widthAnchor.constraint(equalToConstant: KeyboardDismissLayout.diameter),
            keyboardDismissButton.heightAnchor.constraint(equalToConstant: KeyboardDismissLayout.diameter),
            keyboardDismissButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -KeyboardDismissLayout.margin),
            keyboardDismissButton.bottomAnchor.constraint(equalTo: container.keyboardLayoutGuide.topAnchor, constant: -KeyboardDismissLayout.margin),
        ])
    }
}

// ---------------------------------
// 本文（メモ全件を1つにした文書）と、右の縦線・日付の区切りの横線、スクロールつまみ、発話中の「.」
// ---------------------------------
private final class MemoDocumentView: UITextView, UITextViewDelegate {
    // 書き始めたことを知らせる
    var onEditingStarted: (() -> Void)?
    // 書き終えた文書を知らせる（editedIds と、段落ごとの text・sourceIds）
    var onEditingEnded: (([String: Any]) -> Void)?

    // --- 文書
    // 表示中の段落（上から順）
    private var blocks: [MemoBlock] = []
    // 最後に Dart から届いたメモ（古い順）
    private var incomingMemos: [IncomingMemo] = []
    // 最後に Dart から届いた文書の editRevision（編集を保存し終えるたびに Dart 側で増える）
    private var editRevision = 0
    // 本文の文字サイズと色
    private var bodySize = CGFloat(DefaultValue.fontSize)
    private var bodyColor = UIColor.label
    // 縦線と横線の色（背景の波線と同じ色）
    private var railColor = UIColor.label
    // まだ一度もレイアウトしていないか（最初の表示では、一番下（最新）までスクロールする）
    private var isFirstLayout = true
    // 前回のレイアウトでの大きさ
    private var lastLayoutSize = CGSize.zero
    // 文書の高さとブロックの区切りの位置を測り直すか
    private var needsDocumentLayout = true

    // --- 編集
    // 編集の途中か（書き始めてから、保存した文書が届くまで）
    private var editSession: EditSession?
    // 日本語入力の変換中に届いて、出し直しを後回しにした末尾の段落があるか
    private var pendingLiveTail = false
    // 文書を組み直している間は、選択の変化を OS の操作として扱わない
    private var updating = false
    // 段落をまたいでコピーしたときの区切り
    private var copySeparator = DefaultValue.copySeparator

    // --- 縦線・横線と、スクロールつまみ
    private let rail = MemoRailView()
    // 段落の区切りの高さ（blocks と同じ順。文書の座標）
    private var boundaryYs: [CGFloat] = []
    // ドラッグ中の、指の位置とつまみの中心のずれ
    private var scrollThumbGrabOffset: CGFloat = 0

    // --- 発話中の「.」
    private let speakingDotsView = MemoSpeakingDotsView()
    // 出す場所（出さないときは nil）
    private var speakingDotsPlace: SpeakingDotsPlace?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        // TextKit 1（NSLayoutManager）で組み、文書全体の高さとブロックの区切りの位置を同じレイアウトから求める
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        super.init(frame: frame, textContainer: container)
        isEditable = true
        isSelectable = true
        // 話した言葉には辞書に無い言葉が多く、赤い下線だらけになるので、スペルチェックはしない
        spellCheckingType = .no
        // 一覧を下へ引くと、キーボードも一緒に下ろせる（下ろしたら編集を終える）
        keyboardDismissMode = .interactive
        backgroundColor = .clear
        contentInsetAdjustmentBehavior = .never
        self.textContainer.lineFragmentPadding = 0
        textContainerInset = UIEdgeInsets(top: BodyLayout.minPaddingTop, left: BodyLayout.paddingLeft,
                                          bottom: BodyLayout.paddingBottom, right: BodyLayout.paddingRight)
        alwaysBounceVertical = true
        // 標準のスクロールバーの代わりに、縦線の上のつまみを出す
        showsVerticalScrollIndicator = false
        delegate = self
        addSubview(speakingDotsView)
        rail.document = self
        // 縦線・横線とつまみは本文の後ろに描く
        insertSubview(rail, at: 0)
        addGestureRecognizer(MemoScrollThumbPan(document: self))
        addGestureRecognizer(MemoOutsideSelectionTap(document: self))
        // 背面に回ったら編集を終え、書いた分を保存する
        NotificationCenter.default.addObserver(self, selector: #selector(finishEditing),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("ストーリーボードからは生成しません") }

    // ---------------------------------
    // Dart から届いた文書で、表示を更新する
    // ---------------------------------
    func update(_ arguments: Any?) {
        guard let data = arguments as? [String: Any],
              let blockValues = data["blocks"] as? [[String: Any]] else { return }
        incomingMemos = Self.parseMemos(blockValues)
        editRevision = (data["editRevision"] as? NSNumber)?.intValue ?? 0

        // --- 発話中の「.」と、文字の大きさ・色、コピーの区切り
        let requestedDotsPlace = (data["speakingDots"] as? String).flatMap(SpeakingDotsPlace.init(rawValue:))
        let speakingDotsChanged = requestedDotsPlace != speakingDotsPlace
        speakingDotsPlace = requestedDotsPlace
        if requestedDotsPlace == nil { speakingDotsView.stop() } else { speakingDotsView.start() }
        copySeparator = data["copySeparator"] as? String ?? DefaultValue.copySeparator
        bodySize = CGFloat((data["fontSize"] as? NSNumber)?.doubleValue ?? DefaultValue.fontSize)
        bodyColor = Self.opaqueColor(argb: (data["textColor"] as? NSNumber)?.uint32Value ?? DefaultValue.textColor)
        railColor = Self.opaqueColor(argb: (data["railColor"] as? NSNumber)?.uint32Value ?? DefaultValue.railColor)

        // --- 保存を頼んだ文書が届いたら、編集を終える
        if let awaited = editSession?.awaitedRevision, editRevision >= awaited {
            editSession = nil
        }

        // --- 編集の途中は、書き直している段落を置き換えず、末尾の書き直せない段落だけを出し直す
        if editSession != nil {
            applyLiveTail()
            return
        }
        applyWholeDocument(speakingDotsChanged: speakingDotsChanged)
    }

    // Dart から届いたメモの一覧（形の合わないものは飛ばす）
    private static func parseMemos(_ values: [[String: Any]]) -> [IncomingMemo] {
        values.compactMap { value -> IncomingMemo? in
            guard let id = value["id"] as? NSNumber, let text = value["text"] as? String else { return nil }
            return IncomingMemo(id: id.int64Value, text: text,
                                selectable: value["selectable"] as? Bool ?? true,
                                startsDay: value["startsDay"] as? Bool ?? true)
        }
    }

    // Dart から届いた ARGB の値を、不透明の色にする（アルファは使わない）
    private static func opaqueColor(argb: UInt32) -> UIColor {
        UIColor(red: CGFloat((argb >> 16) & 255) / 255,
                green: CGFloat((argb >> 8) & 255) / 255,
                blue: CGFloat(argb & 255) / 255, alpha: 1)
    }

    // ---------------------------------
    // 文書の組み立て
    // ---------------------------------
    // 本文の書体
    private var bodyFont: UIFont {
        UIFont(name: BodyLayout.fontName, size: bodySize) ?? UIFont.systemFont(ofSize: bodySize)
    }

    // 段落の行高と、段落の下の余白（最後の段落の下には空けない）
    private func paragraphStyle(isLastParagraph: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = bodySize * BodyLayout.lineHeightRatio
        style.maximumLineHeight = bodySize * BodyLayout.lineHeightRatio
        style.paragraphSpacing = isLastParagraph ? 0 : BodyLayout.blockSpacing
        return style
    }

    // 本文の文字に付ける属性（memoId は、その文字が元々どのメモの文字だったか）
    private func bodyAttributes(memoId: Int64?, isLastParagraph: Bool) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: bodyColor,
            .paragraphStyle: paragraphStyle(isLastParagraph: isLastParagraph),
        ]
        if let memoId { attributes[.memoId] = NSNumber(value: memoId) }
        return attributes
    }

    // メモを改行1つでつないだ文書
    //   区切りの改行は上の段落の終わりなので上の段落の行高・余白にし、印は下の段落のメモにする（編集の間、末尾の書き直せない段落との区切りを消させないため）
    //   leadingSeparator なら、前に別の段落が続く前提で、先頭にも区切りの改行を置く
    private func buildDocument(from memos: [IncomingMemo], leadingSeparator: Bool = false) -> NSMutableAttributedString {
        let document = NSMutableAttributedString(string: "")
        for (index, memo) in memos.enumerated() {
            let isLast = index + 1 == memos.count
            if index > 0 || leadingSeparator {
                document.append(NSAttributedString(string: "\n", attributes: bodyAttributes(memoId: memo.id, isLastParagraph: false)))
            }
            // 空のメモにも1行分の高さを持たせる
            let visibleText = memo.text.isEmpty ? BodyLayout.emptyBlockText : memo.text
            document.append(NSAttributedString(string: visibleText, attributes: bodyAttributes(memoId: memo.id, isLastParagraph: isLast)))
        }
        return document
    }

    // Dart から届いたメモで、文書全体を組み直す（本文は変わったところから後ろだけを差し替え、スクロール位置を保つ）
    private func applyWholeDocument(speakingDotsChanged: Bool) {
        let wasAtBottom = contentOffset.y >= scrollableHeight - BodyLayout.atBottomTolerance
        let oldOffsetY = contentOffset.y
        let document = buildDocument(from: incomingMemos)
        // 本文が同じでも、「.」の出し方が変わったときは、次のブロックの分の高さを空け直すためにレイアウトし直す
        if document.isEqual(to: textStorage) && !speakingDotsChanged { return }
        updating = true
        replaceChangedTail(with: document)
        updating = false
        rebuildBlocksFromText()

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

    // 前と同じ先頭部分は置き直さず、変わったところから後ろだけを差し替える
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
        // 文字が同じところも、行高やメモの印などの属性は付け直す
        document.enumerateAttributes(in: NSRange(location: 0, length: document.length)) { attributes, range, _ in
            self.textStorage.setAttributes(attributes, range: range)
        }
        textStorage.endEditing()
    }

    // 今の文書を段落に分け、段落ごとの範囲と、元のメモを求め直す
    private func rebuildBlocksFromText() {
        let text = textStorage.string as NSString
        guard text.length > 0 else {
            blocks = []
            return
        }
        let startsDayById = Dictionary(incomingMemos.map { ($0.id, $0.startsDay) }, uniquingKeysWith: { first, _ in first })
        var seenFirstIds = Set<Int64>()
        var rebuilt: [MemoBlock] = []
        var location = 0
        for part in text.components(separatedBy: "\n") {
            let length = (part as NSString).length
            let range = NSRange(location: location, length: length)
            var sourceIds: [Int64] = []
            if length > 0 {
                textStorage.enumerateAttribute(.memoId, in: range) { value, _, _ in
                    guard let id = (value as? NSNumber)?.int64Value, !sourceIds.contains(id) else { return }
                    sourceIds.append(id)
                }
            }
            // 段落を分けたときは、同じメモから来た段落のうち、最初の段落にだけ日付の区切りを引く
            var startsDay = false
            if let firstId = sourceIds.first, !seenFirstIds.contains(firstId) {
                seenFirstIds.insert(firstId)
                startsDay = startsDayById[firstId] ?? false
            }
            rebuilt.append(MemoBlock(sourceIds: sourceIds, text: part, startsDay: startsDay, range: range))
            location += length + 1
        }
        blocks = rebuilt
    }

    // ---------------------------------
    // 編集: 始まりと終わり
    // ---------------------------------
    // キーボードをしまうボタンと、背面に回ったときに、編集を終える
    @objc func finishEditing() {
        if isFirstResponder { _ = resignFirstResponder() }
    }

    // 保存を待っている間は、書き始めない
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        editSession == nil
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        let editableIds = Set(incomingMemos.filter(\.selectable).map(\.id))
        editSession = EditSession(editableIds: editableIds, awaitedRevision: nil)
        adjustTypingAttributes()
        onEditingStarted?()
    }

    // 書き終えたら、書き直せた範囲の段落を Dart へ渡して保存を頼む（保存した文書が届くまでは、書いた本文を出し続ける）
    func textViewDidEndEditing(_ textView: UITextView) {
        guard var session = editSession, !session.isWaitingForSave else { return }
        if pendingLiveTail { applyLiveTail() }
        rebuildBlocksFromText()
        session.awaitedRevision = editRevision + 1
        editSession = session
        onEditingEnded?(editedDocument(editableIds: session.editableIds))
    }

    // Dart へ渡す、書き終えた文書（editedIds と、書き直せた範囲の段落ごとの text・sourceIds）
    private func editedDocument(editableIds: Set<Int64>) -> [String: Any] {
        let end = editableEnd()
        let paragraphs: [[String: Any]] = blocks
            .filter { NSMaxRange($0.range) <= end }
            .map { block in
                ["text": block.text.replacingOccurrences(of: BodyLayout.emptyBlockText, with: ""),
                 "sourceIds": block.sourceIds.map { NSNumber(value: $0) }]
            }
        return ["editedIds": editableIds.map { NSNumber(value: $0) }, "paragraphs": paragraphs]
    }

    // ---------------------------------
    // 編集: 書き直せる範囲と、末尾の書き直せない段落
    // ---------------------------------
    // 書き直せる範囲の終わり（その後ろは、打ち出し中のメモと、編集の間に増えたメモ。区切りの改行もそちらに含める）
    private func editableEnd() -> Int {
        guard let session = editSession else { return textStorage.length }
        var end = textStorage.length
        while end > 0 {
            var runRange = NSRange(location: 0, length: 0)
            let value = textStorage.attribute(.memoId, at: end - 1, longestEffectiveRange: &runRange,
                                              in: NSRange(location: 0, length: end))
            guard let id = (value as? NSNumber)?.int64Value, !session.editableIds.contains(id) else { break }
            end = runRange.location
        }
        return end
    }

    // 書き直せるのは、末尾の書き直せない段落より前だけ（その段落との区切りの改行も消せない）
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard let session = editSession, !session.isWaitingForSave else { return false }
        let end = editableEnd()
        // 書き直せる段落が無いときに打つと、書き直せない段落の頭につながってしまうので打たせない
        if end == 0 && textStorage.length > 0 { return false }
        return NSMaxRange(range) <= end
    }

    // 編集の途中に Dart から届いたメモのうち、書き直せないもの（打ち出し中・編集の間に増えたもの）を、文書の末尾に出し直す
    private func applyLiveTail() {
        guard let session = editSession else { return }
        // 日本語入力の変換中に文書を差し替えると変換が崩れるので、変換を終えてから出し直す
        if markedTextRange != nil {
            pendingLiveTail = true
            return
        }
        pendingLiveTail = false
        let liveMemos = incomingMemos.filter { !session.editableIds.contains($0.id) }
        let end = editableEnd()
        let tailRange = NSRange(location: end, length: textStorage.length - end)
        let tail = buildDocument(from: liveMemos, leadingSeparator: end > 0)
        if !tail.isEqual(to: textStorage.attributedSubstring(from: tailRange)) {
            let oldOffset = contentOffset
            updating = true
            textStorage.replaceCharacters(in: tailRange, with: tail)
            updating = false
            contentOffset = oldOffset
        }
        fixLastParagraphSpacing()
        refreshAfterTextChange()
    }

    // ---------------------------------
    // 編集: 打った文字の行高と印
    // ---------------------------------
    func textViewDidChange(_ textView: UITextView) {
        if markedTextRange == nil {
            fixLastParagraphSpacing()
            if pendingLiveTail { applyLiveTail() }
        }
        refreshAfterTextChange()
    }

    // 本文が変わったあと、段落を求め直し、区切りの位置と縦線・横線を描き直す
    private func refreshAfterTextChange() {
        rebuildBlocksFromText()
        needsDocumentLayout = true
        setNeedsLayout()
        rail.setNeedsDisplay()
    }

    // 段落の下の余白を、最後の段落は 0、その上の段落は空けるように直す（ほかの段落は、いつも空けている）
    private func fixLastParagraphSpacing() {
        let text = textStorage.string as NSString
        guard text.length > 0 else { return }
        let lastCharacterParagraph = text.paragraphRange(for: NSRange(location: text.length - 1, length: 0))
        if text.character(at: text.length - 1) == newlineCharacter {
            // 最後が空の段落なので、改行で終わる段落はその上の段落
            setParagraphSpacing(BodyLayout.blockSpacing, in: lastCharacterParagraph)
            return
        }
        setParagraphSpacing(0, in: lastCharacterParagraph)
        if lastCharacterParagraph.location > 0 {
            let upper = text.paragraphRange(for: NSRange(location: lastCharacterParagraph.location - 1, length: 0))
            setParagraphSpacing(BodyLayout.blockSpacing, in: upper)
        }
    }

    private func setParagraphSpacing(_ spacing: CGFloat, in range: NSRange) {
        guard range.length > 0 else { return }
        let current = textStorage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        if current?.paragraphSpacing == spacing { return }
        updating = true
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle(isLastParagraph: spacing == 0), range: range)
        updating = false
    }

    // OS の操作で文字選択・カーソルが変わったとき
    func textViewDidChangeSelection(_ textView: UITextView) {
        // 文字を選んでいる間は、「.」を出さない
        speakingDotsView.isHidden = speakingDotsPlace == nil || selectedRange.length > 0
        guard !updating, isFirstResponder else { return }
        adjustTypingAttributes()
    }

    // これから打つ文字に、どのメモの文字かの印を付ける
    //   段落の先頭ではその段落の文字を、それ以外ではカーソルの前の文字を引き継ぐ（前の段落の印が付かないように）
    private func adjustTypingAttributes() {
        let text = textStorage.string as NSString
        let caret = selectedRange.location
        var sourceIndex: Int?
        let atParagraphStart = caret == 0 || text.character(at: caret - 1) == newlineCharacter
        if atParagraphStart, caret < text.length, text.character(at: caret) != newlineCharacter {
            sourceIndex = caret
        } else if caret > 0 {
            sourceIndex = caret - 1
        }
        // 書き直せないメモの印は引き継がない
        var inheritedId = sourceIndex.flatMap(memoId(at:))
        if let id = inheritedId, editSession?.editableIds.contains(id) != true { inheritedId = nil }
        typingAttributes = bodyAttributes(memoId: inheritedId, isLastParagraph: false)
    }

    // その文字が元々どのメモの文字だったか（印が無ければ nil）
    private func memoId(at index: Int) -> Int64? {
        (textStorage.attribute(.memoId, at: index, effectiveRange: nil) as? NSNumber)?.int64Value
    }

    // ---------------------------------
    // カーソルとコピー
    // ---------------------------------
    // カーソルの高さを、行の高さ（行間や段落の下の余白を含む）ではなく、文字の高さに合わせる（少しだけ上下に伸ばす）
    override func caretRect(for position: UITextPosition) -> CGRect {
        let lineCaret = super.caretRect(for: position)
        guard !lineCaret.isNull, !lineCaret.isInfinite, textStorage.length > 0 else { return lineCaret }
        return textBand(of: lineCaret)
    }

    // 選択の色の帯と両端のつまみ（OS の枠は、段落の最後の行だけ段落の下の余白の分まで伸びているので、それを縮める）
    //   つまみ: いつもカーソルと同じ高さ
    //   色の帯: 1行に収まるときはカーソルと同じ高さ。何行にもわたるときは行の間も塗ってつなげ、一番下だけ段落の下の余白を外す
    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        let systemRects = super.selectionRects(for: range)
        guard textStorage.length > 0 else { return systemRects }
        let highlightBoxes = systemRects.map(\.rect).filter { $0.width >= 1 }
        let isMultiLine = highlightBoxes.count > 1 || !highlightBoxes.allSatisfy(fitsInOneLine)
        let lowestBottom = highlightBoxes.map(\.maxY).max() ?? 0

        var adjusted: [UITextSelectionRect] = []
        for selectionRect in systemRects {
            let box = selectionRect.rect
            let band = textBand(of: box)
            // --- 色の帯
            if box.width >= 1 {
                var highlight = box
                if !isMultiLine {
                    highlight = band
                } else if box.maxY >= lowestBottom - 0.5 && fitsInOneLine(box) {
                    // 文字の下にも、文字の上と同じだけの余白を残す
                    highlight.size.height = min(box.height, band.maxY + (band.minY - box.minY) - box.minY)
                }
                adjusted.append(MemoSelectionRect(base: selectionRect, rect: highlight))
            } else if !selectionRect.containsStart && !selectionRect.containsEnd {
                adjusted.append(MemoSelectionRect(base: selectionRect, rect: band))
            }
            // --- つまみ（OS が色の帯に兼ねさせていても、幅の無い枠に分けて出す）
            if selectionRect.containsStart {
                let startEdge = CGRect(x: box.minX, y: band.minY, width: 0, height: band.height)
                adjusted.append(MemoSelectionRect(base: selectionRect, rect: startEdge, marksStart: true))
            }
            if selectionRect.containsEnd {
                let endEdge = CGRect(x: box.maxX, y: band.minY, width: 0, height: band.height)
                adjusted.append(MemoSelectionRect(base: selectionRect, rect: endEdge, marksEnd: true))
            }
        }
        return adjusted
    }

    // OS が出した枠が、上端の行の枠（段落の下の余白を含む）の中に収まっているか
    private func fitsInOneLine(_ box: CGRect) -> Bool {
        let pointInLine = CGPoint(x: box.minX - textContainerInset.left, y: box.minY - textContainerInset.top + 1)
        let glyph = layoutManager.glyphIndex(for: pointInLine, in: textContainer)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return box.maxY - textContainerInset.top <= lineRect.maxY + 1
    }

    // OS が出した行の枠を、その行の文字の上下の真ん中を中心に、文字の高さ×caretHeightRatio へ縮める
    private func textBand(of lineBox: CGRect) -> CGRect {
        let font = bodyFont
        let glyphHeight = font.ascender - font.descender
        let height = glyphHeight * BodyLayout.caretHeightRatio
        let pointInLine = CGPoint(x: lineBox.minX - textContainerInset.left, y: lineBox.minY - textContainerInset.top + 1)
        // 文書の末尾の空の行は、文字が無いので、行の上下の真ん中に置く
        let extraLine = layoutManager.extraLineFragmentRect
        if extraLine.height > 0 && pointInLine.y >= extraLine.minY {
            return CGRect(x: lineBox.minX, y: lineBox.midY - height / 2, width: lineBox.width, height: height)
        }
        // OS が枠を置いた行（折り返しの境目では、前の行の末尾のこともある）の文字の上下の真ん中に合わせる
        let glyph = layoutManager.glyphIndex(for: pointInLine, in: textContainer)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = textContainerInset.top + lineRect.minY + layoutManager.location(forGlyphAt: glyph).y
        let glyphMidY = baseline - font.ascender + glyphHeight / 2
        return CGRect(x: lineBox.minX, y: glyphMidY - height / 2, width: lineBox.width, height: height)
    }

    // 文字選択の両端（OS のつまみが出るところ）の近くに、点が入っているか
    fileprivate func selectionEdgeContains(_ point: CGPoint) -> Bool {
        guard let range = selectedTextRange, !range.isEmpty else { return false }
        return [range.start, range.end].contains { position in
            caretRect(for: position).insetBy(dx: -ScrollThumbLayout.selectionEdgeTouchMargin,
                                             dy: -ScrollThumbLayout.selectionEdgeTouchMargin).contains(point)
        }
    }

    // 選択の外をタップしたら、選択を外してそこにカーソルを置く
    //   OS は、選択の終わりの行で選択より右をタップしても、選択を外さないことがあるため（実機のログで確認）
    @objc fileprivate func tappedOutsideSelection(_ recognizer: UITapGestureRecognizer) {
        guard isFirstResponder, selectedRange.length > 0 else { return }
        let point = recognizer.location(in: self)
        // OS のつまみを触ったときは、何もしない
        if selectionEdgeContains(point) { return }
        guard let position = closestPosition(to: point) else { return }
        let offset = self.offset(from: beginningOfDocument, to: position)
        // 選択の中（両端を含む）のタップは、OS のとおりメニューの出し入れに任せる
        let selection = selectedRange
        if offset >= selection.location && offset <= NSMaxRange(selection) { return }
        selectedRange = NSRange(location: offset, length: 0)
    }

    // 選択範囲を、段落の間に区切りを入れてクリップボードへ入れる
    override func copy(_ sender: Any?) {
        guard selectedRange.length > 0 else { return }
        let selected = (textStorage.string as NSString).substring(with: selectedRange)
            .replacingOccurrences(of: BodyLayout.emptyBlockText, with: "")
        UIPasteboard.general.string = selected.components(separatedBy: "\n").joined(separator: copySeparator)
    }

    // ---------------------------------
    // レイアウト
    // ---------------------------------
    override func layoutSubviews() {
        let oldSize = lastLayoutSize
        let wasAtBottom = contentOffset.y >= contentSize.height + contentInset.bottom - oldSize.height - BodyLayout.atBottomTolerance
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        // 一番下までスクロールしたときだけ、最新の行をホームインジケーターの上へ離す（途中では下を通り抜けて流れる）
        let bottomInset = safeAreaInsets.bottom + BodyLayout.paddingBottom + speakingDotsReservedHeight
        if abs(textContainerInset.bottom - bottomInset) > 0.5 {
            textContainerInset.bottom = bottomInset
            needsDocumentLayout = true
        }
        if needsDocumentLayout || oldSize != bounds.size {
            needsDocumentLayout = false
            layoutDocument()
        }
        layoutSpeakingDots()
        if isFirstResponder {
            // 書いている間に一覧の大きさが変わったときは、カーソルの行が見えるようにする
            if oldSize != bounds.size { scrollCaretIntoView() }
        } else if isFirstLayout || (oldSize != bounds.size && wasAtBottom && editSession == nil) {
            // 最初と、一番下を見ている間に一覧の高さが変わったときは、一番下へ
            contentOffset = CGPoint(x: 0, y: scrollableHeight)
        }
        layoutRail()
        isFirstLayout = false
        lastLayoutSize = bounds.size
    }

    // ---------------------------------
    // キーボードとの重なり
    // ---------------------------------
    // 一覧の大きさは変えず（Flutter に縮めさせると、毎フレーム組み直してチラつく）、隠れる分だけ下の余白を足して、キーボードと同じ動きで広げ縮めする
    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let window, let info = notification.userInfo,
              let endFrame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let keyboardInView = convert(window.convert(endFrame, from: window.screen.coordinateSpace), from: window)
        let overlap = max(0, bounds.maxY - keyboardInView.minY)
        // ほかの画面の入力欄で出たキーボードには合わせない（閉じたときだけは戻す）
        guard isFirstResponder || overlap == 0 else { return }
        guard abs(contentInset.bottom - overlap) > 0.5 else { return }

        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curve = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve << 16)) {
            self.contentInset.bottom = overlap
            if self.isFirstResponder { self.scrollCaretIntoView() }
        }
    }

    private func scrollCaretIntoView() {
        guard let range = selectedTextRange else { return }
        let caret = caretRect(for: range.end)
        guard !caret.isNull, !caret.isInfinite else { return }
        scrollRectToVisible(caret.insetBy(dx: 0, dy: -BodyLayout.paddingBottom), animated: false)
    }

    // ステータスバーに重なる高さが変わったら、上の余白を求め直す
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        needsDocumentLayout = true
        setNeedsLayout()
    }

    // メモが少ないうちは上の余白を広げて一覧を下に寄せ、ブロックの区切りの位置を求め直す
    //   一番上までスクロールしたときだけ、いちばん古い行をステータスバーの下へ離す（途中では裏を通り抜けて流れる）
    private func layoutDocument() {
        layoutManager.ensureLayout(for: textContainer)
        let documentHeight = layoutManager.usedRect(for: textContainer).height
        let minTopInset = safeAreaInsets.top + BodyLayout.minPaddingTop
        let topInset = max(minTopInset, bounds.height - documentHeight - textContainerInset.bottom)
        if abs(textContainerInset.top - topInset) > 0.5 { textContainerInset.top = topInset }
        layoutBoundaries(top: topInset)
    }

    // 縦線・横線の View は、スクロールしても表示範囲に重ねたまま留め、本文より後ろに置く
    private func layoutRail() {
        rail.frame = CGRect(x: 0, y: contentOffset.y, width: bounds.width, height: bounds.height)
        sendSubviewToBack(rail)
        rail.setNeedsDisplay()
    }

    // ---------------------------------
    // 段落の区切りの位置（上の段落の最後の行の文字の下端と、この段落の1行目の文字の上端のちょうど間）
    // ---------------------------------
    private func layoutBoundaries(top: CGFloat) {
        guard !blocks.isEmpty, textStorage.length > 0 else {
            boundaryYs = []
            return
        }
        let glyphTops = blocks.map { glyphTopAndBottom(atCharacter: $0.range.location).top + top }
        var boundaries = glyphTops
        for index in blocks.indices.dropFirst() {
            // 空の段落は、区切りの改行の位置で測る
            let upperLastCharacter = max(blocks[index - 1].range.location, NSMaxRange(blocks[index - 1].range) - 1)
            let upperBottom = glyphTopAndBottom(atCharacter: upperLastCharacter).bottom + top
            boundaries[index] = (upperBottom + glyphTops[index]) / 2
        }
        // 一番上の段落には上の段落がないので、2番目の段落と同じだけ文字の上端から離す
        let halfGap = blocks.count > 1 ? glyphTops[1] - boundaries[1] : RailLayout.singleBlockBoundaryGap
        boundaries[0] = glyphTops[0] - halfGap
        boundaryYs = boundaries
    }

    // 文字の上端・下端（行高やブロック間隔の余白を含まない、フォントの ascender・descender の範囲）
    private func glyphTopAndBottom(atCharacter index: Int) -> (top: CGFloat, bottom: CGFloat) {
        // 文書の末尾の空の段落などは、最後の文字で測る
        let characterIndex = min(max(0, index), textStorage.length - 1)
        let glyph = layoutManager.glyphIndexForCharacter(at: characterIndex)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = lineRect.minY + layoutManager.location(forGlyphAt: glyph).y
        let font = textStorage.attribute(.font, at: characterIndex, effectiveRange: nil) as? UIFont
            ?? UIFont.systemFont(ofSize: bodySize)
        return (baseline - font.ascender, baseline - font.descender)
    }

    // ---------------------------------
    // 発話中の「.」の位置（最新のブロックの本文の続き、または次のブロックの1行目）
    // ---------------------------------
    // 次のブロックの1行目に出すあいだは、ブロック間の余白と1行分の高さを文書の下に空けておく
    private var speakingDotsReservedHeight: CGFloat {
        speakingDotsPlace == .newBlock ? BodyLayout.blockSpacing + lastLineRect.height : 0
    }

    // 本文の最後の行（まだ本文が無いときは、見込みの高さの行が先頭にあるものとする）
    private var lastLineRect: CGRect {
        guard textStorage.length > 0 else {
            return CGRect(x: 0, y: 0, width: 0, height: bodySize * BodyLayout.emptyLineHeightRatio)
        }
        let glyph = layoutManager.glyphIndexForCharacter(at: textStorage.length - 1)
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    }

    // 行の上端から文字のベースラインまで
    private var lastLineBaselineOffset: CGFloat {
        guard textStorage.length > 0 else {
            let font = bodyFont
            return (bodySize * BodyLayout.emptyLineHeightRatio - font.lineHeight) / 2 + font.ascender
        }
        let glyph = layoutManager.glyphIndexForCharacter(at: textStorage.length - 1)
        return layoutManager.location(forGlyphAt: glyph).y
    }

    private func layoutSpeakingDots() {
        guard let place = speakingDotsPlace else {
            speakingDotsView.isHidden = true
            return
        }
        let lineRect = lastLineRect
        let containerWidth = textContainer.size.width
        switch place {
        case .append:
            // 最後の行の文字の右端から、行の右端までに収める
            guard let latestBlock = blocks.last, !latestBlock.text.isEmpty else {
                speakingDotsView.isHidden = true
                return
            }
            let lastCharacter = NSMaxRange(latestBlock.range) - 1
            let glyph = layoutManager.glyphIndexForCharacter(at: lastCharacter)
            let textRight = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).maxX
            speakingDotsView.place(x: textContainerInset.left + textRight,
                                   baseline: textContainerInset.top + lineRect.minY + lastLineBaselineOffset,
                                   availableWidth: containerWidth - textRight,
                                   font: bodyFont, color: bodyColor)
        case .newBlock:
            let lineTop = textStorage.length > 0
                ? textContainerInset.top + lineRect.maxY + BodyLayout.blockSpacing
                : textContainerInset.top
            speakingDotsView.place(x: textContainerInset.left,
                                   baseline: lineTop + lastLineBaselineOffset,
                                   availableWidth: containerWidth,
                                   font: bodyFont, color: bodyColor)
        }
        // 文字を選んでいる間は、「.」を出さない
        speakingDotsView.isHidden = selectedRange.length > 0
    }

    // ---------------------------------
    // 右の縦線と、日付の区切りの横線
    // ---------------------------------
    // 縦線・横線の View の上に描く
    fileprivate func drawRail() {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        defer { context.restoreGState() }
        railColor.setStroke()
        context.setLineWidth(RailLayout.lineWidth)
        // 縦線は一覧の枠の一部として、スクロールしても動かさず、一覧の上端から下端まで引く（メモが無くても出す）
        let x = bounds.width - RailLayout.xFromRight
        context.move(to: CGPoint(x: x, y: 0))
        context.addLine(to: CGPoint(x: x, y: bounds.height))
        // 横線は文書の座標で描けるよう、表示範囲の上端の分だけずらす
        context.translateBy(x: 0, y: -contentOffset.y)
        // 横線は、その日の最初の段落の区切りに、画面の端から端まで引く（一番上の段落には引かない）
        for (index, block) in blocks.enumerated().dropFirst() where block.startsDay && index < boundaryYs.count {
            let y = boundaryYs[index]
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
        }
        context.strokePath()
    }

    // ---------------------------------
    // スクロールつまみ（縦線の上を、表示範囲の中だけ動く。y は表示範囲の上端から測る）
    // ---------------------------------
    // キーボードに隠れる分（contentInset.bottom）も、その上へスクロールできる高さに含める
    private var scrollableHeight: CGFloat { max(0, contentSize.height + contentInset.bottom - bounds.height) }

    // 上端はステータスバーの下から動かす。下端がホームインジケーターに重なるときは、その上に広めの余白をとる
    // （ホームへ戻る操作の受付領域では掴みにくいため）
    private var scrollThumbTrack: ClosedRange<CGFloat> {
        let top = safeAreaInsets.top + ScrollThumbLayout.trackMargin
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
        return showsScrollThumb && point.x >= bounds.width - ScrollThumbLayout.touchWidth
            && abs(y - scrollThumbCenterY) <= ScrollThumbLayout.touchHeight / 2
    }

    // 縦線の View の上に描く
    fileprivate func drawScrollThumb() {
        guard showsScrollThumb else { return }
        let centerX = bounds.width - RailLayout.xFromRight
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
// 縦線・横線とスクロールつまみを描く View（触れても反応せず、操作は本文が受け取る）
// ---------------------------------
private final class MemoRailView: UIView {
    weak var document: MemoDocumentView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("ストーリーボードからは生成しません") }

    override func draw(_ rect: CGRect) {
        document?.drawRail()
        document?.drawScrollThumb()
    }
}

// ---------------------------------
// つまみの上で指を置いてすぐ動かしたときだけ、一覧のスクロールより先にドラッグとして受け取る
// ---------------------------------
// 動かさずに待てば OS の長押しが先に成立し、文字選択になる
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
        // 文字選択の端（OS のつまみ）を掴んだときは、そちらを優先する
        return document.scrollThumbContains(point) && !document.selectionEdgeContains(point)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other === document?.panGestureRecognizer
    }
}

// ---------------------------------
// 選択の枠の1つを、位置と大きさ、選択の始まり・終わりの印を差し替えたもの（向きは OS のものをそのまま使う）
// ---------------------------------
private final class MemoSelectionRect: UITextSelectionRect {
    private let base: UITextSelectionRect
    private let adjustedRect: CGRect
    private let marksStart: Bool
    private let marksEnd: Bool

    init(base: UITextSelectionRect, rect: CGRect, marksStart: Bool = false, marksEnd: Bool = false) {
        self.base = base
        adjustedRect = rect
        self.marksStart = marksStart
        self.marksEnd = marksEnd
        super.init()
    }

    override var rect: CGRect { adjustedRect }
    override var writingDirection: NSWritingDirection { base.writingDirection }
    override var containsStart: Bool { marksStart }
    override var containsEnd: Bool { marksEnd }
    override var isVertical: Bool { base.isVertical }
}

// ---------------------------------
// キーボードをしまう丸いボタン（iPhone のキーボードには、しまうキーが無いため）
// ---------------------------------
private enum KeyboardDismissLayout {
    // ボタンの直径と、キーボード・画面の右端からの距離
    static let diameter: CGFloat = 48
    static let margin: CGFloat = 8
}

private final class MemoKeyboardDismissButton: UIButton {
    init() {
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.glass()
        configuration.image = UIImage(systemName: "keyboard.chevron.compact.down")
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .capsule
        self.configuration = configuration
        accessibilityLabel = Locale.preferredLanguages.first?.hasPrefix("ja") == true ? "キーボードを閉じる" : "Hide keyboard"
    }

    required init?(coder: NSCoder) { fatalError("ストーリーボードからは生成しません") }
}

// ---------------------------------
// 発話中の気配として、0.5秒ごとに「.」を1つずつ増やし、行に収まる数（最大10個）まで増えたら0個に戻す
// ---------------------------------
private final class MemoSpeakingDotsView: UIView {
    private static let interval: TimeInterval = 0.5
    private static let maxDotCount = 10
    private var timer: Timer?
    // 今出している「.」の数と、行に収まる数
    private var dotCount = 0
    private var fittingDotCount = 0
    private var font = UIFont.systemFont(ofSize: CGFloat(DefaultValue.fontSize))
    private var color = UIColor.label

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("ストーリーボードからは生成しません") }

    deinit { timer?.invalidate() }

    // 動いている途中なら、数えている途中から続ける
    func start() {
        guard timer == nil else { return }
        dotCount = 0
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.advance() }
        // スクロール中も止めずに増やす
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        setNeedsDisplay()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        dotCount = 0
        setNeedsDisplay()
    }

    // x と baseline は文書の座標。「.」は availableWidth に収まる数までしか増やさない（折り返すと一覧の高さが変わるため）
    func place(x: CGFloat, baseline: CGFloat, availableWidth: CGFloat, font: UIFont, color: UIColor) {
        self.font = font
        self.color = color
        let dotWidth = ("." as NSString).size(withAttributes: [.font: font]).width
        fittingDotCount = dotWidth > 0 ? min(Self.maxDotCount, max(0, Int(availableWidth / dotWidth))) : 0
        if dotCount > fittingDotCount { dotCount = 0 }
        frame = CGRect(x: x, y: baseline - font.ascender, width: max(0, availableWidth), height: font.lineHeight)
        setNeedsDisplay()
    }

    private func advance() {
        dotCount = fittingDotCount > 0 ? (dotCount + 1) % (fittingDotCount + 1) : 0
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard dotCount > 0 else { return }
        (String(repeating: ".", count: dotCount) as NSString)
            .draw(at: .zero, withAttributes: [.font: font, .foregroundColor: color])
    }
}

// ---------------------------------
// 選択の外へのタップ（OS のタップ・ダブルタップ・スクロールの邪魔はせず、横で一緒に受け取る）
// ---------------------------------
private final class MemoOutsideSelectionTap: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    init(document: MemoDocumentView) {
        super.init(target: document, action: #selector(MemoDocumentView.tappedOutsideSelection(_:)))
        cancelsTouchesInView = false
        delaysTouchesEnded = false
        delegate = self
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
