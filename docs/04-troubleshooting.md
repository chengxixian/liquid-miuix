# 排查手册

按症状查。

---

## 启动闪退：渲染树栈溢出

### 症状

点开图标 → 黑屏约 1 秒 → 退回桌面。

`adb logcat -b crash` 里是：

```
Fatal signal 11 (SIGSEGV), code 2 (SEGV_ACCERR), fault addr 0x... in tid ... (RenderThread)
Cause: stack pointer is not in a rw map; likely due to stack overflow.
512 total frames
```

`512 total frames` 全是这种重复：

```
libhwui.so (android::uirenderer::RenderNode::prepareTreeImpl(...))
libhwui.so (android::uirenderer::skiapipeline::SkiaDisplayList::prepareListAndChildren(...))
libhwui.so (android::uirenderer::RenderNode::prepareTreeImpl(...))
...
```

### 原因

**`layerBackdrop` 被加在了包含玻璃元素的祖先节点上。**

`rememberLayerBackdrop()` 默认 `onDraw = drawContent()`。
采集层录制时会把**它子树里的所有东西**（包括玻璃）录进去；
而玻璃采样时又要去读这个层 —— 于是层包含玻璃、玻璃又依赖层，无限递归。

### 排查步骤

1. **打一张 UI 树**，找出所有 `layerBackdrop` 出现的位置：

   ```bash
   grep -rn "layerBackdrop" app/src/main/java
   ```

   正常情况下**只应该有一处** —— 就是那个「背景 + 页面内容」的 Box。

2. **确认玻璃元素都在那一处的子树之外。** 常见的漏网之鱼：
   - 玻璃输入框写在了页面 Composable 内部（页面在采集层里）→
     必须提到采集层外面，用「浮层插槽」透传 `backdrop`；
   - 玻璃顶栏放在了 `Scaffold` 的 `content` 里面 →
     应该放进 `topBar`，或者放在采集层的兄弟位置。

3. **单变量验证**：把玻璃全部关掉（`Modifier.glassNavBar(backdrop = null)`，
   它会走不透明 fallback 分支），只留采集层。
   还崩 → 问题不在玻璃；不崩 → 就是自引用。

### 修复

```kotlin
// ❌ 错
Box(Modifier.layerBackdrop(backdrop)) {
    AppBackground()
    Content()
    GlassBar(backdrop)
}

// ✅ 对
Box {
    Box(Modifier.layerBackdrop(backdrop)) {
        AppBackground()
        Content()
    }
    GlassBar(backdrop)
}
```

需要注意 `Scaffold` 的 `padding`：
玻璃栏要用 `Modifier.padding(padding)` 才能避开系统栏，
但**不能**把它放进 `content` 里 —— 那就在采集层内了。

---

## 玻璃「看起来什么都没干」

玻璃是半透明白 + 有描边，但背景滚动过去时它**完全不变**。

按可能性排序：

### 1. 采集层里没有背景，只有内容

空白处录到的是**透明**。糊透明还是透明。
→ 采集层里必须同时放 `AppBackground()`。

### 2. 页面底色和卡片同色

模糊是低通滤波：**背后什么都没有时它数学上必然不可见**。
页面铺纯白、卡片也是纯白 → 两者之间 0 个灰阶的差，没有可被糊掉的结构。
→ 页面用 `surface`、卡片用 `surfaceContainer`，差一档。

### 3. 内容没滚到玻璃下面

如果给列表留了「底栏高度」的底部 padding，列表永远滚不到玻璃下方，
玻璃背后永远是空白。
→ 内容**不该**为底栏预留高度（只留一点余量避免最后一项被永久盖住）。
这正是「浮在内容之上」的意义。

### 4. 折射位移太小

如果位移与模糊半径同量级，肉眼看不出差别。
→ **位移至少要是模糊半径的 2 倍以上**，2.5 倍更稳。
见 [02-glass.md](02-glass.md)。

### 5. 没有自己的填充色

折射是纯位移、模糊不改变平坦区平均色 —— 这两件事对纯色背景都无能为力。
→ 加 `GlassSurfaceTint`（3% 冷灰）。

---

## 玻璃栏下面的文字发灰 / 顶栏透出内容

**顶栏必须不透明。** 只要给它一点透明度，下方滚动的文字就会渗上来变成灰蒙蒙的一片。

```kotlin
SmallTopAppBar(
    modifier = Modifier.background(MiuixTheme.colorScheme.surfaceContainer),
    color = Color.Transparent,     // 让上面的 background 生效，而不是再加一层半透明
)
```

玻璃感留给**底栏** —— 那里有折射，效果才明显。

---

## 按下时滑块「超出底栏的部分不显示」

玻璃修饰符挂错了地方 —— 它被挂在了**包含内容**的 Box 上。

库的绘制顺序是
`onDrawBehind → drawBackdropLayer(玻璃，含形状裁剪) → onDrawSurface → drawContent()`，
**子内容是在玻璃那一层的裁剪里画的**。

→ 玻璃必须挂在一个**不含子内容**的 Box 上，内容层做它的**兄弟**。

---

## 编译错误

### `The 'org.jetbrains.kotlin.android' plugin is no longer required...`

AGP 9 起已内置 Kotlin 支持。从 `plugins {}` 里删掉 `org.jetbrains.kotlin.android`，
只留 `com.android.application` / `com.android.library` + `org.jetbrains.kotlin.plugin.compose`。

### `Cannot access 'MaterialExpressiveTheme': it is internal`

`MaterialExpressiveTheme` 与 `MotionScheme.expressive()` 在 material3 稳定版里仍是 internal。

**但更可能的情况是你被依赖调解骗了** —— 先看实际解析到哪个版本：

```bash
./gradlew :app:dependencies --configuration debugRuntimeClasspath | grep material3
```

如果显示 `material3:1.3.1 -> 1.5.0-alpha22`，说明 miuix 已经把它提上去了，
你声明 stable 也会被改写成 alpha。**声明必须落在 miuix 那条链上。**

### `Unresolved reference 'tertiary'` / `'outlineVariant'`

miuix 的 `Colors` 没有这两个属性。对应的是 `tertiaryContainer` 与 `dividerLine`。
见 [03-design-tokens.md](03-design-tokens.md) 最后一节。

### `Cannot access class 'com.kyant.backdrop...LayerBackdrop'`

`backdrop` 是 `implementation` 依赖，不传递给调用方。
如果你在另一个模块里写玻璃代码，把它改成 `api`。

---

## 装了新版但界面没变 / `Activity class does not exist`

**先确认安装真的成功了。** `adb install` 有两种静默失败，都会让应用"看起来崩溃了"：

```
INSTALL_FAILED_USER_RESTRICTED: Install canceled by user
```
小米需要打开「开发者选项 → 通过 USB 安装」，否则系统直接拒绝。

```
INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match
```
debug 包和 release 包签名不同（一个用 debug keystore、一个用你的 keystore）。
先卸载再装。

**判断崩溃不要只看进程在不在**（`pidof`）。安装失败时进程本来就不存在，
看起来和崩溃一模一样。**要看 `adb logcat -b crash` 的实际内容。**

---

## 底栏贴着系统导航栏 / 浮得太高

`Scaffold` 给的 `padding` 已经包含系统栏 inset，
底栏再往上留 `16.dp` 通常就够了（3 键导航约 48dp）。

如果还是贴得太紧或浮得太夸张，加一个可调的额外偏移，别去改 `padding`：

```kotlin
private val BarBottomInset = 14.dp   // 按机型微调

.padding(bottom = BarMargin + BarBottomInset)
```

参考实现里底栏图标中心距屏幕底约 55dp；本机 3 键导航下 `BarBottomInset = 14.dp` 时目视一致。
