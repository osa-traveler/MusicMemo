#!/bin/zsh
# FluidR3_GM（SoundFont、MIT ライセンス）を取得して App/Resources/SoundFonts に置く。
# 約148MB あり GitHub の1ファイルの上限を超えるため、リポジトリには含めず、ここで取得する。
# 取得元：Debian の公式パッケージ fluid-soundfont-gm 3.1-6（パッケージと中身のハッシュを固定）
set -euo pipefail

PACKAGE_URL="https://deb.debian.org/debian/pool/main/f/fluid-soundfont/fluid-soundfont-gm_3.1-6_all.deb"
PACKAGE_SHA256=9965fbcc6acee17d6f72b685d28c7f968ec64eba14645445b476d5c6cc2eee4c
SF2_SHA256=74594e8f4250680adf590507a306655a299935343583256f3b722c48a1bc1cb0

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/App/Resources/SoundFonts/FluidR3_GM.sf2"

if [[ -f "$DEST" ]] && [[ "$(shasum -a 256 "$DEST" | cut -d' ' -f1)" == "$SF2_SHA256" ]]; then
  echo "取得済み: $DEST"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "取得中: $PACKAGE_URL"
curl -fsSL -o "$WORK/package.deb" "$PACKAGE_URL"
if [[ "$(shasum -a 256 "$WORK/package.deb" | cut -d' ' -f1)" != "$PACKAGE_SHA256" ]]; then
  echo "パッケージのハッシュが一致しません" >&2
  exit 1
fi

# .deb（ar 形式）から data.tar.xz を取り出し、その中の SF2 だけを展開する
(cd "$WORK" && ar -x package.deb data.tar.xz && tar -xf data.tar.xz ./usr/share/sounds/sf2/FluidR3_GM.sf2)
SF2="$WORK/usr/share/sounds/sf2/FluidR3_GM.sf2"
if [[ "$(shasum -a 256 "$SF2" | cut -d' ' -f1)" != "$SF2_SHA256" ]]; then
  echo "SoundFont のハッシュが一致しません" >&2
  exit 1
fi

mkdir -p "$(dirname "$DEST")"
mv "$SF2" "$DEST"
echo "配置しました: $DEST"
