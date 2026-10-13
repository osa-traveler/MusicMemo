# Third-party notices

## Bravura

- 用途：譜面の記号（音部記号・符頭・休符・臨時記号など）の描画
- 取得元：https://github.com/steinbergmedia/bravura （リリース bravura-1.482 の `Bravura.otf`）
- 著作権：Copyright © 2015, Steinberg Media Technologies GmbH, with Reserved Font Name "Bravura"
- ライセンス：SIL Open Font License 1.1（全文は [App/Resources/Fonts/Bravura-OFL.txt](App/Resources/Fonts/Bravura-OFL.txt)）
- 改変なしで同梱している

## GeneralUser GS

- 用途：iPad の鍵盤の音と再生（AVAudioUnitSampler で読み込む GM 音色）。Mac では使っていない（macOS 標準の音源 gs_instruments.dls を使う。OS に入っているものを読むだけで、同梱・再配布はしない）
- 取得元：https://github.com/mrbumpy409/GeneralUser-GS （v2.0.3、コミット 97049183643d5fc5a9322a69c5b09efb667c6c3a）
- 作者：S. Christian Collins（https://www.schristiancollins.com/generaluser）
- ライセンス：GeneralUser GS License v2.0（取得元の documentation/LICENSE.txt）。個人・商用の音楽制作に制限なく使え、ソフトウェアへの組み込みも認められている
- **このリポジトリには含めていない**。ライセンスに「一部のサンプルの出所を完全には確認できていない」旨の記載があるため、公開リポジトリでの再配布は避け、`Scripts/fetch-soundfont.sh` で取得する（コミットとハッシュを固定）
