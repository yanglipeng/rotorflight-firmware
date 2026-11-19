# AK700 固件与参数备份（说明文档）

本目录是从飞控实际导出的产物，不是重建出来的。

| 项 | 值 |
| --- | --- |
| 导出时间 | 2026-11-19（4.7.0 刷入当天：整片备份 + 参数导出），先前 2026-11-09、2026-11-02 |
| 飞控 | FlyDragon V2.2（`board_name FLYDRAGON_V2_2`，mcu_id `002600483433510931353834`） |
| MCU | STM32F722 / `STM32F7X2`，512 KB flash |
| 固件版本行（飞机当前） | `Rotorflight / STM32F7X2 (S7X2) 4.7.0 Nov 19 2026 / 16:27:30 (norevision) MSP API: 12.10` |
| 导出方式 | DFU 只读整片 512 KB（`dfu-util -U`）+ 飞控 CLI `diff all` |

## 一、文件清单

| 文件 | 大小 | 说明 |
| --- | --- | --- |
| `firmware/AK700_firmware_4.7.0_20261119.hex` | 1 199 288 B | **最新固件（4.7.0，2026-11-19）**：上游 `master` 4.7.0 合并 + 全部本地修复（定速器 / 救机 / 电池）。**已补入 custom defaults**，地面站「固件烧写」直接选它；不含参数区，可刷同为 FlyDragon V2.2 的飞控 |
| `firmware/AK700_flash_full_512k_20261119.bin` | 524 288 B | 2026-11-19 刷 4.7.0 **之前**的整片备份（4.6.0 固件 + 当日参数 + 154 次飞行统计），整片回滚用 |
| `firmware/AK700_firmware_4.6.0_20261109_overspeed-fix.hex` | 1 387 194 B | 4.6.0 最后一版（2026-11-09）：修「往下切转速档时超速保护误触发、油门被清零」；含 11-07 的起转自限幅 + 独立超速保护 |
| `firmware/AK700_firmware_4.6.0_20261106_battery-apply.hex` | 1 383 549 B | 2026-11-06 构建（电池节数立即生效），不含 11-07 的定速器改动，回退用 |
| `firmware/AK700_firmware_4.6.0_20261105_governor-recovery.hex` | 1 383 549 B | 2026-11-05 构建（定速器恢复安全修复），不含本次电池修复 |
| `firmware/AK700_firmware_4.6.0_20261103_battery-refresh.hex` | 1 382 379 B | 2026-11-03 构建（电池刷新 + 13S/14S 检测），保留作对照 / 回退 |
| `firmware/AK700_firmware_4.6.0_20261102.hex` | 1 382 199 B | 2026-11-02 构建（不含电池刷新改动），保留作对照 / 回退 |
| `firmware/AK700_firmware_4.6.0_20261023.hex` | 1 182 550 B | **飞机最初那份固件的原样镜像**（`Oct 23 2026 / 16:07:29`），从飞控整片读出的 |
| `firmware/AK700_flash_full_512k_20261109.bin` | 524 288 B | 2026-11-09 刷机前的整片备份（**11-07 固件 + 改完参数后的状态 + 统计**），用于整片还原 |
| `firmware/AK700_flash_full_512k_20261106.bin` | 524 288 B | 2026-11-06 刷机前的整片备份（11-05 固件 + 当日参数 + 统计） |
| `firmware/AK700_flash_full_512k_20261105.bin` | 524 288 B | 2026-11-05 刷机前的整片备份（11-03 固件 + 当日参数 + 统计） |
| `firmware/AK700_flash_full_512k_20261023.bin` | 524 288 B | 整片 512 KB：固件 + 板级 custom defaults + 参数区 + 飞行统计 |
| `firmware/AK700_config_sector_16k.bin` | 16 384 B | 参数区单独一份（`0x08004000`–`0x08007FFF`），已更新为 **2026-11-09 飞机实际状态** |
| `config/AK700_cli_diff_all_20261109.txt` | 7 134 B | 飞控 CLI `diff all` 原文（2026-11-09 导出，297 行，参数最准） |
| `config/AK700_cli_restore_20261109.txt` | 7 124 B | 干净版（去掉回显行），可整段粘贴进 CLI 恢复参数 |
| `config/AK700_cli_diff_all_20261106.txt` | 7 433 B | 2026-11-06 版，仅留档 |
| `config/AK700_cli_restore_20261106.txt` | 7 424 B | 2026-11-06 版，仅留档 |
| `config/AK700_cli_diff_all_20261105.txt` | 10 192 B | 2026-11-05 版（含当时的板级设置，因 custom defaults 缺失而出现在 diff 里），仅留档 |
| `config/AK700_cli_diff_all_20261102.txt` | 7 200 B | 旧版（2026-11-02），仅留档 |

> `AK7HUD/` 是配套的**遥控器主屏 widget**（从 KSE4 fork，治自动弹面板 / 地面震动 / 电池节数），
> 单独说明见 `AK7HUD/README.md`。目录内容：`main.lua`、`cellcount.lua`、
> `rfsuite_bridge.lua`（RFSuite 桥接层，2026-11-19 新增）、
> `BatterySounds/txbatlow.wav`（2S 遥控器低电量提示音，2026-11-19 补入仓库）。

**各 hex 的差别**：`20261023` 是飞机最初的原样镜像；`20261102` / `20261103` / `20261105` / `20261106` / `20261109`
都是本仓库重编，只差编译日期串与所含修复：`20261103` 带电池刷新，`20261105` 再叠加定速器恢复修复，
`20261106` 修电池节数立即生效，**`20261109` 再叠加 11-07 的起转自限幅 / 独立超速保护，并修掉其中
「下切转速档误切油门」的问题 —— 日常刷这个**。

## 二、校验（SHA256）

```
7D4BC294B08CCBC61BE0B8DD24F72C3AC8760EDB9AA0619DADA0E8BD428B5A6F  firmware/AK700_firmware_4.7.0_20261119.hex
882E33F9B2B3D840D4F54E1A5663EA8BA5F00B09F2DF6CB25935FE2BB20F3B97  firmware/AK700_flash_full_512k_20261119.bin
4BFB629D42141165B6A45D79B6A7F285C89C62BC237FE57F71965D810EEDED01  config/AK700_cli_diff_all_20261119.txt
44831EABA49045B5AC1B834441FA02576B897897994928A97E711C8628842E79  config/AK700_cli_restore_4.7.0.txt
833B3A5D421A0A89F1FCC516705D69753D5E8EFB13C01F19012EC2EB482E526E  firmware/AK700_firmware_4.6.0_20261109_overspeed-fix.hex
2A4087C142499FD69D95BFCE9123E5FC7ECC5089B83DA3A06B7102E91BBB5889  firmware/AK700_flash_full_512k_20261109.bin
6638AB80E36D13446C0836F0C783FC0D9A6B27A5A7FE3ABED6AE2714F792544F  firmware/AK700_config_sector_16k.bin
285C4BD97FE8D8BD71B5BEA04DF26932349E02B3511E474361656F5716039CC5  config/AK700_cli_diff_all_20261109.txt
A75AB8666FF9473FABA26D75F520E769F228F4E23E4B560FF49DB8787DB4A01A  config/AK700_cli_restore_20261109.txt
C37ACC8E81032111149FEF34DBD8D7174258D4E9CDEAFED288A5E22411653370  firmware/AK700_firmware_4.6.0_20261106_battery-apply.hex
782C13952B64F314D5C13F6EAA0F62258EBAC92A621F688A0B1BE3FBF739328D  firmware/AK700_firmware_4.6.0_20261105_governor-recovery.hex
5942C41AA65633AA9C9D11BD33A700361698A1C2E170F2C067059E098166217F  firmware/AK700_flash_full_512k_20261106.bin
7CD521BDA406925BEA425D1B8AC29E7670531A83B9DF6CCDD6DDD13A19C989EA  firmware/AK700_firmware_4.6.0_20261103_battery-refresh.hex
204C8C33A6EFCD4F8062795166CE07B9D8CEF23B34B50F532F4466DC818DF2A0  firmware/AK700_firmware_4.6.0_20261102.hex
4222CB4545674020D870803C19A2FD70E3C6AC0D92CE010BAE09104BD556B386  firmware/AK700_firmware_4.6.0_20261023.hex
EE4321E43D849582A4EB8CCDD8B704A3A8F696A03AC8FD13C63660E7BFBB9CDE  firmware/AK700_flash_full_512k_20261105.bin
B7D6030D80626AC79532CD64CF01B3D5D7413831C56F41FB692C7404FB0E006D  firmware/AK700_flash_full_512k_20261023.bin
26243F3BE8DB2623F86A4BE88093A345C40869C4BA2E2055AC447D6E357598E5  config/AK700_cli_diff_all_20261106.txt
BB47B6A4550D036D78FAB8C3F63927DA96041B7EA57D99838D67181632F23D5E  config/AK700_cli_restore_20261106.txt
71A4B3D772C697D1CAA704554C4F3343A203521EF9203BE2915FFC3EED70C19C  config/AK700_cli_diff_all_20261105.txt
D21E7729B0E09E29D63D1F503C8B3FEFA3C6EB644A8D1F16F312D8C588EB1E87  config/AK700_cli_restore_20261105.txt
133092844103A9B6413225907D0287535C03C12486D0F62F7ADB3B32A85B7FB7  config/AK700_cli_diff_all_20261102.txt
C8584E6F34120BEDCB5B9EE13B1B4506678FED5255CDA784F9EFBF28E2E32DB9  config/AK700_cli_restore_20261102.txt
```

遥控器脚本 `AK7HUD/`（2026-11-19 版，Release 里的 `AK7HUD-20261119.zip` 即这四份）：

```
221962D9FCA84BCCF0C75FC44F21423838EE11E5B20DCF9402595732F309E7FF  AK700/AK7HUD/main.lua
6D3ABA778B1C84F9515F31768ACAEECEC508A768721E619E621E08297A402692  AK700/AK7HUD/cellcount.lua
17BB62D38B762D3133275A234D64831319DB251ADCE60E3C36E476E4092DE34D  AK700/AK7HUD/rfsuite_bridge.lua
74DA2F72879FAFB2119A9019FB1FD5A6FE5F140F8C9A8496CBDFE613697FCA67  AK700/AK7HUD/BatterySounds/txbatlow.wav
```

## 二之二、版本更新记录

### 2026-11-20：正式发布 4.7.0（Release `ak700-4.7.0-20261119`）+ AK7HUD 支持 RFSuite

4.7.0 固件本身与 2026-11-19 刷入飞机的那份**逐字节相同**（hex SHA256 `7D4BC294…B5A6F`），
本次只是正式发版（tag / Release），并补上一直缺失的遥控器脚本资产与文档：

- **AK7HUD 新增 `rfsuite_bridge.lua`**：官方新架构 RFSuite 不提供 `rf2` 全局，但把 MSP 请求面发布为
  `rfsuite.msp`。桥接层在「`_G.rf2` 不存在 且 `rfsuite.msp` 可用」时构造一个 `rf2` 兼容对象
  （`mspQueue:add` → `client:request`、`useApi` 复用 RFSuite 的 API `parse`），任一条件不满足就完全不动，
  RF Tool 2.3.x 路径逐字未改。`main.lua` 只有两处钩子：顶部优先加载桥接层、`profileRf2()` 探测不到
  `rf2` 时回调一次 `install()`（应付 RFSuite runtime 起得比 widget 晚）。
- **补入 `AK7HUD/BatterySounds/txbatlow.wav`**：此前 README 第 128 行引用了它，但文件从没进过仓库，
  新克隆/新 Release 会缺这个音效。
- **AK7HUD 版本表、文件清单、SHA256** 已同步（见上）。

校验：4 个 Lua 文件 `luac -p` 全部通过；**未上遥控器实机验证**（需要在遥控器上启用 RFSuite Service widget，
再测电池面板读/写节数；同时**必须撤掉 RfTool widget**，两套后台会抢同一个 `crossfireTelemetryPush` 槽）。

发布资产：4.7.0 hex、刷前整片 512 KB 备份、`AK700_cli_diff_all_20261119.txt`、
`AK700_cli_restore_4.7.0.txt`、`AK7HUD-20261119.zip`、`AK700-release-20261119.zip`。

### 2026-11-19：升级到 Rotorflight 4.7.0（合并上游 29 个提交）

从上游 `master` `3bc524d` 合并，固件 **4.7.0**、MSP API **12.10**。

**上游带来的新功能**（对 AK700 有用的排前面）：

| 提交 | 内容 |
| --- | --- |
| #508 | 电池配置改为**每个 profile 各存一份节数和 4 个单节电压** —— 7S / 13S / 14S 可以一个 profile 一种 |
| #538 | cyclic / yaw **master gain**（按比例缩放 P/D/I，换旋翼头不用重调 PID） |
| #533 | `SYSTEM_STATUS` / `SYSTEM_CONFIG` 遥测传感器 |
| #499 / #500 | RX 串口、ESC 遥测**接线自动识别** |
| #540 | 飞控板**自动找平** |
| #518 | XACT 舵机 F.Bus 编程；#497 CRSF 外置传感器解码；#523 tune advisor |

**冲突与解决**（3 个文件 6 块）：

- `README.md` → 取本地中文版；
- `sensors/battery.c` → 保留本地节数检测，7 处标量字段换成 `getBatteryProfileCellCount()` /
  `getBattery*CellVoltage()`；`batteryCellCountLocked` 上移并在 `applyBatteryProfile()` 里清锁；
- `msp/msp.c` → 回复报告实际生效节数；保留上游 54 字节 profile 解析块 + 尾部 `batteryRefreshCellCount()`；
  legacy 标量字节在数组之后生效（保证遥控器 `cellcount.lua` 的读改写仍有效）。

`governor.c` / `rescue.c` 上游未碰，本地修复逐字保留。

**必须重灌参数**：PG 版本 battery 5→6、pid 0→1、feature 1→2、telemetry 6→8。
迁移文件 `config/AK700_cli_restore_4.7.0.txt`（5 个电池项改成 6 元数组，其余 290 行逐字未动）。

**Flash**：488 516 B / 491 520 B，余 **3 004 B**（比 4.6.0 的 1 420 B 更宽裕）。

> **状态（2026-11-20）**：已刷入飞机并验证启动、custom defaults 与参数迁移（183 行逐行一致、
> 154 次飞行统计完好）；**尚未飞行验证** —— 地面测试（拆桨：节数识别、定速器起转/切档/超速、救机总距限幅、
> 低压门限）仍待做。首次飞行前请按旧版流程做台架检查。

> ⚠️ **刷机事故复盘（2026-11-19）**：第一次刷 4.7.0 时把 `.hex` 直接传给
> `dfu-util -D`（dfu-util 不支持 Intel HEX），地址算到 `0x08151493` 越界，设备进入
> `firmware is corrupt` 状态；随后三段 bin 写入**全部返回 `EXIT=0` 但一个字节都没落盘**，
> 导致刷完飞控 USB 完全不枚举。靠 `AK700_flash_full_512k_20261119.bin` 整片回滚恢复，
> 参数 183 行逐行一致。
> **教训**：hex 必须先转 bin；写完必须 `-U` 读回验证（`0x08000000` 首 4 字节应为 `00 00 01 20`）；
> 整片 512 KB 一次写入，不分段。完整规则见根目录 [AGENTS.md](../AGENTS.md)。
>
> 另外：编出来的 hex **不含 custom defaults**（板级资源映射在 `0x08002808–0x08003FFF`，
> 由链接脚本预留、不在 hex 里）。直接用未补齐的 hex 会报 `###WARNING: NO CUSTOM DEFAULTS FOUND###`。
> 本目录的 `AK700_firmware_4.7.0_20261119.hex` 已补齐。

### 2026-11-09：定速器「往下切转速档时油门被清零」修复（含 11-07 的起转保护）

**这一版同时包含 2026-11-07 那批定速器改动（之前只在飞机上跑、没发布）和今天的修复。**

#### A. 2026-11-07 批次：起转自限幅 + 独立超速保护（`governor.c`）

背景是 11-07 的起转险情：转速估计冻结在 59 rpm，定速器的 P/I 完全失明，起转的开环油门一路从 0 爬到 76%，
实际冲到 **2425 转**（目标 1150）。改动：

1. **起转前馈限幅** `govSpoolupThrottleTarget()`：起转目标从「输入油门（定速器用户曲线通常 100%）」改为
   `min(输入, 目标转速所需稳态油门 × 1.10)`；恢复段同样被 `×1.20` 限住（`GOV_SPOOLUP_FF_MARGIN` /
   `GOV_RECOVERY_FF_MARGIN`）。**不依赖转速估计**——估计全死，油门也只停在平衡点附近（1150 档 ~37%、2100 档 ~68%）。
2. **合理性闸门分上下**：起转段（估计 < 90% 目标）向上的大跳变去抖 100 ms 后**跟随**（原来会永久冻结，
   正是 11-07 那次的原因）；到目标以上仍永久冻结。
3. **独立超速跳闸** `govOverspeedCheck()`：用**电机侧转速**（不经过闸门）判断，> 1.2× 目标持续 1 s、
   或 > 1.5× 持续 250 ms → 强制清零油门并清 PID。
4. **跨电池通用常数** `motorRPMKV = 转速 /（油门 × 电压）`：同一架机 14S 实测 60.7、7S 59.7（差 1.5%），
   用来算稳态油门，换电池不会失效（`motorRPMK` 原语义保留）。

#### B. 2026-11-09 修复：跳闸的判定基准（`governor.c`，+39/−1）

**问题**：超速跳闸拿「瞬变的 `requestedHeadSpeed`」当基准。开关一拨，目标 1950 → 1800 → 1150 立刻生效，
而转子还在 **1930 rpm**（> 1.5 × 1150 = 1725）→ 走硬档 → **250 ms 后油门被清零**，转速掉到 ~400 rpm，
1–2 秒才拉回来。2026-11-08 的三个架次 **3/3 复现**（+249..251 ms，归零 31–97 ms；13:13 那架次在 +750 ms
又跳一次 262 ms —— 跳闸没清计时器，速度落进软档又补一刀）。11-06 / 11-07 旧固件同样的下切动作**没有**这个现象。

**修复**：判定基准改为「**向上立刻跟请求、向下等转子真的掉进新目标 1.2× 以内才跟**」，请求一变就清零超速计时器，
另加 2500 ms 兜底防止基准被卡死。保护全程在岗（下切期间按旧的高目标判，那仍是真超速），
且 11-07 防飞车的场景（目标不变、转速持续超 1.2×）不受影响。

**验证**：

| 项 | 结果 |
| --- | --- |
| 仿真（`downloads/gov_sim`，1 kHz 闭环，门禁/PID 原样抽取） | 下切档 **不再有零油门事件**，转速自然衰减 1930→1172（目标 1150），保持 ACTIVE |
| 仿真正对照（稳定 1150 目标、转速持续 1900） | **251 ms 后跳闸**（硬档 250 ms），保护完好 |
| 同一用例跑回滚版源码 | +251 ms 切油、58 ms 零油门 —— 精确复现原缺陷 |
| 整包构建 / 单文件 `-Werror` | exit 0 / 零警告 |
| 刷写后整片回读 | 参数区 **0/16384**、custom defaults **0/6144**、下方镜像 **16384 B 全同**、主代码 **490504 B 全同** |
| 新固件版本行 | `4.6.0 Nov  9 2026 / 15:07:22 (norevision)` |
| Flash 余量 | 镜像结束 `0x0807FC08`，480 KB 固件区**只剩 1016 B** |

**台架建议（先拆桨）**：解锁后把三个转速档来回切（高→低、低→高），确认**切档瞬间油门不掉零**、转速平滑过渡；
再确认「给油到目标后人为拖住转子」这类超速场景仍会被切油。

#### C. 本次参数变化（`gov_f_gain` 15/20/20 → 30/30/30）

按 11-08 日志分析，大机动时转速下垂主要来自**集体矩前馈不足**：`gov_f_gain` 原来只覆盖约 10 个百分点的
油门需求里的 2–3 个。三个 profile 统一改成 **30**（轮廓化上调，先不动其他项）。仿真预期：泵动最低转速
89.6% → 91.1%，代价是卸载峰值 100.0% → 100.9%。若装机后觉得卸载时转速冲高，再往回收；
要更硬可到 40–50（仿真 92.5%，峰值 102.9%）。

另外这次导出的 `diff all` 也把 11-06 以来你自己改的东西记录进来了：三个档位 **1150 / 1800 / 1950**、
`battery_cell_count = 14`、`roll_p_gain 90→75`、`yaw_p_gain 145→120`、`collective_rc_rate 48→50`、
`collective_srate 54→52`。

### 2026-11-06：电池节数立即生效（修 11-03 的漏洞）

**问题**：11-03 加的「写入节数立即生效」在**节数设错时失效**。`batteryRefreshCellCount()` 的提前返回条件是
`voltageState != BATTERY_OK`，而节数设错时（例如 12S 配置插 7S 电池，27 V 远低于 12S 的临界阈值）
电压状态立刻变成 `BATTERY_CRITICAL` → 刷新被跳过 → **只有重启才生效**。

**修复**（`src/main/sensors/battery.c`，+8/−1）：提前返回条件改为
`voltageState == BATTERY_NOT_PRESENT`——只有「完全没插电池」才跳过，其余状态（含 WARNING / CRITICAL）
都立即应用。

**验证**：刷写后回读整片 —— 向量表 0/10240、custom defaults 0/6144、**参数区 0/16384**、主代码 0/489208。

**同日日志侧发现**：
- 第二、三起落飞的是 **7S 电池**（25.7–29.3 V）。目标 1600 转时稳态油门已 97%、I 项饱和，
  侧摆推杆时油门打满仍从 1557 掉到 1379 转 —— **7S 带 1600 转动力不够**，建议 7S 只用 1150–1200。
- 14S @ 2100 转：motor 中位 64%，转速跟踪中位误差 0、p95 65 rpm，健康。

### 2026-11-05：定速器恢复（bailout）安全修复

**问题**：误触油门锁、或熄火后恢复时，转速会冲向满油门（实测 2100 档目标 2100、峰值 2206，超调 5%；目标越低超调越大）。原因是恢复阶段（`GOV_STATE_RECOVERY` / `BAILOUT`）把油门**开环爬向输入油门**，而定速器用户的油门曲线通常是 100%，于是恢复就等于满油门。

**改了什么**（只动 `governor.c`，+77/−1 行）

1. **恢复目标改为「目标转速需要的稳态油门」**（新增 `govRecoveryControl()`）。
   用固件实时学习的电机常数 `motorRPMK` 直接算出该转速需要的油门
   （`requestedHeadSpeed / motorRPMK`），作为 PID 积分项的初值。转子会朝一个平衡点
   加速，而平衡点**正好是目标转速**——既是该传动系能给的最快加速（0 转时扭矩余量最大），
   也不可能超速。PID 仍修残差，所以电机常数不准只影响精度、不影响安全。
   冷启动尚未学到 `motorRPMK` 时回退到输入油门。
2. **修掉 `motorRPMLatch` 粘滞**。原来它只在 `THROTTLE_OFF` / `IDLE` 时清零，于是
   「转子已经停转」仍可能被当成「还在转」进入恢复，并给一个不转的电机加油门。
   现在转速比掉到 5% 以下就清零。
3. 输出仍走单条斜坡（`gov_recovery_time`），不会阶跃，停转时仍有平顺起步。

**验证**：`governor` 仿真 9 项全过（`downloads/gov_sim`）；刷写后回读整片，参数区与备份
**0/16384 字节差异**，向量表与主代码区也与新 hex 逐字节一致。

**台架建议**（先拆桨）：先测「转子完全停转后松开油门锁」（预期 3~5 秒到目标、峰值不超过 +5%），
再测「转子还在转时松开」（应更快、无超调）。

### 2026-11-03：电池节数 / 告警刷新优化

**改了什么**（只动 `battery.c`、`battery.h`、`msp.c` 三个文件，+65/−16 行）

1. **写入节数立即生效**。以前通过 MSP（地面站电池页 / 遥控器脚本）写入
   `battery_cell_count` 后，飞控只是存了配置，当前生效的节数和告警阈值要等
   **拔插电池或重启**才更新。现在 `MSP_SET_BATTERY_CONFIG` 写入后会立即重算
   生效节数、告警电压、临界电压和迟滞电压，`Cel#` 遥测当场变化。
2. **13S / 14S 自动检测**。自动检测表原来最大到 12S（缺 13/14），13S/14S 会掉成
   1S，低压保护失效。现在：
   - 表扩到 `{1..8, 10, 12, 13, 14}`（**故意不含 9/11**，否则 12S 半电会被判成 11S）；
   - 检测窗口改成独立的窄窗口 `3.91–4.20 V/节`，使 6/7/12/13/14 的电压区间互不重叠
     （`13×4.20 = 54.60 V < 14×3.91 = 54.74 V`）；
   - 窄窗口找不到时回退到宽窗口（`vbatmincellvoltage`–`vbatmaxcellvoltage`）兜底。

**为什么这么改**：低压保护阈值（`vbat_min_cell_voltage`）同时也是自动检测窗口的下界，
直接调它会误报低压，所以检测窗口用独立的固定常量，不动用户设置。

**实测能力**：

| 电池 | 满电 ~ 78%（≥3.91V/节） | 78% 以下 |
| --- | --- | --- |
| 6S / 7S / 12S | 正确 | 6S/12S 正确；7S 低电会判成 6S（历史遗留） |
| **13S** | **正确** | 模糊时判成 12S |
| **14S** | **正确** | 模糊时判成 13S |

12/13/14 在 78% 以下电压区间物理重叠（12S 满电 = 14S 3.6V/节），任何算法都无法区分，
所以低电量重连时仍建议用遥控器确认节数。

**兼容性**：MSP API 未变（仍是 12.9），参数组（PG）未改，地面站/遥控器脚本不需要任何改动；
参数区 `0x08004000–0x08007FFF` 不属于这个 hex，刷固件不会动参数。

## 三、怎么刷

### 1. 只刷固件（换版本时用）

1. 地面站（Rotorflight Configurator，**需 4.7 代**，支持 MSP API 12.10）连上飞控
2. 「固件烧写 / Firmware Flasher」→ 选 `firmware/AK700_firmware_4.7.0_20261119.hex`
3. **建议勾 Full chip erase**：这个 hex 已含 custom defaults（`0x08002808–0x08003FFF`），
   全片擦除后会被重新写入；不勾也可以，但参数区残留的 4.6.0 数据会因 PG 版本不匹配而被重置，结果一样
4. 刷完进 CLI 敲 `version`，应显示 `4.7.0 ... MSP API: 12.10`，且 `diff all` 开头**不应**有
   `###WARNING: NO CUSTOM DEFAULTS FOUND###`
5. 粘贴 `config/AK700_cli_restore_4.7.0.txt` 恢复参数（见第 3 小节）

### 2. 整片还原（连参数和飞行统计一起）

先让飞控进 DFU：按住 BOOT 插 USB（或 CLI 敲 `dfu`），USB 会枚举成 `STM32 BOOTLOADER`（`0483:df11`），然后：

```bash
# Windows 下 dfu-util 0.11 可从 https://dfu-util.sourceforge.net/releases/ 下载
dfu-util -a 0 -d 0483:df11 -s 0x08000000:0x80000:leave -D AK700_flash_full_512k_20261119.bin -v
```

会把参数和 `stats_total_flights = 154`、`stats_total_time_s = 34457` 一起写回，写完自动重启。

> ⚠️ **一定要加 `-v`，并且写完读回验证**。`dfu-util` 的返回码不可靠：2026-11-19 出现过
> 三段写入全部报成功、实际 flash 为空的情况。验证方法：
> `dfu-util -a 0 -d 0483:df11 -s 0x08000000:16 -U probe.bin`，首 4 字节应为 `00 00 01 20`。

### 3. 只恢复参数（换固件版本之后）

地面站 → CLI，把 `config/AK700_cli_restore_4.7.0.txt` 全文粘贴进去。文件结构是标准的：

```
batch start
defaults nosave
…… 所有设置 ……
save
```

粘贴完自动执行并保存。末尾会切回导出时激活的档位（`profile 0` / `rateprofile 0`）。

> 4.7.0 的 5 个电池项已改成 6 元数组（每个电池 profile 一份）：
> `battery_cell_count = 14,14,14,14,14,14`、`vbat_max_cell_voltage = 420,420,420,420,420,420` 等。
> 若想让 #508 的自动识别接管节数，把 `battery_cell_count` 改成 `0,0,0,0,0,0`。

## 四、参数速查

- **3 个 PID profile 对应三档转速**：profile 0 = `gov_headspeed 1250`、profile 1 = 1900、profile 2 = 2200
  （`gov_f_gain` 三个 profile 都是 30；profile 2 的 `gov_gain` 是 35，其余用默认 40）
- **定速器前馈**：`gov_f_gain = 30`（治大机动时转速下垂）
- **救机**：`rescue_mode = CLIMB`，三个 profile 的 pull_up/climb/hover collective 分别为
  900/900/800、860/800/700、860/800/674；`rescue_max_collective = 900`
- **自平**：`angle_level_strength = 75`、`angle_level_limit = 25`
- **电池**：`battery_cell_count = 14,14,14,14,14,14`（5 个电池项在 4.7.0 都是 6 元数组）
- **定速器**：`gov_mode = ELECTRIC`、`gov_handover_throttle = 10`、`gov_fallback_drop = 0`、`esc_sensor_protocol = ZTW`
- **调试**：`debug_mode = GOVERNOR`（分析完日志建议改回 `NONE`）
- **模式开关**：SF = 解锁、SG = ANGLE/TRAINER、SH = RESCUE、SB = 蜂鸣 / 静音

## 五、注意事项

1. 刷写前先让地面站断开连接，免得和刷写工具抢串口。
2. 换大版本（4.6→4.7）建议勾 Full chip erase，之后立刻粘贴参数文件；同版本内更新可以不勾。
3. 刷写中断不用担心：STM32F7 有 ROM bootloader，飞控会停在 DFU 里，重新刷即可。
   **ROM DFU 在独立的系统存储区，固件刷写永远碰不到它，芯片刷不坏** —— 按住 BOOT0 插 USB 一定能救。
4. `dfu-util -e`（detach）在 STM32 ROM DFU 上不生效（返回 `can't detach`），读完 / 写完想回正常模式就
   **拔插一次 USB**。
5. **不要相信 `dfu-util` 的返回码**。写完必须读回验证，详见上文「二、校验」和根目录 `AGENTS.md`。
6. Flash 余量：4.7.0 版占用 488 516 B，480 KB 固件区**剩 3 004 B**（比 4.6.0 的 1 016 B 宽裕），
   但后续加功能仍需留意。
