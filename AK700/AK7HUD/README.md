# AK7HUD — Rotorflight 主屏 widget

AK700 用的 Rotorflight 主屏控件，从 **KSE4** fork 而来（保留原版所有已跑通的功能），
专治 KSE4 几个反复坑人的毛病，并把「电池节数 / 单片电压报警」做成干净、可回退的独立模块。

> 适配环境：EdgeTX 2.12.x（HelloRadio V16 实测）、Rotorflight 4.7.0（MSP API 12.10）。
> 兼容 Rotorflight 4.6.0（MSP API 12.9）；依赖官方 Lua 脚本包 RF Tool 2.3.x（`/WIDGETS/RfTool/`）。
> 两者独立共存——**不改 KSE4 的任何文件**，随时切回。

## 一、为什么另起一个（KSE4 的弊端）

| 问题 | KSE4 原版 | AK7HUD |
|---|---|---|
| 电池面板乱弹 | 飞控每次连接/重连都自动弹容量面板，挡主屏 | 面板函数改成空操作，**任何路径都不弹**，只有点电池条才开 |
| 地面狂震 | 电池 0% / RX-BEC 低压时持续震动，插 BEC 就震 | 所有震动统一在 `playBatteryHaptic()` 一处门控：**转速 < 500 一律静默** |
| 电池节数 | 无；固件自动检测表最大 12S，13S/14S 掉成 1S，低压保护失效 | 点电池条 → 选节数 → 原生 MSP 写入飞控 |
| 报警电压 | 无，只能靠固件固定阈值 | 点电池条 → 设每节报警电压（3.00–3.90 V，步进 0.05） |
| 结构脆弱 | 电池逻辑塞在 200 KB 单体里，一处出错整屏白 | 抽成独立 `cellcount.lua`，**惰性加载**，加载失败整屏照常显示 |
| 点一次弹两个菜单 | EdgeTX 可能一次点击投递两次 tap | 触发入口加 300 厘秒去抖 |

## 二、文件

| 文件 | 大小 | 说明 |
|---|---|---|
| `main.lua` | ~205 KB | 主屏（fork 自 KSE4，改动处都有 `AK7HUD` / `akCells` 注释标记） |
| `cellcount.lua` | ~26 KB | 电池节数 / 报警模块，惰性加载，原生 MSP 32/33/130/250 读写 |
| `rfsuite_bridge.lua` | ~9 KB | RFSuite 桥接层：用 `rfsuite.msp` 构造 `rf2` 兼容对象（见第十三节），RF Tool 在场时完全不生效 |
| `BatterySounds/txbatlow.wav` | 58 696 B | 遥控器（2S LiPo）低电量提示音，16 kHz 单声道；缺失时回退 `/SOUNDS/cn/lowbat.wav` |
| `README.md` | 本文件 | |

## 三、安装 / 激活

1. 把整个 `AK7HUD` 目录拷到遥控器 SD 卡：`/WIDGETS/AK7HUD/`
   （`main.lua` + `cellcount.lua` + `rfsuite_bridge.lua` + `BatterySounds/txbatlow.wav`；用 RF Tool 时可不要桥接层）
2. 重启遥控器
3. 遥控器 → 模型 → 屏幕设置 → 把主屏那个控件从 **KSE4** 换成 **AK7HUD**
4. 确认新主屏正常显示后，再考虑删 KSE4（不删也互不影响）

**不要把 `cellcount.lua` 单独乱放**——名字和路径是写死的，改了要同步改 `main.lua` 里的加载路径。

## 四、电池操作流程

```
点电池条
  └─ BATTERY CELLS   （按当前电压列出可能的节数，默认高亮最可能的）
       └─ 选节数 ──→ 写飞控（MSP 32 读 → 只改节数 → 33 写 → 250 存盘 → 130 校验）
            └─ BATTERY ALARM （每节报警电压；KEEP = 沿用上次，CHANGE = 3.00–3.90 V 步进 0.05）
```

- 选完节数会**立即更新主屏 `Cel#`**（不再等 apply 完成才刷新）
- 用新固件（2026-11-03 起）时，飞控**当场应用**新节数，菜单会显示 `N CELLS OK`
- 用旧固件时会提示 `REPLUG PACK TO APPLY`——这是旧固件的限制，不是 widget 的问题
- **2026-11-06 固件修正**：以前若当前节数设错（例如 12S 配置插 7S 电池，电压被判为临界），
  写入会被静默丢弃、只有重启才生效。现在除「完全没插电池」外都会立即应用
- 每个模型单独记忆：`/WIDGETS/AK7HUD/cells_<模型名>.cfg`

## 五、报警与播报行为

| 条件 | 行为 |
|---|---|
| 电压低于「节数 × 每节报警阈值」持续 **5 秒** | 语音播报**单片电压**，屏幕同时显示 `x.xx V/cell` 与总电压/节数 |
| 仍低于阈值 | **每 5 秒重复**播报（短促重复，直到回升） |
| 巡航中（已解锁 / 旋翼转）电压正常 | 每 **20 秒**播报一次单片电压 |
| **转速 < 500**（地面、BEC 阶段、未起转） | **一律静默**，不振不报 |
| 回升到阈值以上但未超 +0.5 V | 静默带：状态保留，不重复报 |
| 超过阈值 +0.5 V | 复位，等下次再触发 |

> 节数取的是**已确认过的值**（cfg 或飞控当前生效值），不是候选猜测值——
> 避免"选完节数但还没写进去"时按错的节数算阈值。

## 六、诊断（出问题先看这三个文件）

| 文件 | 位置 | 内容 |
|---|---|---|
| `cells_addon.txt` | `/WIDGETS/AK7HUD/` | 模块加载成功才会写。**文件存在 = 模块起来了** |
| `cells_log.txt` | `/WIDGETS/AK7HUD/` | 运行时状态流水（加载、MSP 收发、节数、阈值、报警） |
| `cells_<模型>.cfg` | `/WIDGETS/AK7HUD/` | 上次确认的节数与每节报警电压 |

排查顺序：**先看 `cells_log.txt`，不要靠猜**。历史上反复返工就是因为猜而不是读日志。

## 七、回退

- 可在屏幕设置里把控件切回 **KSE4**（立即生效，AK7HUD 不动 KSE4 任何文件）
- 或把 `/WIDGETS/AK7HUD/` 改名/删除，重启后主屏回到 KSE4

## 八、已知限制

- **13S/14S 半电时自动检测会模糊**：12S 满电（50.40 V）与 14S 3.6 V/节（50.40 V）在电压上完全重叠，
  任何算法都分不开。满电～78% 电量时固件能正确识别；放电后重连请**手动选一次节数**。
- 报警阈值只有「每节电压」一个维度，没有按容量/百分比报警。

## 九、2026-11-10 补丁：飞行中不再碰电池配置

配合新固件（`battery.c` 2026-11-10 版：disarm 自动检测 + 手动写入锁定本上电周期）：

| 场景 | 旧行为 | 现在 |
|---|---|---|
| 飞行中电池条被误触 | 可能排队 MSP 33 + **MSP 250（EEPROM 擦写）**，主循环停顿几十 ms | 直接拦截：`STOP ROTOR TO CHANGE CELLS`，菜单不打开、写入被拒 |
| 飞行中轮询 MSP 130 校验 | 写完节数后会每 200 ms 轮询最多 60 s | 转速 ≥1 / 已解锁时暂停轮询，落地后继续 |
| 飞行中写日志 | `cells_log.txt` 每 4 s 整文件重写一遍 SD | 飞行中只缓存到 RAM，落地后一次性落盘 |
| 电池配置反复刷新 | RF Tool 链路抖动 → 每次重连都重新 snapshot（MSP 175 + 32） | 两次 snapshot 之间强制 10 s 冷却，且飞行中不做 |

## 十、2026-11-10 遥控器电池（2S LiPo）显示调整

用户反馈：遥控器电池还有不少电时，顶栏电池条就变黄/变红，很焦虑。

**原因**：旧代码把 2S 包按"7.0 V = 0%、8.4 V = 100%"线性换算，黄色阈值是 ≤50%（≈7.70 V）、红色 ≤30%
（≈7.42 V）。LiPo 中段电压曲线很平，7.4 V 其实还有接近一半电量，却被算成 29%。

**现在**：
- 百分比改用真实放电曲线（LiPo / Li-Ion 各一条），曲线中段不再虚低；
- **颜色阈值按电压**，不再按百分比：

| 电池类型 | 绿色 | 黄色 | 红色 |
|---|---|---|---|
| 2S LiPo | ≥ 7.55 V | 7.35–7.55 V | < 7.35 V |
| 2S Li-Ion | ≥ 7.25 V | 7.00–7.25 V | < 7.00 V |

- **HEADSPEED 面板标题行右侧新增 `TX x.xV NN%`**（原来顶栏那个电池条只有 11 px 宽，放不下字），
  颜色与电池条一致，瞄一眼就知道确切电压和它代表的百分比。选项 `TxBatt`（LiPo / Li-Ion）仍然决定用哪条曲线和阈值。
- **百分比曲线按标准 LiPo 放电表标定**（2026-11-10 二次调整：第一版曲线中段过于悲观，7.7 V 只给 30%，看着像快没电）：

| 2S LiPo 电压 | 8.40 | 8.20 | 8.00 | 7.90 | 7.80 | 7.70 | 7.60 | 7.50 | 7.40 | 7.30 | 7.20 | 7.00 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 百分比 | 100% | 88% | 72% | 64% | 56% | **48%** | 40% | 32% | 24% | 16% | 8% | 0% |
| 颜色 | 绿 | 绿 | 绿 | 绿 | 绿 | 绿 | 绿 | 黄 | 黄 | 红 | 红 | 红 |

  顶栏电池条只有约 14 px 高，1 px ≈ 7%，所以同时把百分比文字显示出来，避免"看着像最后一格"的误判。

- **电压平滑 + 百分比回滞**：`tx-voltage` 会随背光/语音/RF 发射抖动 ±0.1~0.2 V，现在显示值是一阶低通
  （每帧 0.2 系数，约 1 s 时间常数），百分比变化 <2% 不动，数字和条子不再跳。
- **低电量主动提醒**：低于 **7.37 V（LiPo）持续 10 s** → 播报 `BatterySounds/txbatlow.wav`
  （"遥控器电池电量低"，缺文件时回退 `/SOUNDS/cn/lowbat.wav`）+ 短震动；之后每 **5 分钟**重复，**最多 3 次**；
  回升到 **7.55 V** 以上复位。Li-Ion 用 7.02 / 7.25 V。
- **排版微调**：顶栏电池条宽度 20→26（参考像素），更好读；电池条**边框颜色跟随状态**（绿/黄/红）；
  `TX … %` 文本右边缘与下方 `MAX`/`TAIL` 数值列对齐。

## 十一、版本

| 日期 | 变更 |
|---|---|
| 2026-11-03 | 首个版本：从 KSE4 fork、改名、去自动弹面板、震动加转速门控、惰性加载电池模块 |
| 2026-11-03 | 实测修复：① 双击去抖 300 厘秒；② 选中后立即更新主屏节数；③ 震动统一门控（含 RX/BEC 路径） |
| 2026-11-03 | 配合固件 `20261103_battery-refresh`：节数写入立即生效，`REPLUG` 提示仅旧固件需要 |
| 2026-11-10 | 飞行中禁止写电池配置/写 SD 日志/轮询校验；snapshot 加 10 s 冷却；配合新固件自动检测 |
| 2026-11-10 | 遥控器电池改用放电曲线 + 电压阈值（2S LiPo 绿色到 7.55 V），并在 HEADSPEED 面板显示 `TX x.xV` |
| 2026-11-19 | 固件升到 4.7.0（MSP API 12.10）。先做了兼容性核对（第十二节）：`MSP 32/33/175/176` 与 PID profile 的新旧布局全部兼容，无需改代码 |
| 2026-11-19 | 新增 `rfsuite_bridge.lua`：装上官方 RFSuite 也能用（第十三节）；`main.lua` 只加「优先加载桥接层 + `profileRf2()` 探测不到 rf2 时重试」两处钩子，RF Tool 路径逐字未动 |
| 2026-11-19 | 新增 `BatterySounds/txbatlow.wav`（2S 遥控器低电量提示音）—— 此前只写在 README 里，文件一直没进仓库 |
| 2026-11-20 | 随 4.7.0 正式发版（Release `ak700-4.7.0-20261119`）。四个文件 `luac -p` 语法校验通过；**未上遥控器实机验证** |

## 十二、4.7.0 / MSP API 12.10 兼容性（2026-11-19 核对）

固件 4.6.0 → 4.7.0 时上游改了电池参数组（每 profile 一份节数）、PID profile 加了 master gain、
遥测加了 SYSTEM_STATUS，一并核对了对本脚本的影响：

| 项目 | 4.6.0 | 4.7.0 | 对本脚本 |
|---|---|---|---|
| `MSP_API_VERSION` | 12.9 | 12.10 | 通过。脚本只有 `>= 12.09` 下限判断，没有上限 |
| `MSP_BATTERY_PROFILE` (175) / `SET` (176) | 1 字节 active index | 完全没变 | 电池 profile 切换/读取照旧 |
| `MSP_BATTERY_CONFIG` (32) 回复 | 15 B legacy + 6×u16 capacity = 27 B | 前 27 B **逐字节不变**，尾部追加 6×u8 节数 + 4×6×u16 电压 = 81 B | `cellcount.lua` 只用到前 27 B，读取不受影响 |
| `MSP_SET_BATTERY_CONFIG` (33) 写入 | 27 B | 追加段用 `sbufBytesRemaining` 判长度，27 B 旧包仍合法 | **必须靠固件侧本地补丁**：legacy 节数字节在 profile 数组之后再生效，否则写回的节数会被数组覆盖 |
| `MSP_PID_PROFILE` (94) 回复 | 43 B | 44 B（尾部加 cyclic/yaw master gain） | 老 RF Tool 顺序读到 43 B 为止，多出的字节忽略，不会错位 |
| `MSP_SET_PID_PROFILE` (95) 写入 | 43 B | 新字段有 `sbufBytesRemaining >= 2` 保护 | 老脚本写回不会把 master gain 清零 |
| CRSF 遥测传感器 | — | 新增 `SYSTEM_STATUS`(0x1230)；GPS 高度改分米 | 本脚本不读 GPS 高度，新增传感器不被 `CUSTOM` 模式自动启用，无影响 |
| MSP 遥测分帧 | — | #521 修复「替换回复时漏发 START 帧」 | 纯 bug 修复，对脚本只有好处（重试不再整包丢） |

**结论：4.7.0 下 AK7HUD 与 RF Tool 2.3.0.1 可直接使用，无需改脚本。**

> 不要换用官方新架构 **RFSuite**（`rotorflight-lua-edgetx-suite`）。它安装在 `/SCRIPTS/RFSUITE/`，
> 不提供 `rf2` 全局、也没有 `/WIDGETS/RfTool/app.lua`，本脚本的电池模块会直接报 `INSTALL RF TOOL 2.3`。
> RFSuite 虽然原生支持 12.10（master gain、auto-align、ESC 接线检测），但那是另一套东西，二者不共存。

## 十三、RFSuite 共存（2026-11-19）

上一节的结论已经改了：从 2026-11-19 起，本脚本可以跑在 **RFSuite** 上，靠的是新增的
`rfsuite_bridge.lua`。

RFSuite 把 MSP 请求面发布成 `rfsuite.msp`，注释里写得很清楚——`crossfireTelemetryPush` 只有
一个发送槽，脚本自带队列不是拿到第二条通道，而是和它抢，两边都丢包。所以桥接层不建队列，
只把 AK7HUD 的 `rf2.mspQueue:add(message)` 转成 `client:request{...}`。

### 生效条件

桥接层只在同时满足下面两条时接管，任一不满足就完全不动，AK7HUD 回到 RF Tool 原路径：

1. `_G.rf2` 不存在（RF Tool 没跑，或没装）
2. `_G.rfsuite.msp` 可用（RFSuite 的 runtime 已被拉起）

`main.lua` 的 `profileRf2()` 探测不到 rf2 时会回头再调一次 `install()`，所以 RFSuite 比本
widget 起得晚也能接上。

### 用法与红线

- 装了 RFSuite 之后，**必须启用 RFSuite Service widget**（或 RFSuite 仪表盘 widget）放在某个
  屏的小区域里。RFSuite 的连接、CRSF 传感器、MSP 泵只有它活着才跑；没有它，`rfsuite.msp`
  不存在，本脚本的电池面板会退回 `RF TOOL 2.3 REQUIRED`。
- **不要同时启用 RfTool widget。** 两套后台会抢同一个 `crossfireTelemetryPush` 槽。想用
  RFSuite 就把 RfTool widget 从屏幕上撤掉（文件留着不影响）。
- `SCRIPTS/RF2`、`WIDGETS/RfTool` 不用删，留着方便回退：把 RFSuite Service 撤掉、RfTool
  widget 装回去，AK7HUD 立刻回到原来的路径。

### 数据映射

| AK7HUD 拿到的 | RFSuite 侧 |
|---|---|
| `mspQueue:add(message)` | `client:request{command, payload, onReply, onError}` |
| `message.processReply(self, buf)` | `onReply(buf)`，buf 是 1-based 字节数组 |
| `message.retryDelay`（1/10 s） | `timeout`（秒） |
| `useApi("mspBatteryConfig")` | 复用 `rfsuite-core/tasks/msp/api/battery_config.lua` 的 `parse` |
| `status.armingDisableFlags` | `arming_disable_flags`（snake→camel） |
| `stats.stats_total_flights.value` | `flightcount` |

RFSuite 的 `battery_config.lua` 原生认 81 字节布局（含每 profile 节数），所以第 6 版固件
那份 81 字节回复不用本脚本自己判长度。

> **状态：代码已通过 Lua 语法检查，尚未在实机验证。** 首次使用请在地面完成一次
> 「读节数 → 改成相邻值 → 确认飞控真的变了 → 改回来」，再上电飞行。


