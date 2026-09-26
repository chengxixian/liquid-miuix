# 快速开始

## 环境要求

| 项 | 版本 | 说明 |
|---|---|---|
| JDK | 17 | |
| Gradle | 9.4.1+ | miuix 0.9.4 要求 |
| AGP | 9.1.0+ | 本项目用 9.2.1 |
| Kotlin | 2.4.20 | |
| compileSdk | **37** | miuix 0.9.4 的 AAR 元数据强制要求 |
| minSdk | **33** | `miuix-blur` 硬编码 |

`compileSdk 37` 与 `minSdk 33` 都不是随便定的 —— 见文末「为什么版本这么激进」。

---

## 跑起来

```bash
git clone https://github.com/<you>/liquid-miuix.git
cd liquid-miuix
./gradlew :example:installDebug
```

`example` 模块是一个三页的最小示例，包含正确的采集层 + 悬浮玻璃底栏结构。

---

## 接入到已有项目

### 1. 复制源码（推荐）

`library` 是按「可直接拷进项目」写的 —— 没有自己的资源文件、没有复杂的构建配置。
把这三个目录复制到你项目的源码根下，改包名即可：

```
glass/    液态玻璃配方 + 底栏
theme/    主题、Monet 取色、设计令牌
ui/       通用组件
```

### 2. 或者作为模块依赖

```kotlin
// settings.gradle.kts
include(":liquid-miuix")
project(":liquid-miuix").projectDir = file("path/to/liquid-miuix/library")
```

```kotlin
// app/build.gradle.kts
implementation(project(":liquid-miuix"))
```

### 3. 依赖与 SDK 版本

```kotlin
android {
    compileSdk = 37
    defaultConfig { minSdk = 33 }
}

dependencies {
    api("top.yukonga.miuix.kmp:miuix-ui-android:0.9.4")
    api("top.yukonga.miuix.kmp:miuix-icons-android:0.9.4")
    api("io.github.kyant0:backdrop-android:2.0.1")
    api("com.materialkolor:material-kolor:4.1.1")
    api("androidx.compose.material3:material3:1.5.0-alpha22")
    api("androidx.compose.material:material-icons-extended:1.7.8")
}
```

### 4. 主题入口

```kotlin
setContent {
    LiquidTheme {
        AppShell()
    }
}
```

### 5. 目录结构

```
library/src/main/java/com/liquidmiuix/
├── glass/
│   ├── GlassSurface.kt         Modifier.liquidGlass / glassNavBar / AppBackground
│   │                           LocalGlassBackdrop / rememberGlassBackdrop
│   └── GlassNavBarContent.kt   悬浮玻璃底栏（滑块 + 拖动 + 形变）
├── theme/
│   └── LiquidTheme.kt          LiquidTheme / LiquidAccentColor
│                               LiquidRadii / LiquidSpacing / LiquidMotion
│                               LiquidTypography / LiquidShapes
└── ui/
    └── Components.kt           LiquidCard / LiquidListItem / LiquidInfoRow
                                LiquidPill / LiquidStatusBanner / LiquidProgress
                                LiquidEmptyState / Modifier.staggeredEntry
```

---

## 三个入口点

### `LiquidTheme`

```kotlin
@Composable
fun LiquidTheme(
    accentColor: LiquidAccentColor = LiquidAccentColor.Dynamic,  // 跟随壁纸
    darkTheme: Boolean? = null,                                  // null = 跟随系统
    content: @Composable () -> Unit,
)
```

它做三件事：
1. 建 `ThemeController`（miuix 的主题控制器，`MonetSystem` 走壁纸取色）；
2. 把 miuix 的 `Colors` **映射**成 Material3 `ColorScheme`
   —— 否则会出现「对话框是 Material 紫、页面是 MIUI 蓝」的割裂；
3. 设置状态栏 / 导航栏图标的明暗。

### `Modifier.liquidGlass`

通用玻璃修饰符。「挂空 Box、内容做兄弟」的约束见 [02-glass.md](02-glass.md)。

### `GlassNavBarContent`

悬浮底栏的内容层（图标 + 文字 + 可拖动的高亮滑块）。
它与玻璃底板必须是**兄弟**。

---

## 常见接入错误

| 现象 | 原因 |
|---|---|
| 启动闪退（黑屏约 1 秒） | 玻璃放在了采集层里面 → [04-troubleshooting.md](04-troubleshooting.md) |
| 玻璃看起来没效果 | 采集层缺背景 / 页面与卡片同色 / 内容没滚到玻璃下面 |
| 按下时超出栏体的部分被裁掉 | 玻璃挂在含子内容的 Box 上了 |
| `Unresolved reference 'tertiary'` | miuix `Colors` 没有这个属性 |

---

## 为什么版本这么激进

这不是随便选的，是 miuix 0.9.4 的硬要求：

- **compileSdk 37**：它的 AAR 元数据里写着 `minCompileSdk=37`，
  低于这个值 Gradle 直接拒绝；
- **AGP ≥ 9.1.0 / Gradle ≥ 9.4.1**：AGP 9 的版本要求；
- **minSdk 33**：`miuix-blur` 硬编码；
- **material3 必须落在 miuix 那条依赖链上**：见 [README](../README.md#两个版本陷阱)。
