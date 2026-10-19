# dsh-plugin-labview-tools

LabVIEW / Win32 窗口自动化。把 `labview-tools/` 的 5 个 PowerShell 脚本封装成 4 个 DSH 工具。

## 工具

| 工具 | 对应脚本 | 说明 |
|---|---|---|
| `labview_windows` | `lvenum.ps1` | 枚举进程的**全部**顶层窗口，含隐藏与零尺寸窗口 |
| `labview_ctl` | `lvctl.ps1` | 单次操作：列出 / 聚焦 / 最大化 / 点击 / 按键 / 粘贴 / 截图 |
| `labview_batch` | `lvbatch.ps1` | 按步骤 DSL 回放一串操作，最后截图 |
| `labview_capture` | `lvprint.ps1` / `lvshot.ps1` | `mode=window` 抓被遮挡的窗口；`mode=desktop` 抓整个虚拟桌面 |

### 步骤 DSL（`labview_batch` 的 `steps`）

分号分隔，示例：`N;F:*Untitled*;L120,340;W400;P你好;K^s`

| 步骤 | 含义 |
|---|---|
| `N` | 刷新窗口列表 |
| `F<通配符>` | 聚焦标题匹配的窗口 |
| `X<通配符>` | 最大化并聚焦 |
| `G<通配符>` | 温和置顶（`BringWindowToTop` + `SetForegroundWindow`） |
| `L<x>,<y>` / `R<x>,<y>` / `D<x>,<y>` | 左键 / 右键 / 双击 |
| `M<x>,<y>` | 仅移动光标 |
| `V<x1>,<y1>,<x2>,<y2>` | 拖拽 |
| `K<按键>` | SendKeys，如 `^s` |
| `P<文本>` | 写剪贴板后 Ctrl+V（中文推荐） |
| `W<毫秒>` | 等待 |

> ⚠️ **`F` / `X` / `G` 之前必须先有一个 `N`**。
> 窗口列表在脚本开始时是空的，只有 `N` 步骤（或循环结束后的那次刷新）会填充它；
> 顺序错了不会报错，只会打印 `F: no window like ...` 然后什么也不做。

## 依赖

Windows PowerShell 5.1+。脚本只做 P/Invoke（`user32.dll`、`kernel32.dll`）与
`System.Windows.Forms` / `System.Drawing`，不需要装任何模块。
WSL 下通过 interop 调用也可以。

**这些脚本不会启动 LabVIEW**：它们只连接已经在运行的进程；进程不在就报错退出。

## 风险（务必读）

1. 会合成**真实**的鼠标键盘事件，作用于当时的前台窗口。聚焦与点击之间若焦点被抢走
   （弹窗、Alt-Tab、UAC），操作会落到别的程序上。强制聚焦内部会连按两次 Esc，
   在非目标窗口上可能取消对话框。**运行期间不要动鼠标键盘。**
2. 会覆盖系统剪贴板（`P` 步骤 / `pasteText`），原内容不保存。
3. `-Maximize` 不还原窗口状态。
4. 截图**直接覆盖** `-Out`，无备份。
5. 多个 LabVIEW 实例同时运行时，`Get-Process | Select-Object -First 1` 只会锁定其中任意一个。

## 迁移改动

`-Out` 的默认值由写死的 `C:\Users\<用户名>\AppData\Local\Temp\...` 改为
`(Join-Path $env:TEMP ...)`，并在截图前自动创建输出目录。
原写法在换用户后 `Bitmap.Save` 会抛未捕获异常。

## 安装

桌面端 profile 由 Electron 应用独占管理（`dsh plugin --profile desktop …` 会被官方拒绝）。二选一：
应用内「设置 → 插件 → 添加本地插件」；或把目录放进
`%USERPROFILE%\.dsh\profiles\desktop\plugins\`，在该 profile 的 `package.json` 加 `link:` 依赖、
包名加入 `dsh.profile.bundles`，再用自带 pnpm 装依赖。装完重启 dsh desktop。

纯源码包，无构建步骤：`main` / `exports` 指向 `lib/`，`dsh.bundle.patch` 指向 `cordis.patch.yml`。
