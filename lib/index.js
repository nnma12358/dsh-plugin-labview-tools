/* ============================================================================
 * dsh-plugin-labview-tools — LabVIEW / Win32 GUI 自动化（profile bundle, Host half）
 *
 * 把工作区里 5 个自制的 PowerShell 脚本封装成 DSH 工具：
 *   lvenum.ps1   → labview_windows   枚举进程的全部顶层窗口（含隐藏）
 *   lvctl.ps1    → labview_ctl       单次操作：列出/聚焦/最大化/点击/按键/粘贴/截图
 *   lvbatch.ps1  → labview_batch     按步骤 DSL 回放一串操作后截图
 *   lvprint.ps1  → labview_capture   window 模式：PrintWindow 抓被遮挡的窗口
 *   lvshot.ps1   → labview_capture   desktop 模式：抓整个虚拟桌面
 *
 * 设计取舍：
 *   - 只依赖 node:child_process，不 inject 任何 Host 服务（除 tools），
 *     因此在 web / desktop / headless 任何 profile 下都能挂载。
 *   - PowerShell 脚本本身不做任何删除/移动，只写 -Out 指定的 PNG。
 *   - 这些脚本连接的是「已经在运行的」LabVIEW 进程，本身不会启动 LabVIEW。
 * ========================================================================== */

import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

export const name = 'labview-tools'
export const inject = ['tools']

const PAYLOAD = join(dirname(fileURLToPath(import.meta.url)), '..', 'payload')

/* ---------------------------------------------------------------- 运行时探测 */

/** PowerShell 可执行文件的候选路径：WSL 下走 interop，Windows 下走 PATH。 */
function resolvePowerShell() {
  if (process.env.DSH_POWERSHELL) return process.env.DSH_POWERSHELL
  if (process.platform === 'win32') return 'powershell.exe'
  const interop = '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
  return existsSync(interop) ? interop : 'powershell.exe'
}

/** 把 Linux 路径翻成 Windows 路径，供 powershell.exe -File 使用。 */
async function toWindowsPath(linuxPath) {
  if (process.platform === 'win32') return linuxPath
  const r = await run(['wslpath', '-w', linuxPath], { timeoutMs: 15000 })
  if (r.code === 0 && r.stdout.trim()) return r.stdout.trim()
  return linuxPath
}

/* -------------------------------------------------------------------- 进程 */

/** 启动一个子进程并收齐输出；永不 reject，超时用 SIGKILL 收尾。 */
function run(argv, opts = {}) {
  return new Promise((resolve) => {
    let child
    try {
      child = spawn(argv[0], argv.slice(1), {
        cwd: opts.cwd,
        env: { ...process.env, ...(opts.env || {}) },
        windowsHide: true,
      })
    } catch (error) {
      resolve({ code: -1, stdout: '', stderr: String((error && error.message) || error), timedOut: false })
      return
    }
    const cap = opts.maxBytes || 2000000
    let stdout = ''
    let stderr = ''
    let timedOut = false
    let timer = null
    if (opts.timeoutMs) {
      timer = setTimeout(() => {
        timedOut = true
        try { child.kill('SIGKILL') } catch { /* 已经退出 */ }
      }, opts.timeoutMs)
    }
    child.stdout.on('data', (d) => { if (stdout.length < cap) stdout += d.toString('utf8') })
    child.stderr.on('data', (d) => { if (stderr.length < cap) stderr += d.toString('utf8') })
    child.on('error', (error) => {
      if (timer) clearTimeout(timer)
      resolve({ code: -1, stdout, stderr: stderr + String((error && error.message) || error), timedOut })
    })
    child.on('close', (code) => {
      if (timer) clearTimeout(timer)
      resolve({ code, stdout, stderr, timedOut })
    })
  })
}

/** 调用 payload 里的一个 .ps1，返回机器的原始输出。 */
async function runPs(script, psArgs, opts = {}) {
  const scriptPath = join(PAYLOAD, script)
  const hostPath = await toWindowsPath(scriptPath)
  const argv = [
    resolvePowerShell(),
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', hostPath,
    ...psArgs,
  ]
  const r = await run(argv, { timeoutMs: opts.timeoutMs || 120000 })
  const text = [r.stdout.trim(), r.stderr.trim()].filter(Boolean).join('\n')
  if (r.timedOut) {
    return { ok: false, text: '超时（已终止）：' + script + '\n' + text }
  }
  if (r.code !== 0) {
    return { ok: false, text: '退出码 ' + String(r.code) + '：' + script + '\n' + text }
  }
  return { ok: true, text: text || '(无输出)' }
}

/* --------------------------------------------------------------- 参数拼装 */

/** 把对象翻成 PowerShell 命令行：布尔 true → 开关，null/undefined/false 跳过。 */
function psFlags(args, allowed) {
  const out = []
  for (const key of allowed) {
    const value = args[key]
    if (value === undefined || value === null || value === false || value === '') continue
    const flag = '-' + key.charAt(0).toUpperCase() + key.slice(1)
    if (value === true) { out.push(flag); continue }
    out.push(flag, String(value))
  }
  return out
}

/** 声明式工具注册：统一 render 与错误包装。 */
function define(ctx, spec) {
  ctx.tools.register({
    name: spec.name,
    description: spec.description,
    parameters: { type: 'object', properties: spec.properties, required: spec.required || [] },
    output: {
      schema: { type: 'string' },
      render: (_args, value) => [{ type: 'text', text: String(value) }],
    },
    execute: async (args) => {
      try {
        return await spec.execute(args || {})
      } catch (error) {
        return '工具内部错误：' + String((error && error.message) || error)
      }
    },
  })
}

/* ------------------------------------------------------------------- 注册 */

export function apply(ctx) {
  /* --- 1. 枚举窗口 ------------------------------------------------------- */
  define(ctx, {
    name: 'labview_windows',
    description: '枚举某个进程（默认 LabVIEW）的全部顶层窗口，含隐藏窗口与零尺寸窗口，'
      + '输出 hwnd / 可见性 / 是否最小化 / 矩形 / 样式 / 类名 / 标题。'
      + '当别的工具「找不到窗口」时，先用它排查。',
    properties: {
      procName: { type: 'string', description: '进程名，不含 .exe，默认 LabVIEW。' },
    },
    async execute(args) {
      const r = await runPs('lvenum.ps1', psFlags(args, ['procName']), { timeoutMs: 60000 })
      return r.text
    },
  })

  /* --- 2. 单次窗口操作 --------------------------------------------------- */
  define(ctx, {
    name: 'labview_ctl',
    description: '对已运行的 LabVIEW（或任意 Win32 程序）窗口做一次操作：列出窗口、聚焦、最大化、'
      + '点击（left/right/double）、发送按键、粘贴文本，并在结束时截图。'
      + '坐标默认是相对窗口的像素；给 full=true 则使用整屏坐标。'
      + 'pasteText 用剪贴板绕过输入法，是输入中文的推荐方式。'
      + '注意：-Maximize 之后不会还原窗口状态。',
    properties: {
      procName: { type: 'string', description: '进程名，默认 LabVIEW。' },
      list: { type: 'boolean', description: '只列出窗口后退出，不做任何操作。' },
      win: { type: 'number', description: '窗口序号（来自 list 输出）；默认取最大的可见窗口。' },
      titleLike: { type: 'string', description: '用通配符匹配标题选窗口，例如 *Untitled*。' },
      full: { type: 'boolean', description: 'true 时坐标按整屏算，且截图为整屏。' },
      x: { type: 'number', description: '点击 X 坐标；必须与 y 同时给出才生效。' },
      y: { type: 'number', description: '点击 Y 坐标。' },
      click: { type: 'string', description: 'left | right | double。' },
      keys: { type: 'string', description: 'SendKeys 语法，例如 ^s（Ctrl+S）、%{F4}。' },
      type: { type: 'string', description: '直接输入的文本（SendKeys 语法，特殊字符需转义）。' },
      pasteText: { type: 'string', description: '写入剪贴板后 Ctrl+V，适合中文。' },
      maximize: { type: 'boolean', description: '先最大化目标窗口。' },
      noFocus: { type: 'boolean', description: '不改变前台窗口。' },
      noCapture: { type: 'boolean', description: '不截图。' },
      settleMs: { type: 'number', description: '操作前后的等待毫秒数，默认 700。' },
      out: { type: 'string', description: '截图输出路径（.png）；默认写到临时目录。' },
      maxWidth: { type: 'number', description: '截图最大宽度，默认 2400。' },
    },
    async execute(args) {
      const flags = psFlags(args, ['procName', 'list', 'win', 'titleLike', 'full', 'x', 'y',
        'click', 'keys', 'type', 'pasteText', 'out', 'noFocus', 'noCapture', 'maximize',
        'maxWidth', 'settleMs'])
      const r = await runPs('lvctl.ps1', flags, { timeoutMs: 180000 })
      return r.text
    },
  })

  /* --- 3. 步骤回放 ------------------------------------------------------- */
  define(ctx, {
    name: 'labview_batch',
    description: '用分号分隔的步骤 DSL 驱动窗口，跑完一整串操作后截图。'
      + '步骤语法：N 刷新窗口列表；F<通配符> 聚焦；X<通配符> 最大化并聚焦；G<通配符> 温和置顶；'
      + 'L<x>,<y> 左键；R<x>,<y> 右键；D<x>,<y> 双击；M<x>,<y> 仅移动；'
      + 'V<x1>,<y1>,<x2>,<y2> 拖拽；K<按键>；P<文本> 剪贴板粘贴；W<毫秒> 等待。'
      + '重要：F/X/G 之前必须先有一个 N 步骤刷新窗口列表，否则一律匹配失败。'
      + '示例："N;F:*Untitled*;L120,340;W400;P你好;K^s"。',
    properties: {
      steps: { type: 'string', description: '分号分隔的步骤串（必填）。' },
      procName: { type: 'string', description: '进程名，默认 LabVIEW。' },
      titleLike: { type: 'string', description: '起始窗口标题通配符。' },
      full: { type: 'boolean', description: '坐标按整屏算。' },
      defaultWaitMs: { type: 'number', description: '每步默认等待毫秒数，默认 700。' },
      maxWidth: { type: 'number', description: '截图最大宽度，默认 2400。' },
      out: { type: 'string', description: '截图输出路径（.png）。' },
    },
    required: ['steps'],
    async execute(args) {
      if (!args.steps) return '缺少必填参数 steps。'
      const flags = psFlags(args, ['procName', 'steps', 'titleLike', 'full', 'defaultWaitMs',
        'maxWidth', 'out'])
      const r = await runPs('lvbatch.ps1', flags, { timeoutMs: 300000 })
      return r.text
    },
  })

  /* --- 4. 截图 ----------------------------------------------------------- */
  define(ctx, {
    name: 'labview_capture',
    description: '截图。mode=window（默认）用 PrintWindow 抓指定窗口，窗口被遮挡或部分移出屏幕也能抓到；'
      + 'mode=desktop 抓整个虚拟桌面。两者都只写一个 PNG，不修改被截窗口的状态。',
    properties: {
      mode: { type: 'string', description: 'window（默认）或 desktop。' },
      procName: { type: 'string', description: '进程名，默认 LabVIEW（仅 window 模式）。' },
      titleLike: { type: 'string', description: '按标题通配符选窗口（仅 window 模式）。' },
      win: { type: 'number', description: '窗口序号，默认 0 即最大窗口（仅 window 模式）。' },
      list: { type: 'boolean', description: '只列出窗口，不截图（仅 window 模式）。' },
      out: { type: 'string', description: '输出 PNG 路径。' },
      maxWidth: { type: 'number', description: '最大宽度，desktop 模式默认 1600。' },
    },
    async execute(args) {
      const mode = String(args.mode || 'window').toLowerCase()
      if (mode === 'desktop') {
        const flags = psFlags(args, ['out', 'maxWidth'])
        const r = await runPs('lvshot.ps1', flags, { timeoutMs: 120000 })
        return r.text
      }
      const flags = psFlags(args, ['procName', 'titleLike', 'win', 'list', 'out'])
      const r = await runPs('lvprint.ps1', flags, { timeoutMs: 120000 })
      return r.text
    },
  })
}
