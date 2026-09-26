package com.liquidmiuix.example

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.dp
import com.kyant.backdrop.backdrops.layerBackdrop
import com.liquidmiuix.glass.AppBackground
import com.liquidmiuix.glass.glassNavBar
import com.liquidmiuix.glass.GlassNavBarContent
import com.liquidmiuix.glass.LocalGlassBackdrop
import com.liquidmiuix.glass.rememberGlassBackdrop
import com.liquidmiuix.theme.LiquidMotion
import com.liquidmiuix.theme.LiquidSpacing
import com.liquidmiuix.theme.LiquidTheme
import com.liquidmiuix.ui.LiquidCard
import com.liquidmiuix.ui.LiquidListItem
import top.yukonga.miuix.kmp.basic.SmallTopAppBar
import top.yukonga.miuix.kmp.theme.MiuixTheme

/**
 * 示例 Activity。
 *
 * 重点看 [AppShell] 的结构 —— **这是整套方案里唯一不能改的部分**，
 * 放错一层就会启动闪退（详见 docs/02-glass.md）。
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            LiquidTheme {
                AppShell()
            }
        }
    }
}

private enum class Page(val title: String, val icon: ImageVector) {
    Home("首页", Icons.Rounded.Home),
    Star("收藏", Icons.Rounded.Star),
    Settings("设置", Icons.Rounded.Settings),
}

private val BarMargin = 16.dp
private val BarHeight = 64.dp
private val BarPressedScale = 1.04f

/**
 * 悬浮玻璃底栏 + 采集层的**正确结构**。
 *
 * ```
 * Box(fillMaxSize)
 *   └ CompositionLocalProvider(LocalGlassBackdrop provides backdrop)
 *       └ Scaffold(containerColor = 透明)
 *           ├ topBar: SmallTopAppBar          ← 在采集层之外
 *           └ content:
 *               Box(fillMaxSize)
 *                 ├ Box(layerBackdrop)        ← 采集层：背景 + 全部页面内容
 *                 │    AppBackground()
 *                 │    AnimatedContent { 页面 }
 *                 └ Box(padding)              ← 悬浮底栏，在采集层之外
 *                      └ Box(BottomCenter)
 *                          ① Box(glassNavBar)     ← 玻璃底板，**不含子内容**
 *                          ② GlassNavBarContent   ← 与玻璃是**兄弟**
 * ```
 *
 * ## ⚠️ 两条硬约束
 *
 * 1. **玻璃元素必须在采集层之外**。`rememberLayerBackdrop()` 默认
 *    `onDraw = drawContent()`；把 `layerBackdrop` 加在包含玻璃的祖先节点上，
 *    玻璃采样时会去录制一个已经包含自己的层 → 自引用 → 渲染树无限递归。
 *    实测崩溃栈：`Fatal signal 11 (SIGSEGV) in RenderThread` /
 *    `Cause: stack pointer is not in a rw map; likely due to stack overflow.` /
 *    `512 total frames` 全在 `libhwui RenderNode::prepareTreeImpl`。
 *
 * 2. **玻璃修饰符只能挂在空 Box 上**。库的绘制顺序是
 *    `onDrawBehind → drawBackdropLayer(玻璃，含形状裁剪) → onDrawSurface → drawContent()`，
 *    子内容是在玻璃那层的裁剪里画的。所以内容层要做玻璃的**兄弟**，
 *    否则超出栏体的子元素（比如按下时外扩的滑块）会被裁掉。
 *
 * ## 为什么采集层里必须同时有背景和内容
 *
 * - 只有内容、没背景 → 空白处录到的是**透明**，糊透明还是透明；
 * - 只有背景、没内容 → 糊一个纯色得到的还是同一个纯色（模糊是低通滤波，纯色高频为零）。
 */
@Composable
private fun AppShell() {
    var page by remember { mutableStateOf(Page.Home) }
    val backdrop = rememberGlassBackdrop()

    var barPressed by remember { mutableStateOf(false) }
    val barScale by animateFloatAsState(
        targetValue = if (barPressed) BarPressedScale else 1f,
        animationSpec = LiquidMotion.press(),
        label = "barScale",
    )

    Box(Modifier.fillMaxSize()) {
        CompositionLocalProvider(LocalGlassBackdrop provides backdrop) {
            Scaffold(
                // 背景由采集层画；Scaffold 不能再铺不透明底，否则会盖住采集层
                containerColor = Color.Transparent,
                topBar = {
                    SmallTopAppBar(
                        title = page.title,
                        modifier = Modifier.background(MiuixTheme.colorScheme.surfaceContainer),
                        color = Color.Transparent,
                    )
                },
            ) { padding ->
                val ld = LocalLayoutDirection.current
                // 内容**不**为底栏预留高度：列表要能滚到 dock 下方，
                // 玻璃才有东西可折射（这正是「浮在内容之上」的意义）。
                val contentPadding = PaddingValues(
                    start = padding.calculateStartPadding(ld),
                    top = padding.calculateTopPadding(),
                    end = padding.calculateEndPadding(ld),
                    bottom = padding.calculateBottomPadding(),
                )

                Box(Modifier.fillMaxSize()) {
                    // ── 采集层 ──
                    Box(Modifier.fillMaxSize().layerBackdrop(backdrop)) {
                        AppBackground()
                        AnimatedContent(
                            targetState = page,
                            transitionSpec = {
                                val forward = targetState.ordinal > initialState.ordinal
                                val enter: (Int) -> Int = { if (forward) it / 4 else -it / 4 }
                                val exit: (Int) -> Int = { if (forward) -it / 4 else it / 4 }
                                (
                                    fadeIn(LiquidMotion.snappy()) +
                                        slideInHorizontally(LiquidMotion.gentle(), enter)
                                    ).togetherWith(
                                    fadeOut(LiquidMotion.snappy()) +
                                        slideOutHorizontally(LiquidMotion.snappy(), exit)
                                )
                            },
                            label = "page",
                        ) { p ->
                            Box(Modifier.fillMaxSize().padding(contentPadding)) {
                                DemoPage(p)
                            }
                        }
                    }

                    // ── 悬浮玻璃底栏（在采集层之外）──
                    Box(Modifier.fillMaxSize().padding(padding)) {
                        Box(
                            modifier = Modifier
                                .align(Alignment.BottomCenter)
                                .padding(start = BarMargin, end = BarMargin, bottom = BarMargin)
                                .fillMaxWidth()
                                .height(BarHeight)
                                // 按下缩放作用在整条 dock 上（父修饰符），
                                // 内部滑块自己再乘一个更大的比例，两者天然相乘。
                                .graphicsLayer {
                                    scaleX = barScale
                                    scaleY = barScale
                                }
                        ) {
                            // ① 玻璃底板：只有玻璃、不含任何子内容
                            Box(
                                Modifier
                                    .matchParentSize()
                                    .glassNavBar(
                                        backdrop = backdrop,
                                        shape = RoundedCornerShape(50), // 50% = 真正的胶囊
                                    )
                            )
                            // ② 内容层：与玻璃是兄弟
                            GlassNavBarContent(
                                items = Page.entries.map { it.icon to it.title },
                                selectedIndex = Page.entries.indexOf(page),
                                onSelect = { page = Page.entries[it] },
                                modifier = Modifier.matchParentSize(),
                                backdrop = backdrop,
                                contentHeight = BarHeight,
                                onBarPressedChange = { barPressed = it },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DemoPage(page: Page) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(LiquidSpacing.page),
        verticalArrangement = Arrangement.spacedBy(LiquidSpacing.item),
    ) {
        items(count = 12) { i ->
            LiquidCard {
                LiquidListItem(
                    title = "${page.title} · 第 ${i + 1} 项",
                    subtitle = "往下滚 —— 卡片会从玻璃底栏下方穿过，那就是折射在起作用",
                    leading = page.icon,
                )
            }
        }
    }
}

