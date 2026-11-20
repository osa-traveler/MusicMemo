#!/bin/zsh
# Mac のデバッグビルドで画面を撮影する（開発用）。
# 使い方：Scripts/snapshot.sh 出力ファイル.png [倍率] [入力デモ 0/1/2/3/4/5/6] [曲の設定 0/1/2] [トラック 0/1/2] [セクション 0/1/2]
#   例：Scripts/snapshot.sh /tmp/main.png        … サンプル曲を 100% で
#       Scripts/snapshot.sh /tmp/zoom.png 2      … 200% で
#       Scripts/snapshot.sh /tmp/demo.png 1 1    … 入力デモを流してから
#       Scripts/snapshot.sh /tmp/sel.png 1 2     … 入力デモに続けて、音符の選択・移動・削除・範囲選択を流してから
#       Scripts/snapshot.sh /tmp/box.png 1 3     … 同じく、範囲選択の箱を出したところで
#       Scripts/snapshot.sh /tmp/set.png 1 0 1   … 曲の設定を開いて（ポップオーバーは /tmp/set-popover.png）
#       Scripts/snapshot.sh /tmp/set.png 1 0 2   … 曲の設定を変えてから（E♭ major へ移調、3/4、♩=96、小節数 +2）
#       Scripts/snapshot.sh /tmp/trk.png 1 0 0 1 … 先頭のトラックの設定を開いて
#       Scripts/snapshot.sh /tmp/trk.png 1 0 0 2 … トラックの追加・複製・設定の変更・並べ替え・削除をしてから
#       Scripts/snapshot.sh /tmp/sec.png 1 0 0 0 1 … 編集位置のセクションの名前と長さを開いて
#       Scripts/snapshot.sh /tmp/sec.png 1 0 0 0 2 … セクションの複製・追加・名前・長さ・分割をしてから
# ビルドは .build/DerivedData に置く（Xcode から実行しているアプリとは別物）。
# 撮影には画面収録の権限が要らない（アプリ自身がウィンドウを PNG に書き出す。App/Debug/DebugSnapshot.swift）。
set -euo pipefail

OUT="${1:?出力ファイルを指定してください}"
ZOOM="${2:-1}"
DEMO="${3:-0}"
SETTINGS="${4:-0}"
TRACKS="${5:-0}"
SECTIONS="${6:-0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/.build/DerivedData"
APP="$DERIVED/Build/Products/Debug/MusicMemo.app"

cd "$ROOT"
xcodegen generate >/dev/null
LOG=$(xcodebuild -project MusicMemo.xcodeproj -scheme MusicMemo -destination 'platform=macOS' -derivedDataPath "$DERIVED" build 2>&1)
echo "$LOG" | grep -E "error:|warning: |BUILD" | grep -v appintents | sort -u
echo "$LOG" | grep -q "BUILD SUCCEEDED" || exit 1

rm -f "$OUT" "${OUT%.*}-popover.png"
open -n --env MUSICMEMO_SNAPSHOT="$OUT" --env MUSICMEMO_ZOOM="$ZOOM" --env MUSICMEMO_INPUT_DEMO="$DEMO" --env MUSICMEMO_SETTINGS_DEMO="$SETTINGS" --env MUSICMEMO_TRACK_DEMO="$TRACKS" --env MUSICMEMO_SECTION_DEMO="$SECTIONS" \
  "$APP" --args -ApplePersistenceIgnoreState YES
for _ in $(seq 1 25); do [[ -f "$OUT" ]] && break; sleep 1; done
sleep 1
# 自分が起動したビルドだけを止める（Xcode から実行中のアプリには触らない）
pkill -f "$APP/Contents/MacOS/MusicMemo" 2>/dev/null || true
ls "$OUT"
