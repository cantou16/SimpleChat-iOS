# SimpleChat for iOS

基于 [Pokanshuu/Simple-Chat](https://github.com/Pokanshuu/Simple-Chat)（MIT）的 iOS 原生移植（SwiftUI 重写）。

## v0.1.0 功能子集

- OpenAI 兼容 + Anthropic 兼容双协议，SSE 流式输出
- DeepSeek 风格思考链（reasoning_content / thinking_delta）折叠展示
- API Key 经 Keychain + AES-256-GCM 加密存储（对齐 Android 端 SecretBox）
- 多会话管理、JSON 落盘持久化、http 自建端点支持

## 与 Android 端的差距（刻意砍掉）

Markdown 富渲染、公式/Mermaid、附件/图片、导入导出、语音、朗读、多厂商预设 —— 见 `docs/`。

## 开发

Windows 写码 + GitHub Actions macOS 云构建：

- 推送到 `main` 自动跑：单测 → 模拟器启动截图 → 产出未签名 IPA（Actions Artifacts）
- 本地：`brew install xcodegen && cd ios && xcodegen generate && open SimpleChat.xcodeproj`

## 安装到 iPhone

产出的是未签名 IPA，用任意签名渠道（Sideloadly / 爱思 / 自有证书）签名后安装。
