import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:momeo/foundation/app_colors.dart';

// ============================================================
// ListeningBackdrop — リスニング画面の背景に流れる音量波形
//
//   マイク音量にリアルタイム連動する波線を、画面全体の背景として描く。
//   「何も操作していなくても常に耳を澄ませている」という気配を出すための
//   もの。カードは手前に不透明で乗り、この波形は隙間から覗く。
//
//   ■ つくり
//   - 入力は levelReader()（直近のピーク音量 0.0〜1.0）。音の取り込みは
//     外（リスニングのパイプライン）が担うため、このウィジェットは
//     描画だけに徹する。
//   - Ticker で毎フレーム、音量を平滑化→ゲイン→無音揺れ→履歴更新し、
//     CustomPaint で中央ラインを基準に揺れる、1本のなめらかな波線を描く。
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

  // 過去の音量履歴（右が新しい）。removeAt + add で左へずらすため可変長にする
  final List<double> _history =
      List<double>.filled(_sampleCount, 0.0, growable: true);

  // エンベロープ平滑後の現在値と、右端から入ってくる最新1サンプル分
  double _smoothed = 0.0;
  double _current = 0.0;

  // 1サンプル分のピッチに対するスクロール量 [0.0, 1.0)。1.0 に達したら履歴をずらす
  double _scrollFrac = 0.0;

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

    // ⑤ 1サンプル分のスクロールが進むごとに履歴を左へずらし、右端に最新を詰める（連続的な左への流れ）
    _idlePhase += _idleFrequencyHz * 2 * pi * dtSec;
    _scrollFrac += dtSec / _sampleIntervalSec;
    while (_scrollFrac >= 1.0) {
      _scrollFrac -= 1.0;
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
          scrollFrac: _scrollFrac,
          color: AppColors.onSurface.withValues(alpha: _lineOpacity),
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
    required this.scrollFrac,
    required this.color,
  });

  // ---------------------------------
  // 変数
  // ---------------------------------

  // State が破壊的に更新する履歴（参照で受け取る）
  final List<double> history;

  // 右端から入ってくる最新の1サンプル
  final double current;

  // 1サンプル分のピッチに対するスクロール量 [0.0, 1.0)
  final double scrollFrac;

  final Color color;

  // ---------------------------------
  // 描画
  // ---------------------------------

  @override
  void paint(Canvas canvas, Size size) {
    final count = history.length;
    final pitch = size.width / count;
    final cy = size.height / 2;
    final maxHalf = size.height * _maxAmplitudeFactor;

    // 空間的な搬送波（画面幅に _wavesAcross 本の山が来る周波数）。これに音量を掛けて
    // 1本の波線にする。搬送波は画面位置で固定し、音量（履歴）が右から左へ流れる
    final carrier = 2 * pi * _wavesAcross / size.width;

    // 各サンプル点の座標。音量を上下の振れ幅にし、搬送波で揺らして1本の線に結ぶ
    final points = <Offset>[];
    for (var i = 0; i <= count; i++) {
      final x = i * pitch - scrollFrac * pitch;
      final value = i < count ? history[i] : current;
      final y = cy + value * maxHalf * sin(x * carrier);
      points.add(Offset(x, y));
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 1本のなめらかな波線を描く
    canvas.drawPath(_smoothPath(points), paint);
  }

  // ---------------------------------
  // パスを返す
  // ---------------------------------
  Path _smoothPath(List<Offset> points) {
    final path = Path();
    if (points.length < 2) return path;
    path.moveTo(points[0].dx, points[0].dy);
    final n = points.length;
    for (var i = 0; i < n - 1; i++) {
      final p0 = points[i == 0 ? 0 : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[i + 2 < n ? i + 2 : i + 1];
      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  // ---------------------------------
  // 再描画判定
  // ---------------------------------

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      current != old.current ||
      scrollFrac != old.scrollFrac ||
      color != old.color;
}

// ---------------------------------
// チューニング定数（実機で整える）
// ---------------------------------

const int _sampleCount = 28; // 画面内のサンプル点の数
const double _strokeWidth = 0.5; // 波線の太さ（px）
const double _wavesAcross = 2.0; // 画面幅に対する波の山の数（多いほど細かく揺れる）
const double _sampleIntervalSec = 0.06; // 1サンプルぶんのスクロールにかかる秒数
const double _attackTauSec = 0.02; // 音量上昇の追従時定数（小さい=速い）
const double _releaseTauSec = 0.30; // 音量下降の追従時定数（大きい=ゆっくり）
const double _gainExponent = 0.5; // ゲイン曲線の指数（小さいほど小音を拡大）
const double _idleAmplitude = 0.06; // 無音揺れの振幅（最大振れ幅比）
const double _idleFrequencyHz = 0.4; // 無音揺れの周期
const double _maxAmplitudeFactor = 0.40; // 画面高さに対する、中央ラインからの最大振れ幅
const double _lineOpacity = 0.2; // 波線の濃さ（onSurface に対する透過）
