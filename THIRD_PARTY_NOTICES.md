# Third-party notices

## Bravura

- 用途：譜面の記号（音部記号・符頭・休符・臨時記号など）の描画
- 取得元：https://github.com/steinbergmedia/bravura （リリース bravura-1.482 の `Bravura.otf`）
- 著作権：Copyright © 2015, Steinberg Media Technologies GmbH, with Reserved Font Name "Bravura"
- ライセンス：SIL Open Font License 1.1（全文は [App/Resources/Fonts/Bravura-OFL.txt](App/Resources/Fonts/Bravura-OFL.txt)）
- 改変なしで同梱している

## FluidR3_GM

- 用途：鍵盤の音と再生（AVAudioUnitSampler で読み込む GM 音色）。iPad と Mac で共通
- 取得元：Debian の公式パッケージ fluid-soundfont-gm 3.1-6（https://deb.debian.org/debian/pool/main/f/fluid-soundfont/）の `FluidR3_GM.sf2`
- **このリポジトリには含めていない**。約148MB あり GitHub の1ファイルの上限を超えるため、`Scripts/fetch-soundfont.sh` で取得してアプリに同梱する（パッケージと SoundFont のハッシュを固定）
- ライセンス：MIT

```
Copyright (c) 2000-2002, 2008 Frank Wen <getfrank@gmail.com>
Copyright (c) 2008 Toby Smithe

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
```

## macOS 標準の音源（gs_instruments.dls）

- FluidR3_GM が無いときだけ、Mac で予備として使う。OS に入っているファイルを読むだけで、同梱・再配布はしない
