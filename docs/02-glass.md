# 液态玻璃的实现与参数

这份文档解释 `library/.../glass/GlassSurface.kt` 里每一个数字是怎么来的。
**结论都有实测依据**，不是「看着差不多」。

---

## ⚠️ 先看这条：布局硬约束

不遵守这条会**启动闪退**，而且崩溃信息完全指不到真正的原因。

### 约束一：玻璃元素必须在采集层之外

`rememberLayerBackdrop()` 默认 `onDraw = drawContent()`。
如果把 `layerBackdrop` 加在**包含玻璃元素的祖先节点**上，
玻璃采样时会去录制一个**已经包含自己**的层 → 自引用 → 渲染树无限递归。

崩溃栈长这样（小米 25019PNF3C / Android 17 / HyperOS 实测）：

```
Fatal signal 11 (SIGSEGV), code 2 (SEGV_ACCERR) in tid (RenderThread)
Cause: stack pointer is not in a rw map; likely due to stack overflow.
512 total frames — 全部是 libhwui RenderNode::prepareTreeImpl
```

**正确写法**：

```kotlin
Box {
    Box(Modifier.layerBackdrop(backdrop)) {   // 采集层：只有背景 + 页面内容
        AppBackground()
        PageContent()
    }
    GlassBar(backdrop)                        // 玻璃在采集层之外
}
```

**错误写法**：

```kotlin
Box(Modifier.layerBackdrop(backdrop)) {       // ❌ 玻璃成了采集层的后代
    AppBackground()
    PageContent()
    GlassBar(backdrop)                        //    采样到的层包含它自己
}
```

> 注意采集层的**内容**里也不能有玻璃。比如把玻璃输入框画在页面 Composable
> 内部（而页面在采集层里）同样会崩 —— 它必须走一个「浮层插槽」提到采集层外面去。

### 约束二：玻璃修饰符只能挂在空 Box 上

库的绘制顺序是：

```
onDrawBehind
  → drawBackdropLayer(玻璃，含形状裁剪)     ← 子内容是在这一层的裁剪里画的
  → onDrawSurface
  → drawContent()
```

所以**内容层要做玻璃的兄弟**，否则超出栏体的子元素会被裁掉。
最典型的症状：底栏滑块按下时向外扩 4dp，那 4dp 会消失。

```kotlin
Box {
    Box(Modifier.matchParentSize().glassNavBar(backdrop, shape))   // ① 玻璃，空 Box
    BarContent()                                                   // ② 内容，兄弟
}
```

### 为什么采集层里必须同时有「背景」和「内容」

- **只有内容、没背景** → 空白处录到的是**透明**，糊透明还是透明。
  表现为：栏下那片区域等于「没被处理过的原始背景」，玻璃看起来什么都没干；
- **只有背景、没内容** → 糊一个纯色得到的还是同一个纯色。
  模糊是低通滤波，纯色的高频为零，糊前糊后是同一片平坦。

---

## 效果链

```kotlin
effects = {
    vibrancy()                               // ① 饱和度 ×1.5
    blur(blurRadius.toPx())                  // ② 毛玻璃
    if (refraction) {
        lens(                                // ③ 折射（纯位移的 RuntimeShader）
            refractionHeight = refractionHeight.toPx(),
            refractionAmount = refractionAmount.toPx(),
            depthEffect = true,
            chromaticAberration = dispersion,
        )
    }
}
```

库内部是 `RenderEffect.createChainEffect(prev, next)`，**按书写顺序执行**。

### ① vibrancy 必须最先

它反编译后就是 `colorControls(brightness = 0, contrast = 1, saturation = 1.5)`，
对应社区给 Apple 玻璃校准的 1.4× 饱和度。

**放在模糊后面的话，颜色已经被摊淡，再加饱和度只会得到灰。**

### ② 关于「折射被模糊吃掉」这个说法 —— 不成立

曾经认为 `blur` 放在 `lens` 前面会把背景糊平、令折射失效。
反编译着色器后确认**这个判断是错的**：

lens 编译成的 RuntimeShader 主函数核心是

```
refractedCoord = coord + d * grad
```

**纯位移**。位移不改变对比度，所以「背景是平的 ⇒ 折射看不见」与模糊无关。

`blur → lens` 恰恰是 Apple 的做法：先糊背景再掰弯它。
而色散彩边依旧锐利 —— 彩边是着色器把 RGB 三通道错位采样得到的，与输入糊不糊无关。

---

## 参数怎么调

### 模糊半径：5dp

Apple `Liquid Glass` `.regular` 档的社区等效值是 **24dp**（iOS 26 的 `.regular`
变体强制包含背景模糊）。但本项目刻意取得很小：

> **栏下方的正文要依稀可读**（起码能辨认出字是什么）。
> 24dp / 16dp 这种量级会把字彻底糊掉。

5dp 只剩一层很薄的磨砂。

### 折射强度：没有折射率标量

这套库**没有** `refractiveIndex` 这种参数，能调的只有三个：

| 参数 | 含义 |
|---|---|
| `refractionHeight` | 折射边带宽度。只有距边缘这么宽的一条带内才发生位移 |
| `refractionAmount` | 边缘处最大位移像素数 |
| `depthEffect` | 位移方向里额外叠加 `normalize(centeredCoord)`，即「气泡感」本体 |

### 经验规则：位移至少是模糊半径的 2 倍以上

曾经按「避免夸张气泡」把 `amount` 砍到 `height` 的 0.64 倍，结果**折射直接看不见了**。

原因不是 `amount/height` 这个比值，而是 **`refractionAmount` 与模糊半径的量级关系**：
blur 会把背景里的中频结构抹平。当位移量与模糊半径同量级时，
把一张已经糊开的图平移几十像素，肉眼几乎看不出差别（灰度在该尺度上已近似线性）。

实测数据：

| 位移 / 模糊 | 比值 | 结果 |
|---|---|---|
| 72px / 64px | 1.13 | 看不出折射 |
| 160px / 64px | 2.5 | 折射回来 |

**取 2.5 倍更稳。** 另外这个比值同时受「降低模糊度」帮助 —— 模糊变小，同样的位移更显眼。

本项目的取值：dock 模糊 5dp、位移 40dp（比值 8）；滑块模糊 4dp、位移 16dp（比值 4）。

### 色散（边缘虹彩）

库只提供**布尔**开关：打开即换用带色散的着色器，**强度写死在着色器里、没有幅度参数**。

所以「降低彩虹感」的唯一手段就是关掉它。
折射（`depthEffect`）与色散是两个独立的开关，**关掉色散不影响折射**。

---

## 玻璃自己的填充色

```kotlin
val GlassSurfaceTint = Color(0xFF6E7D96).copy(alpha = 0.03f)
```

**为什么必须有它**：折射是纯位移、模糊不改变平坦区域的平均色 ——
这两件事对「背后是一片纯色」都无能为力。
**只有玻璃自己的填充色才能让它在任何背景上都成立。**

**为什么是冷灰而不是白**：半透明白色压在浅色页面上得到的结果还是同一个浅色 —— 等于没加。
要「看得见」就必须与背景**有一点点色相/明度差**，但不能差太多 ——
太浓就不「干净透亮」了。3% 的冷灰只改变 6~8 个灰阶：有实体感、同时保持透亮。

---

## 磨砂颗粒

```kotlin
const val GlassGrainAlpha = 0.12f   // 96px 可平铺贴图
```

**为什么需要**：模糊是低通滤波，**它抹掉多少高频，就看得见多少变化**。
平坦背景的高频为零，模糊前后都是同一片平坦 ——
所以只靠 blur 的话，整条玻璃上唯一看得出被糊过的地方就是高频细节（文字、图标边缘）。

磨砂玻璃的「毛」本质是**表面微粗糙**，与背后有没有东西无关。

颗粒贴图的 alpha 与灰阶都是随机的：明暗颗粒成对出现、**平均色接近中性**，
所以它只带来「质感」，不会额外改变玻璃的整体明暗。

---

## 背景为什么必须比卡片暗一档

页面底色取 miuix 语义色 `surface`（深色 `#000` / 浅色 `#F7F7F7`），
卡片取 `surfaceContainer`（深色 `#242424` / 浅色纯白）。

若页面也铺纯白，**卡片与背景之间就是 0 个灰阶的差**，整屏退化成一张白纸；
而玻璃底栏做的是背景模糊 —— 模糊是低通滤波，「背后什么都没有」时它**数学上必然不可见**。

页面灰、卡片白之后，底栏下方就有了可被糊掉的真实结构（卡片边、分隔线、正文）。

---

## 底栏滑块：为什么是每帧手动积分

`GlassNavBarContent` 的滑块位置由一条二阶弹簧决定，**每帧手动积分**：

```kotlin
while (true) {
    val now = withFrameNanos { it }
    val dt = ...
    val target = if (dragging) fingerTarget else restingTarget
    v += (stiffness * (target - sliderLeft) - damping * v) * safeDt
    sliderLeft += v * safeDt
}
```

**为什么不用 `snapshotFlow` / `collectLatest` / `Animatable.animateTo`**：
那条异步链曾经**静默停摆**过 —— 滑块在 4 秒的拖动里从 289 走到 299 就冻结了，
不报错、只是不动；而且因为吸附判据用的是手指位置，
连「最后停在哪一格」这种测试都发现不了。

`withFrameNanos` + 显式积分是最笨的写法，但它**不可能**停止推进：
只要还有一帧画面，它就在算。

**阻尼分两段**，这是「不抽搐」的关键：

- 拖动中 ζ = 1.0（临界阻尼）：目标位是手指逐个事件写进来的、本身是阶梯状的，
  欠阻尼弹簧追这种目标会来回振荡，看起来就是抽搐；
- 松手后 ζ = 0.70：这时目标是固定的一格，欠阻尼才有那一下 Q 弹过冲。

两段之间速度是连续的（同一个 `springVelocity`），所以切换不会跳。

**为什么拖动只允许从滑块上起手**：整条栏都能拖的话，
用户想点 tab 却稍微一滑就会变成拖动，而且他根本不知道滑块是可以拖的。

**为什么位移一律从按下点起算**（而不是累加增量）：
系统 `touchSlop` 约 75px（≈19dp，是平台标准 8dp 的两倍多），
用增量的话那段 slop 距离会被永久丢掉，滑块从头到尾落后手指一个 slop 的量。
