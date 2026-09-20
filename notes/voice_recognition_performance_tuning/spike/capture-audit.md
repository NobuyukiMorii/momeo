# S2 capture-audit — 2026-09-20

ブランチ: `spike/voice_recognition_performance_tuning/capture-audit`、S3 `96cf384`から。
状態: 診断コード準備済み、実機録音・人の聴感判定は未完了。

## 実装

S3の録り込みにdebug限定で生PCMを観測する経路を追加。新規VADの初回録音を対象とし、VADのclear/flush後のサンプル原点を推測しない。再測定はアプリ再起動から行う。
`spike_capture_audit/<時刻>_session.wav` と、各発話の `_raw.wav`（前後最大0.5秒）/ `_vad.wav`、pairs.tsv、stop.tsv を端末内に保存する。writeWaveは既存sherpaを使用。
対応位置は `SpeechSegment.start` を用い、生PCMとサンプル全件一致を確認したペアだけを書き出す。不一致・保存失敗を未検証として記録。10分を超えた録音はoverflowとして記録し、診断用メモリの増大を止める。認識入力・しきい値・端数処理を変更しない。
停止時の未投入サンプル数をstop.tsvへ記録する。条件チップは既存の録り込み画面に追加し、capture_conditions.tsvへ保存する。
聴感メモはlistened=pendingで開始する。未記入を「問題なし」には扱わない。

## 検証

- 変更3ファイルのflutter analyze成功。
- Android arm64 debugビルド成功。
- 既存S3音声25件をwaveヘッダから再点検: 30秒超8件、最長37.174秒。これは過去の録音であり、今回の新規測定ではない。

## 保留と再開条件

小声・距離・生活音・相づち・停止直後・機器切替など、指定条件での本人の新しい録音が必要。既存wavは切り出し済みであり、失われた切り出し前の音は復元できない。
人の聴感判定が必要な理由: 欠けた語をモデル出力から推測しても境界の診断にはならない。pairs.tsvのlistenedを確認済みにしてmissingWords/cut/noteを記入する。判定がない間はS2未完了、S5設定探索は保留。

S2の新規録音は `files/spike_audio_s2/` に分離する。既存S3の25wav/answers.tsvを増減・上書きせず、S4以降の比較対象集合を固定する。録り込み画面の条件・正解入力もS2専用の同ディレクトリを使う。
