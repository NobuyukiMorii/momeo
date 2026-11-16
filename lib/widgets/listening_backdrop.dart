import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:momeo/foundation/app_colors.dart';

// ============================================================
// ListeningBackdrop — リスニング画面の背景に流れる音量波形
//
//   マイク音量にリアルタイム連動する波線を、画面全体の背景として描く。
//   「何も操作していなくても常に耳を澄ませている」という気配を出すための
//   もの。メモ一覧は手前に重なり、この波形はその後ろに見える。
//
//   ■ つくり
//   - 入力は levelReader()（直近のピーク音量 0.0〜1.0）。音の取り込みは
//     外（リスニングのパイプライン）が担うため、このウィジェットは
//     描画だけに徹する。
//   - Ticker で毎フレーム、音量を平滑化→ゲイン→無音揺れし、一定間隔で履歴に記録する。
//   - 線の頂点は画面上の位置に固定し、各頂点で「何秒前の音か」を求めて履歴から値を引く。
//     頂点そのものは動かないので、線の端や波の形が流れに合わせてガタつかない。
//   - 新しい音は右端に現れ、左へ流れて左端から消える。
//
//   ■ チューニング値（実機で整える）
//   感度・速さ・揺れの大きさは末尾の定数を1箇所で調整できる。
// ============================================================

// ---------------------------------
// リスニング画面の背景に流れる音量波形
// ---------------------------------
class ListeningBackdrop extends StatefulWidget {
  const ListeningBackdrop({super.key, required this.levelReader});

  // 直近のピーク音量（0.0=無音 〜 1.0=最大）を返す。
  // 毎フレーム呼ばれるため、重い処理を入れないこと。
  final double Function() levelReader;

  @override
  State<ListeningBackdrop> createState() => _ListeningBackdropState();
}

// ---------------------------------
// 状態管理
// ---------------------------------
class _ListeningBackdropState extends State<ListeningBackdrop>
    with TickerProviderStateMixin {

  // ---------------------------------
  // 変数
  // ---------------------------------

  // 毎フレームの再描画を駆動するタイマー
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  // 過去の音量履歴（末尾が新しい）。_historyStepSec ごとに1つ記録する
  final List<double> _history =
      List<double>.filled(_historyLength, 0.0, growable: true);

  // エンベロープ平滑後の値と、それにゲインと無音揺れを掛けた「いまの音量」
  double _smoothed = 0.0;
  double _current = 0.0;

  // 最後に履歴へ記録してからの経過秒数
  double _sinceLastRecordSec = 0.0;

  // 無音揺れの位相（時間とともに進む）
  double _idlePhase = 0.0;

  // ---------------------------------
  // 初期化
  // ---------------------------------
  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  // ---------------------------------
  // 破棄
  // ---------------------------------
  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // ---------------------------------
  // 毎フレーム：経過時間分だけ状態を進め、再描画する
  // ---------------------------------
  void _onTick(Duration elapsed) {
    final dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    setState(() => _advance(dt));
  }

  // ---------------------------------
  // 指定時間分だけ音量を処理して履歴を進める
  // ---------------------------------
  void _advance(Duration dt) {
    var dtSec = dt.inMicroseconds / 1000000.0;
    if (dtSec <= 0) return;
    // 画面復帰直後などに極端な飛びが出ないよう、1フレーム分を超える時間は打ち切る
    if (dtSec > 0.1) dtSec = 0.1;

    // ① 最新のピーク音量を取得（0.0〜1.0）
    final raw = widget.levelReader().clamp(0.0, 1.0).toDouble();

    // ② 非対称エンベロープ：音量が上がるときは素早く、下がるときはゆっくり追従
    final tauSec = raw > _smoothed ? _attackTauSec : _releaseTauSec;
    _smoothed += (raw - _smoothed) * (1 - exp(-dtSec / tauSec));

    // ③ 非線形ゲイン：小さな音を持ち上げてよく動くようにする
    _current = pow(_smoothed, _gainExponent).clamp(0.0, 1.0).toDouble();

    // ④ 完全無音でも常に命を持たせるため、微弱な揺れを下駄履き（実音が強ければそちらが優先）
    final idle = _idleAmplitude * (0.5 + 0.5 * sin(_idlePhase));
    if (_current < idle) _current = idle;
    _idlePhase += _idleFrequencyHz * 2 * pi * dtSec;

    // ⑤ 一定間隔ごとに、いまの音量を履歴の末尾へ記録し、古いものを捨てる
    _sinceLastRecordSec += dtSec;
    while (_sinceLastRecordSec >= _historyStepSec) {
      _sinceLastRecordSec -= _historyStepSec;
      _history.removeAt(0);
      _history.add(_current);
    }
  }

  // ---------------------------------
  // 描画
  // ---------------------------------
  @override
  Widget build(BuildContext context) {
    // RepaintBoundary で包み、毎フレームの再描画が ListView 側へ伝播しないようにする
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BackdropPainter(
          history: _history,
          current: _current,
          sinceLastRecordSec: _sinceLastRecordSec,
          color: AppColors.onSurfaceFaint,
        ),
        // 全面を覆うことで paint() の size に画面全体が入る
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ============================================================
// _BackdropPainter — 中央ラインを基準に揺れる、1本のなめらかな波線を描く
// ============================================================
class _BackdropPainter extends CustomPainter {
  _BackdropPainter({
    required this.history,
    required this.current,
    required this.sinceLastRecordSec,
    required this.color,
  });

  // ---------------------------------
  // 変数
  // ---------------------------------

  // State が破壊的に更新する履歴（参照で受け取る。末尾が新しい）
  final List<double> history;

  // いまの音量（右端＝0秒前の値）
  final double current;

  // 履歴の末尾を記録してからの経過秒数（＝末尾の値が何秒前のものか）
  final double sinceLastRecordSec;

  final Color color;

  // ---------------------------------
  // 描画
  // ---------------------------------

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final maxHalf = size.height * _maxAmplitudeFactor;

    // 空間的な搬送波（画面幅に _wavesAcross 本の山が来る周波数）。画面位置で固定する
    final carrier = 2 * pi * _wavesAcross / size.width;

    // 画面1pxが何秒ぶんの時間にあたるか（右端が「いま」、左端が _visibleSeconds 秒前）
    final secondsPerPx = _visibleSeconds / size.width;

    // 頂点は画面上の位置に固定し、左端から右端までちょうど並べる
    final vertexCount = max(1, (size.width / _vertexSpacingPx).ceil());

    final path = Path();
    for (var vertexIndex = 0; vertexIndex <= vertexCount; vertexIndex++) {
      final x = size.width * vertexIndex / vertexCount;
      final ageSec = (size.width - x) * secondsPerPx;
      final y = centerY + _levelAt(ageSec) * maxHalf * sin(x * carrier);
      if (vertexIndex == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  // ---------------------------------
  // 指定した秒数前の音量を、履歴から線形補間して返す
  // ---------------------------------
  double _levelAt(double ageSec) {
    // 末尾の記録より新しい区間は、いまの音量と末尾の記録をつなぐ
    if (ageSec <= sinceLastRecordSec) {
      if (sinceLastRecordSec <= 0) return current;
      return _lerp(current, history.last, ageSec / sinceLastRecordSec);
    }

    // それより古い区間は、隣り合う2つの記録をつなぐ
    final stepsBack = (ageSec - sinceLastRecordSec) / _historyStepSec;
    final newerIndex = history.length - 1 - stepsBack.floor();
    final olderIndex = newerIndex - 1;
    if (olderIndex < 0) return history.first;
    return _lerp(
      history[newerIndex],
      history[olderIndex],
      stepsBack - stepsBack.floor(),
    );
  }

  double _lerp(double from, double to, double ratio) =>
      from + (to - from) * ratio;

  // ---------------------------------
  // 再描画判定
  // ---------------------------------

  // 時間が進むだけで全頂点の値が変わるため、毎フレーム描き直す
  @override
  bool shouldRepaint(_BackdropPainter old) => true;
}

// ---------------------------------
// チューニング定数（実機で整える）
// ---------------------------------

const double _visibleSeconds = 1.68; // 右端から左端まで流れるのにかかる秒数
const double _historyStepSec = 0.02; // 音量を履歴へ記録する間隔（秒）
const double _vertexSpacingPx = 2.0; // 線の頂点の間隔（px）。小さいほどなめらか
const double _strokeWidth = 0.5; // 波線の太さ（px）
const double _wavesAcross = 2.0; // 画面幅に対する波の山の数（多いほど細かく揺れる）
const double _attackTauSec = 0.02; // 音量上昇の追従時定数（小さい=速い）
const double _releaseTauSec = 0.30; // 音量下降の追従時定数（大きい=ゆっくり）
const double _gainExponent = 0.5; // ゲイン曲線の指数（小さいほど小音を拡大）
const double _idleAmplitude = 0.06; // 無音揺れの振幅（最大振れ幅比）
const double _idleFrequencyHz = 0.4; // 無音揺れの周期
const double _maxAmplitudeFactor = 0.40; // 画面高さに対する、中央ラインからの最大振れ幅

// 画面に収まる時間ぶん＋補間用の余り2つを保持する
final int _historyLength = (_visibleSeconds / _historyStepSec).ceil() + 2;
