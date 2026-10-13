#!/bin/zsh
# Mac のデバッグビルドで画面を撮影する（開発用）。
# 使い方：Scripts/snapshot.sh 出力ファイル.png [倍率] [入力デモ 0/1]
#   例：Scripts/snapshot.sh /tmp/main.png        … サンプル曲を 100% で
#       Scripts/snapshot.sh /tmp/zoom.png 2      … 200% で
#       Scripts/snapshot.sh /tmp/demo.png 1 1    … 入力デモを流してから
# ビルドは .build/DerivedData に置く（Xcode から実行しているアプリとは別物）。
# 撮影には画面収録の権限が要らない（アプリ自身がウィンドウを PNG に書き出す。App/Debug/DebugSnapshot.swift）。
set -euo pipefail

OUT="${1:?出力ファイルを指定してください}"
ZOOM="${2:-1}"
DEMO="${3:-0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/.build/DerivedData"
APP="$DERIVED/Build/Products/Debug/MusicMemo.app"

cd "$ROOT"
xcodegen generate >/dev/null
LOG=$(xcodebuild -project MusicMemo.xcodeproj -scheme MusicMemo -destination 'platform=macOS' -derivedDataPath "$DERIVED" build 2>&1)
echo "$LOG" | grep -E "error:|warning: |BUILD" | grep -v appintents | sort -u
echo "$LOG" | grep -q "BUILD SUCCEEDED" || exit 1

rm -f "$OUT"
open -n --env MUSICMEMO_SNAPSHOT="$OUT" --env MUSICMEMO_ZOOM="$ZOOM" --env MUSICMEMO_INPUT_DEMO="$DEMO" \
  "$APP" --args -ApplePersistenceIgnoreState YES
for _ in $(seq 1 25); do [[ -f "$OUT" ]] && break; sleep 1; done
sleep 1
# 自分が起動したビルドだけを止める（Xcode から実行中のアプリには触らない）
pkill -f "$APP/Contents/MacOS/MusicMemo" 2>/dev/null || true
ls "$OUT"
