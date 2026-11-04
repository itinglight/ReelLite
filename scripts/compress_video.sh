#!/bin/bash

# 函数：居中输出
center() {
  str="$1"
  width="$2"
  len=${#str}
  if [ $len -ge $width ]; then
    printf "%s" "$str"
  else
    pad=$(( (width - len)/2 ))
    printf "%*s%s%*s" $pad "" "$str" $((width - len - pad)) ""
  fi
}

# 输入文件
INPUT="$1"
if [ -z "$INPUT" ]; then
  echo "用法: ./scripts/compress_video.sh input_file"
  exit 1
fi

# 输出文件夹
OUTPUT_DIR="compressed_videos"
mkdir -p "$OUTPUT_DIR"

# 文件名基础
BASENAME=$(basename "$INPUT")
NAME="${BASENAME%.*}"

# 原视频大小
ORIG_SIZE=$(stat -f%z "$INPUT")
ORIG_SIZE_KB=$((ORIG_SIZE/1024))

# 视频帧率
FPS=$(ffprobe -v 0 -of csv=p=0 -select_streams v:0 -show_entries stream=r_frame_rate "$INPUT")
FPS_INT=$(echo "$FPS" | bc)

echo "开始压缩: $INPUT"
echo "检测到源帧率: $FPS (~$FPS_INT fps)"
echo "原始视频大小: ${ORIG_SIZE_KB} KB"

# -------------------------------
# 压缩命令
# -------------------------------
OUTPUT1="${OUTPUT_DIR}/${NAME}_1080p_vp8.webm"
ffmpeg -y -i "$INPUT" -an -c:v libvpx -crf 10 -b:v 0 -deadline good -cpu-used 1 \
-vf "scale='min(1920,iw)':'-2',fps=$FPS_INT" "$OUTPUT1"

OUTPUT2="${OUTPUT_DIR}/${NAME}_720p_vp9.webm"
ffmpeg -y -i "$INPUT" -an -c:v libvpx-vp9 -crf 33 -b:v 0 -row-mt 1 -tile-columns 2 -frame-parallel 1 \
-vf "scale='min(1280,iw)':'-2',fps=$FPS_INT" "$OUTPUT2"

OUTPUT3="${OUTPUT_DIR}/${NAME}_1080p_vp9_hq.webm"
ffmpeg -y -i "$INPUT" -an -c:v libvpx-vp9 -crf 25 -b:v 0 -row-mt 1 -tile-columns 2 -frame-parallel 1 \
-vf "scale='1920:-2',fps=$FPS_INT" "$OUTPUT3"

OUTPUT4="${OUTPUT_DIR}/${NAME}_1080p_av1_hq.mp4"
ffmpeg -y -i "$INPUT" -an -c:v libaom-av1 -crf 36 -b:v 0 -cpu-used 6 \
-vf "scale='1920:-2',fps=$FPS_INT" "$OUTPUT4"

OUTPUT5="${OUTPUT_DIR}/${NAME}_1080p_av1.mp4"
ffmpeg -y -i "$INPUT" -an -c:v libaom-av1 -crf 38 -b:v 0 -cpu-used 6 \
-vf "scale='1920:-2',fps=$FPS_INT" "$OUTPUT5"

OUTPUT6="${OUTPUT_DIR}/${NAME}_720p_av1.mp4"
ffmpeg -y -i "$INPUT" -an -c:v libaom-av1 -crf 38 -b:v 0 -cpu-used 6 \
-vf "scale='1280:-2',fps=$FPS_INT" "$OUTPUT6"

# -------------------------------
# 居中表格输出
# -------------------------------
echo ""
echo "压缩完成，视频体积 & 压缩比表格（按体积排序）"

# 列宽
W1=35
W2=10
W3=10
W4=12
W5=15

# 表头
printf "%s | %s | %s | %s | %s\n" \
"$(center "文件名" $W1)" \
"$(center "大小" $W2)" \
"$(center "压缩比" $W3)" \
"$(center "占原体积" $W4)" \
"$(center "原视频大小" $W5)"

# 分隔线
printf '%*s\n' $((W1+W2+W3+W4+W5+12)) '' | tr ' ' '-'

# 输出数据并排序
for FILE in "$OUTPUT1" "$OUTPUT2" "$OUTPUT3" "$OUTPUT4" "$OUTPUT5" "$OUTPUT6"; do
  SIZE=$(stat -f%z "$FILE")
  SIZE_KB=$((SIZE/1024))
  RATIO=$(echo "scale=2; $ORIG_SIZE/$SIZE" | bc)
  PERCENT=$(echo "scale=1; $SIZE*100/$ORIG_SIZE" | bc)
  FILENAME=$(basename "$FILE")
  printf "%s | %s | %s | %s | %s\n" \
  "$(center "$FILENAME" $W1)" \
  "$(center "${SIZE_KB}KB" $W2)" \
  "$(center "${RATIO}x" $W3)" \
  "$(center "${PERCENT}%" $W4)" \
  "$(center "${ORIG_SIZE_KB}KB" $W5)"
done | sort -k2 -h
