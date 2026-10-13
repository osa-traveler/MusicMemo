# MusicMemo

コードとメロディを譜面入力でスケッチし、Logicへ書き出すための iPad / Mac アプリ（個人用）。

## 最初に読むもの

| ファイル | 内容 |
| --- | --- |
| `docs/APP_SPEC.md` | **いま実装されている仕様**。操作、表示のルール、実装しながら決めた値 |
| `docs/ROADMAP.md` | **今後の課題**。確認が残っていること、次に作るもの、既知の制限 |
| `docs/SPEC.md` | デザイン段階の画面仕様（元の仕様書）。未決事項のうち決めたものはチェック済み |
| `docs/screens/`、`docs/reference/*.html` | 画面のデザインモック。`01_main_100.png` が基準。寸法・色・座標の正確な値は HTML から読む |
| `README.md` | セットアップ手順とフォルダ構成 |

HTMLはデザインモック。構造を移植するのではなく、ネイティブUIで同じ見た目と挙動を再現する。

## 現状（2026-10-13 時点）

- CLAUDE.md の当初の7段階（データモデル → 譜面の静的表示 → ルーラ等 → 全体ビュー → ズーム → 入力 → 書き出し）は完了
- そのあと、再生とメトロノーム、音源の差し替え（FluidR3_GM）、保存（1曲＝1ファイル）を実装済み
- これからは「使いながら調整」の段階。次の候補は `docs/ROADMAP.md` の「次に作るもの」（曲の設定、トラックの操作、セクションの操作、コード入力ビュー、入力方法の追加）

## 進め方

- いきなり全部作らず、段階ごとに動く状態にする
- 各段階の前に実装計画を示し、確認を取ってから書く。決める必要のある点は、おすすめを添えて質問にまとめる
- SPEC.md の「未決事項」や、仕様に無い判断は勝手に決めず質問する。実装の都合で決めた細部は、報告のときに「決めたこと」として伝える
- 段階が終わったら、ビルド・テスト・撮影で確認してから報告し、確認をもらってからコミット・プッシュする
- 仕様や決めた値が変わったら `docs/APP_SPEC.md` と `docs/ROADMAP.md` も更新する
- やりとり・コメント・ドキュメントは日本語

## 開発の手順

```sh
Scripts/fetch-soundfont.sh               # 音源（FluidR3_GM、約148MB）を取得。リポジトリには含めない
xcodegen generate                        # .xcodeproj と Support/Info.plist を生成（ファイルを追加・削除したらやり直す）
cd Packages/MusicMemoCore && swift test  # モデル層のテスト
Scripts/snapshot.sh 出力.png [倍率] [入力デモ]  # Mac のデバッグビルドで画面を撮影
```

- ビルドの確認：Mac（`-destination 'platform=macOS'`）と iPad（`-destination 'generic/platform=iOS Simulator'`）の両方
- この Mac には iOS 26 のシミュレータが無いので、iPad はビルドの確認だけ。実機の確認はユーザーに頼む
- 画面の確認は `Scripts/snapshot.sh` で撮影し、`docs/screens/` の基準画面と見比べる（画面収録の権限は不要）
- 操作や再生の確認は、デバッグビルドの環境変数（`docs/APP_SPEC.md` の「開発用の仕組み」）で自動実行し、ログ（`log show --predicate 'subsystem == "MusicMemo"'`）や保存されたファイルで確かめる
- 音は直接聞けないので、出力レベル（`MUSICMEMO_PLAY_CHECK=1`）やオフライン合成の数値で確かめ、最終的な聞こえ方はユーザーに確認してもらう

## 注意すること

- **公開リポジトリ**（GitHub）。プッシュ前に、個人情報（メールアドレス、Mac のユーザーフォルダのパスなど）と、他者の権利を侵害するもの（ライセンスの不明な素材、大きな音源ファイル）が入っていないか確認する
- コミットの作者メールはこのリポジトリだけ GitHub の noreply アドレスに設定済み（`git config user.email`）。変えない
- 外部の素材を入れるときは `THIRD_PARTY_NOTICES.md` に取得元とライセンスを記録する。SoundFont はリポジトリに入れず、取得スクリプトでハッシュを固定して取る
- プロセスを止めるときは、自分が起動したビルド（`.build/DerivedData` や作業用フォルダのもの）だけを対象にする。ユーザーが Xcode から実行しているアプリ（`~/Library/Developer/Xcode/DerivedData` のもの）は止めない
- 音源：GeneralUser GS は AVAudioUnitSampler で再生中に落ちるため使わない。音源を替えるときは `MUSICMEMO_SOUNDBANK` と `MUSICMEMO_PLAY_CHECK` で落ちないことを何度か確かめてから採用する
- AVAudioUnitSampler は、エンジンが動いている最中に音色を読み込むと落ちることがある。音色の変更を作るときはエンジンを止めてから読み込む
