#!/bin/bash

FILE="$1"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "用法: ./scripts/video_inspect.sh video_file"
  exit 1
fi

# ---------- 基础信息 ----------
CODEC=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name \
  -of default=nk=1:nw=1 "$FILE")

CODEC_LONG=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_long_name \
  -of default=nk=1:nw=1 "$FILE")

PROFILE=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=profile \
  -of default=nk=1:nw=1 "$FILE")

WIDTH=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width \
  -of default=nk=1:nw=1 "$FILE")

HEIGHT=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=height \
  -of default=nk=1:nw=1 "$FILE")

FPS=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=avg_frame_rate \
  -of default=nk=1:nw=1 "$FILE")

BITRATE=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=bit_rate \
  -of default=nk=1:nw=1 "$FILE")

SIZE_BYTES=$(stat -f%z "$FILE")
SIZE_MB=$(echo "scale=2; $SIZE_BYTES/1024/1024" | bc)

# ---------- 码率处理 ----------
if [ "$BITRATE" = "N/A" ] || [ -z "$BITRATE" ]; then
  BITRATE_TXT="N/A"
else
  BITRATE_TXT="$(echo "$BITRATE/1000" | bc) kbps"
fi

# ---------- 兼容性评分 ----------
CHROME_SCORE=0
SAFARI_SCORE=0
REMARK=""

if [[ "$CODEC" == "av1" ]]; then
  CHROME_SCORE=5
  SAFARI_SCORE=4
  REMARK="AV1 高效编码"
elif [[ "$CODEC" == "vp9" ]]; then
  CHROME_SCORE=5
  if [[ "$PROFILE" == "Profile 0" ]]; then
    SAFARI_SCORE=5
    REMARK="Safari 完美支持"
  else
    SAFARI_SCORE=1
    REMARK="Safari 不兼容 (Profile 问题)"
  fi
elif [[ "$CODEC" == "h264" ]]; then
  CHROME_SCORE=5
  SAFARI_SCORE=5
  REMARK="通用保命编码"
else
  REMARK="未知编码"
fi

# ---------- 输出 ----------
echo ""
echo "🎬 视频体检报告"
echo "------------------------------------------------------------"
printf "%-16s : %s\n" "文件名" "$(basename "$FILE")"
printf "%-16s : %s (%s)\n" "编码" "$CODEC" "$CODEC_LONG"
printf "%-16s : %s\n" "Profile" "$PROFILE"
printf "%-16s : %sx%s\n" "分辨率" "$WIDTH" "$HEIGHT"
printf "%-16s : %s\n" "帧率" "$FPS"
printf "%-16s : %s\n" "码率" "$BITRATE_TXT"
printf "%-16s : %.2f MB\n" "视频体积" "$SIZE_MB"
echo "------------------------------------------------------------"
printf "%-16s : %d / 5\n" "Chrome 兼容性" "$CHROME_SCORE"
printf "%-16s : %d / 5\n" "Safari 兼容性" "$SAFARI_SCORE"
printf "%-16s : %s\n" "综合评价" "$REMARK"
echo "------------------------------------------------------------"

