# MusicMemo

コードとメロディを譜面入力でスケッチし、Logic へ書き出すための iPad / Mac アプリ（個人用）。
仕様は [docs/SPEC.md](docs/SPEC.md)。

## セットアップ

```sh
brew install xcodegen          # 未導入なら
Scripts/fetch-soundfont.sh     # 鍵盤の音（GeneralUser GS）を取得。リポジトリには含めていない
xcodegen generate              # MusicMemo.xcodeproj を生成（SoundFont を取得したあとに実行）
open MusicMemo.xcodeproj
```

- SoundFont が無くてもビルド・起動はできる（音が鳴らないだけ）
- モデル層のテスト：`cd Packages/MusicMemoCore && swift test`

## 構成

| パス | 内容 |
| --- | --- |
| `App/` | SwiftUI のアプリ（iPad / Mac 共通） |
| `Packages/MusicMemoCore/` | 曲データ・記譜・入力の処理（UI に依存しない） |
| `Scripts/` | 補助スクリプト |
| `docs/` | 仕様書と画面のデザインモック |

使っている外部の素材は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
