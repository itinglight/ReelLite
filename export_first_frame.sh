#!/bin/bash

INPUT="$1"
if [ -z "$INPUT" ]; then
  echo "用法: ./export_first_frame.sh video_file"
  exit 1
fi

NAME="${INPUT%.*}"

JPG="${NAME}_first_frame.jpg"
WEBP="${NAME}_first_frame.webp"

# ---------- JPG ----------
ffmpeg -y -ss 0.1 -i "$INPUT" \
  -vframes 1 \
  -q:v 2 \
  "$JPG"

# ---------- 静态 WebP（关键参数） ----------
ffmpeg -y -ss 0.1 -i "$INPUT" \
  -vframes 1 \
  -update 1 \
  -c:v libwebp \
  -quality 90 \
  "$WEBP"

# ---------- 文件体积 ----------
JPG_SIZE=$(stat -f%z "$JPG")
WEBP_SIZE=$(stat -f%z "$WEBP")

JPG_KB=$((JPG_SIZE / 1024))
WEBP_KB=$((WEBP_SIZE / 1024))

echo ""
echo "首帧图片导出完成（确认：WebP 为静态）："
printf "%-12s | %-30s | %10s\n" "格式" "文件名" "体积"
printf '%.0s-' {1..60}; echo
printf "%-12s | %-30s | %8s KB\n" "JPG"  "$(basename "$JPG")"  "$JPG_KB"
printf "%-12s | %-30s | %8s KB\n" "WebP" "$(basename "$WEBP")" "$WEBP_KB"
