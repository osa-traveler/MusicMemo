#!/bin/zsh
# GeneralUser GS（SoundFont）を取得して App/Resources/SoundFonts に置く。
# 出所が完全には確認できないサンプルを含む旨がライセンスにあるため、リポジトリには含めず、ここで取得する。
# 取得元：https://github.com/mrbumpy409/GeneralUser-GS（v2.0.3、コミットとハッシュを固定）
set -euo pipefail

COMMIT=97049183643d5fc5a9322a69c5b09efb667c6c3a
SHA256=9575028c7a1f589f5770fccc8cff2734566af40cd26ed836944e9a5152688cfe
URL="https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/${COMMIT}/GeneralUser-GS.sf2"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/App/Resources/SoundFonts/GeneralUser-GS.sf2"

if [[ -f "$DEST" ]] && [[ "$(shasum -a 256 "$DEST" | cut -d' ' -f1)" == "$SHA256" ]]; then
  echo "取得済み: $DEST"
  exit 0
fi

mkdir -p "$(dirname "$DEST")"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
echo "取得中: $URL"
curl -fsSL -o "$TMP" "$URL"

ACTUAL="$(shasum -a 256 "$TMP" | cut -d' ' -f1)"
if [[ "$ACTUAL" != "$SHA256" ]]; then
  echo "ハッシュが一致しません（期待 $SHA256 / 実際 $ACTUAL）" >&2
  exit 1
fi
mv "$TMP" "$DEST"
trap - EXIT
echo "配置しました: $DEST"
