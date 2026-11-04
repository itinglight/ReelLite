# 轻片 ReelLite · macOS 应用源码

项目介绍、功能说明和安装方法见仓库根目录的 [README](../README.md)。

## 开发

```bash
swift build                # 编译
swift run                  # 直接运行（无 .app 包，图标显示为默认）
./build_app.sh             # 打包成 build/轻片.app
./scripts/make_icon.sh     # 修改 scripts/make_icon.swift 后重新生成图标
```

## 代码结构

| 路径 | 内容 |
| --- | --- |
| `Sources/ReelLite/App.swift` | 应用入口、侧边栏、设置页、外部打开文件 |
| `Sources/ReelLite/Core/Shell.swift` | 查找 ffmpeg、运行子进程（支持取消、逐行读取输出） |
| `Sources/ReelLite/Core/FFmpeg.swift` | ffprobe JSON 解析、`-progress` 进度解析、兼容性规则 |
| `Sources/ReelLite/Features/` | 四个功能页面及对应的数据模型 |
| `Sources/ReelLite/UI/Components.swift` | 拖放区、参数说明行、名词解释、日志等通用组件 |

新增压缩方案只需在 `CompressView.swift` 的 `CompressPreset.all` 里加一项。
