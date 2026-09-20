# S5 事前の独立したソース診断

2026-09-20。実機設定探索は未実施。

`maxSpeechDuration=30`はハード上限ではない。sherpaのVoiceActivityDetector::Impl::AcceptWaveformはbuffer_.Size()>max_utterance_length_のとき、minSilenceDurationを0.1秒、thresholdを0.90に切り替える。サンプルを30秒で強制分割する処理ではなく、その後も発話判定なら継続する。
Dart 1.13.3のvad.dartではmaxSpeechDurationをC構造体に渡しているので、Dart側の渡し忘れとはいえない。
従って「30秒設定なのに37.174秒」はライブラリのこの意味と整合する。個々の境界の確率系列を計測したわけではないため、各ファイルの切断時刻の完全な因果証明ではない。
本番コメント「上限」やカタログの「強制区切り」は実装の意味より強い。ここでは本番コード・設定を変更しない。

一次資料（リリースタグを固定。未リリースmasterではない）:
- https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.3/sherpa-onnx/csrc/voice-activity-detector.cc#L46-L61
- https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/voice-activity-detector.cc#L46-L61
- 同ファイルL189-L214（設定値から長さへの変換、超過時の0.1秒/0.90）

再開条件: S2の欠けの聴感判断、最終判定用音声（無い場合は調整用だけと明記）を得てから、一度に一設定だけ振る。ハードカット導入は単なる設定反映の修正ではなく別の介入なので、効果と副作用を測る必要がある。
