# Aikin录音 · iOS

原生 SwiftUI 应用，面向 iOS 26 及以上版本，可在 iOS 27 使用。使用 Apple SpeechAnalyzer / SpeechTranscriber 做本地实时转写与文件转写，不复用 Android SDK、第三方服务密钥或会员授权。

## 功能

- 黑色文件库，每条录音使用灰色细边框；无登录、广告、商城、云存储。
- 录音 / 导入操作使用原生 Liquid Glass。系统控件尊重动态字体、减少动态效果和系统辅助功能。
- 录制 M4A 音频，暂停、继续，接听电话等系统中断时保存。
- 默认标题 `Aikin会议录音_2026年10月17日15时32分`，使用上海时区；音频用 UUID 存储，避免同一分钟录音相互覆盖。分享时恢复可读文件名。
- Apple 本地语音模型：普通话、英语、粤语（以设备实际支持的语言为准）。首次使用可能需要联网下载语言模型；不上传至自建或第三方转写服务。
- 从系统“文件”选择音频，播放与前后跳转、文字编辑、重命名、分享音频和导出 TXT。
- 本地 JSON 索引采用原子写入；异常退出后找回仍保存在目录中的音频。

录音不依赖转写成功：模型准备失败时提示错误，继续保存音频，之后可在详情页重试转写。iOS 应用沙盒中的录音不会自动迁移自 Android；请在 Android 导出后通过系统文件导入。

## GitHub Actions 构建

推送 `main`，或在 **Actions → Build iOS unsigned IPA → Run workflow** 手动触发。

工作流在 GitHub macOS 26 环境中，用 Xcode 编译 arm64 真机应用、检查无签名状态、打包 `AikinRecorder-unsigned.ipa`，再运行模拟器单元测试并截图。下载该次运行的 **Artifacts → AikinRecorder-iOS-运行编号**。

制品包括：未签名 IPA、SHA256、编译日志、测试结果与模拟器首页截图。构建不需要 Apple 账号、证书或 GitHub Secrets。未签名 IPA 不能直接安装；请在你自己的签名工具中使用证书及匹配设备/分发类型的描述文件签名。签名时保留麦克风权限说明和 `audio` 后台模式。

## 在 Mac 上构建

安装包含 iOS 26 SDK 或更新 SDK 的 Xcode 后，在仓库目录运行：

```bash
python3 scripts/generate_project.py
open AikinRecorder.xcodeproj
# 或生成未签名 IPA
bash scripts/build_unsigned.sh
```

无 CocoaPods、SPM 或 Homebrew 依赖。Xcode 工程由标准库 Python 脚本生成，仓库同时保存生成后的工程。默认 Bundle ID 为 `app.aikin.recorder`，可按自己的签名配置修改。

## 验证范围

自动测试覆盖命名时区、导出文件名清理、时长显示、本地索引持久化、文字导出和异常录音恢复。模拟器编译不能验证真实麦克风、耳机路由、后台录音或 Apple 模型下载/识别效果，这些需要签名后在 iPhone 实测。

## 字体与资源

Special Elite 来自 Google Fonts，按附带 Apache 2.0 许可分发。字体只用于应用图标和首页操作按钮中的英文副标题；其余文字采用系统字体。图标为黑底白色 A。应用不收集分析数据、不集成广告 SDK。
