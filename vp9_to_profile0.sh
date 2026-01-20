#!/bin/bash
set -e

TARGET="$1"

if [ -z "$TARGET" ]; then
  echo "用法:"
  echo "  ./vp9_to_profile0.sh video.webm"
  echo "  ./vp9_to_profile0.sh ./videos_dir"
  exit 1
fi

process_file() {
  FILE="$1"

  echo "▶ 检查: $(basename "$FILE")"

  CODEC=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name \
    -of default=nk=1:nw=1 "$FILE")

  PROFILE=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=profile \
    -of default=nk=1:nw=1 "$FILE")

  PIX_FMT=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=pix_fmt \
    -of default=nk=1:nw=1 "$FILE")

  if [[ "$CODEC" == "vp9" && ( "$PROFILE" != "Profile 0" || "$PIX_FMT" != "yuv420p" ) ]]; then
    OUT="${FILE%.webm}_p0.webm"

    echo "⚠ Safari 不兼容 → 重新编码"
    echo "   Codec   : $CODEC"
    echo "   Profile : $PROFILE"
    echo "   PixFmt  : $PIX_FMT"
    echo "   输出为  : $(basename "$OUT")"

    ffmpeg -y -i "$FILE" \
      -c:v libvpx-vp9 \
      -profile:v 0 \
      -pix_fmt yuv420p \
      -b:v 0 \
      -crf 30 \
      -row-mt 1 \
      -threads 8 \
      -an \
      "$OUT"

    echo "✅ 完成"
    echo ""
  else
    echo "✅ 已符合 Safari 要求，跳过"
    echo ""
  fi
}

echo ""

if [ -f "$TARGET" ]; then
  # 单文件
  if [[ "$TARGET" != *.webm ]]; then
    echo "❌ 仅支持 .webm 文件"
    exit 1
  fi
  process_file "$TARGET"

elif [ -d "$TARGET" ]; then
  # 文件夹
  echo "🔍 扫描目录: $TARGET"
  echo ""

  shopt -s nullglob
  for FILE in "$TARGET"/*.webm; do
    process_file "$FILE"
  done
  shopt -u nullglob

else
  echo "❌ 找不到文件或目录: $TARGET"
  exit 1
fi

echo "🎉 处理完成"

