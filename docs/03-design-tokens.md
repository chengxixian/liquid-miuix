# 设计令牌

取值对齐 miuix 自身的字号/色板尺度，
并已在本项目真机验证。**新代码一律引用常量，不写字面量 dp** ——
之前各处散落 10/12/14/15/16/18/20 这类随手值，是整体协调度差的主要来源。

---

## 圆角

```kotlin
object LiquidRadii {
    val small      = 12.dp
    val medium     = 16.dp
    val large      = 24.dp
    val extraLarge = 32.dp
}
```

同一套数值喂给 Material3 的 `Shapes`，保证两套组件库的圆角一致。

**胶囊用 `RoundedCornerShape(50)` 而不是固定 dp。**
固定 dp 只有在「圆角 ≥ 高度一半」时才是胶囊：
16dp / 28dp 都小于 64dp 栏高的一半（32dp），看起来是「很圆的矩形」
而不是 App Store 那种**两端半圆的胶囊**。百分比写法与高度解耦，永远正确。

---

## 间距

```kotlin
object LiquidSpacing {
    val tight  = 4.dp     // 紧邻元素，如图标与其文字标签
    val inline = 8.dp     // 行内元素间距
    val item   = 12.dp    // 相关内容块之间（列表项之间用 14dp）
    val card   = 16.dp    // 卡片内部留白
    val page   = 20.dp    // 页面左右安全边距
}
```

命名按**用途**而非数值，这样以后调整尺度只需改这一处。

列表项内部：`Row(horizontalArrangement = spacedBy(13.dp))`，leading 图标 24dp。

---

## 排版

```kotlin
displaySmall   38.sp  Light       // 大数字、空态标题
headlineLarge  32.sp  Normal
headlineSmall  25.sp  Normal
titleLarge     21.sp  Medium
titleMedium    17.sp  Medium      // 卡片标题
titleSmall     15.sp  Medium      // 列表项标题
bodyLarge      16.sp  Normal
bodyMedium     14.sp / 21.sp  Normal   // 正文
bodySmall      12.sp / 18.sp  Normal   // 脚注
```

miuix 自己的语义名与之对应：
`headline2` ≈ 大标题、`title2` ≈ 卡片标题、`title4` ≈ 列表项标题、
`body2` = 正文、`footnote1` = 脚注。

**统一走 `MiuixTheme.textStyles.*`**，不要自己拼 `TextStyle` ——
否则 miuix 组件与手写文本的字号会不知不觉分叉。

---

## 动效

**核心原则：一律用低刚度弹簧，不用线性 tween。**
低刚度让动画有「跟手 + 回弹」的尾韵，`MediumBouncy` 提供一次可感知的过冲 ——
这就是那种「Q 弹」手感的来源。

```kotlin
object LiquidMotion {
    fun <T> bouncy()  = spring<T>(DampingRatioMediumBouncy, StiffnessLow)    // 主交互
    fun <T> gentle()  = spring<T>(DampingRatioLowBouncy,    StiffnessVeryLow) // 大幅位移
    fun <T> snappy()  = spring<T>(DampingRatioNoBouncy,     StiffnessMediumLow)// 淡入淡出
    fun <T> press()   = spring<T>(DampingRatioMediumBouncy, StiffnessMedium)  // 按压

    const val StaggerMillis = 40L
    const val PressedScale  = 0.96f
    const val FloatingBarPressedScale = 1.04f
}
```

**用泛型函数而不是共享 `val`**：`SpringSpec<T>` 的目标类型要由调用处推断，
写成 `val bouncy = spring<Float>(...)` 会让 `Dp` / `Color` / `Offset` 的动画
无法复用同一个令牌。

### 页面切换

方向感知的层叠推入，位移只走 **1/4 屏**：

```kotlin
val forward = targetState.ordinal > initialState.ordinal
val enterOffset: (Int) -> Int = { if (forward) it / 4 else -it / 4 }
(fadeIn(snappy()) + slideInHorizontally(gentle(), enterOffset))
    .togetherWith(fadeOut(snappy()) + slideOutHorizontally(snappy(), exitOffset))
```

全屏滑动会让两页在采集层里大面积交叠，**模糊条带跟着内容乱跑**。

### 列表错峰入场

```kotlin
Modifier.staggeredEntry(index)   // delay = index * 40ms，上限 8 项
```

上限 8 项是必要的：否则列表越长、靠后的项等待越久（第 30 项要等 1.2s）。

---

## 按压反馈：放大，不是按瘪

两条玻璃栏按下的方向都是**放大**：

```kotlin
// 整条 dock：1.04×
val barScale by animateFloatAsState(
    targetValue = if (pressed) 1.04f else 1f,
    animationSpec = LiquidMotion.press(),
)
```

底栏与内部的滑块**一起被放大**，滑块自己再乘一个更大的比例。
两者在修饰符链上是父子关系，比例天然相乘。

**取值要克制**：底栏四周只有 16dp 留白，放大超过 1.06 就会把留白吃得差不多、
看起来像贴住了屏幕边缘。

**缩放做在 `graphicsLayer` 上**（纯绘制），命中区仍是原来的整条栏。

**文字本身不做缩放** —— 缩放会导致重绘糊字。

---

## 颜色：只用语义色

**不写死十六进制。** 一律取 `MiuixTheme.colorScheme.*`：

| 用途 | 取色 |
|---|---|
| 页面底色 | `surface` |
| 卡片 | `surfaceContainer` |
| 卡片按下 / 浮起 | `surfaceContainerHigh` |
| 正文 | `onSurface` |
| 次要文字 / 说明 | `onSurfaceVariantSummary` |
| 强调 / 选中态 | `primary` |
| 分组容器 | `surfaceVariant` |

配合 `paletteStyle = Neutral`，`surface` 系保持中性不被强调色染色，
主色只作用于 `primary` 系 —— 这样「换主题色 = 换按钮颜色」，页面底色始终干净。

### 注意 miuix `Colors` 没有的属性

| 你可能想用 | miuix 实际叫 |
|---|---|
| `tertiary` | 只有 `tertiaryContainer` |
| `outlineVariant` | `dividerLine` |
| `onSurfaceVariant` | `onSurfaceVariantSummary` / `onSurfaceVariantActions` |

写之前先确认属性存在，否则是编译错误（比运行时才发现好）。

---

## 卡片：靠底色差分层，不用阴影

```kotlin
// 页面 surface（深色 #000 / 浅色 #F7F7F7）
// 卡片 surfaceContainer（深色 #242424 / 浅色纯白）
```

两者天然差一档，靠「圆角 + 底色差」分层即可。
**加阴影反而会破坏 MIUI / Hyperion 那种扁平的干净感。**

这同时是玻璃能生效的前提 —— 见 [02-glass.md](02-glass.md) 最后一节。
