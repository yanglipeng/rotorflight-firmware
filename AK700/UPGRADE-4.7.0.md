# AK700 升级到 Rotorflight 4.7.0 —— 完整方案

> 编写日期：2026-11-19
> 基准：飞机实读参数（`AK700_cli_diff_all_20261119.txt`，固件 4.6.0 Nov 10 2026 / MSP API 12.9）
> 目标分支：`ak700-4.6.0` 合入上游 `master`（4.7.0 / MSP API 12.10）；**实际在 `ak700-4.7.0` 上完成**（见第 3 节）

---

## ✅ 执行结果（2026-11-19 17:00 完成）

已刷入并验证。最终状态：

| 项 | 结果 |
| --- | --- |
| 固件 | `4.7.0 Nov 19 2026 / 16:27:30 (norevision)` · MSP API **12.10** |
| custom defaults | 生效（`board_name FLYDRAGON_V2_2` / `board_design RTFL` / `manufacturer_id FDRC`，无警告） |
| Flash | 488 516 B / 491 520 B，余 **3 004 B** |
| 参数 | 244 条命令灌入成功，183 行与刷机前逐行一致；`stats_total_flights = 154` 完好 |
| 产物 | `firmware/AK700_firmware_4.7.0_20261119.hex`（1 199 288 B，含 custom defaults） |

**执行中踩到两个方案里没预见的坑，已修正并写进 AGENTS.md：**

1. **`dfu-util` 不吃 Intel HEX**。把 `.hex` 直接给 `-D`，它按二进制处理，长度 1 381 524 加到
   `0x08000000` 得 `0x08151493` 越界，设备进入 `firmware is corrupt` 状态；此后三段 bin 写入
   **全部返回 `EXIT=0` 却一个字节都没落盘**，刷完 USB 完全不枚举。靠整片备份回滚恢复。
2. **编译产物 hex 不含 custom defaults**。板级资源映射在 `0x08002808–0x08003FFF`，由链接脚本预留、
   不在 hex 里。直接刷会报 `###WARNING: NO CUSTOM DEFAULTS FOUND###`，BEEPER / MOTOR / SERVO /
   SPI / ADC / timer / dma / 陀螺仪 / 串口映射全部缺失。

**修正后的正确流程**：把 hex 固件段 + 从整片备份取来的 custom defaults 与参数区拼成**单个 512 KB 镜像**，
一次写入（带 `-v`），写完 `-U` 读回四处校验，再物理拔插重启。

---

## 0. 先说结论

| 维度 | 结论 |
| --- | --- |
| 版本号 | 固件 4.6.0 → **4.7.0**，MSP API 12.9 → **12.10**，PG 版本 4 组 bump |
| 代码冲突 | 只有 3 个文件 6 个冲突块 + battery.c 里 7 处访问器替换 + 1 处锁复位 |
| 参数冲突 | **0 项被删除**；只有 5 个电池项变数组；新增 7 项（含 2 个 master gain） |
| 最大风险 | Flash —— **已实测，装得下**：合并后 488,500 / 491,520 B，余 3,020 B（比现在这版还多 1,600 B） |
| 参数方案 | 已生成 `AK700_cli_restore_4.7.0.txt`，刷完直接粘贴，不用逐项手改 |

---

## 1. 飞机当前状态快照（2026-11-19 实读）

- 固件：`4.6.0 Nov 10 2026 / 20:29:12 (norevision) MSP API: 12.9`
- 飞行统计：`stats_total_flights = 154`、`stats_total_time_s = 34457`
- 三档转速：profile 0 = 1250、profile 1 = 1900、profile 2 = 2200
- 电池相关 5 行（升级后要变数组的就是这 5 项）：

```
set bat_capacity            = 5000,5200,5200,0,0,0
set battery_cell_count      = 14
set vbat_max_cell_voltage   = 420
set vbat_full_cell_voltage  = 420
set vbat_warning_cell_voltage = 345
（vbat_min_cell_voltage 未出现在 diff 里 = 默认 330）
```

> 注意：这与仓库里那份 `AK700_cli_restore_20261110.txt` 已经不同（文件里节数是自动识别、
> 统计 140 次、rate profile 2 的 srate 也不同）。以本次实读为准。

---

## 2. Gate 0：flash 预算（已实测，装得下）

结论先给：**合并后装得下，而且比现在飞的这版还多出 1.6 KB 余量。**

实测方式：本机 xpack GCC 12.2.1 + `mingw32-make`，`TARGET=STM32F7X2`，与飞机上那版固件完全同一套工具链
（`obj/` 里 2026-11-10 20:31 的产物就是本机编出来的；GitHub Actions 只跑 `unified` 通用目标，不含你板子的
`FDRC-FLYDRAGON_V2_2` config，所以那条路产不出可用的 hex）。

固件区 `0x08008000 - 0x08080000` = 480 KB = 491,520 B：

| 构建 | 代码区占用 | 余量 | 占比 |
| --- | --- | --- | --- |
| 当前在飞的 4.6.0 + 本地改动 | 490,100 B | **1,420 B** | 99.71% |
| 纯上游 4.7.0 | 486,280 B | 5,240 B | 98.93% |
| **合并后 4.7.0 + 本地改动** | **488,500 B** | **3,020 B** | 99.39% |

三点值得注意：

1. **上游 4.7.0 比 4.6.0 更小**。新增约 5.4 KB（`fbus_xact` / `crsf_sensors` / `tune_advisor` /
   `boardalignment_auto` / `status`），但 #514 在统一目标关掉 GHOST / RX_PPM / RX_PARALLEL_PWM、
   #492 关掉 CMS，加上各协议栈的连带剔除，省下约 7 KB，净减 1,600 B。
2. **本地改动总共只占 2,220 B**（合并后 488,500 − 纯上游 486,280）：定速器恢复/限速、救援总距限速、
   节数检测三块加起来的真实体积，比预估的"532 行"要小得多。
3. **RAM 不是瓶颈**：DTCM 40,760 / 64 KB（62%），SRAM1 92,184 / 176 KB（51%）。
   上游把 `isr_vector` 之外的东西没往 RAM 里塞。

生成的 hex 最高地址 `0x0807F434`，到 `0x08080000` 正好 3,020 B，与链接器统计一致。

> 注：以上是合并当天的构建统计。最终**发布 / 刷入版**为 `488 516 B / 余 3 004 B`（差 16 B，
> 来自版本串与最后重编），见第 0 节与 `AK700/README.md` 的 SHA256 表。

> 3 KB 余量对"以后还要继续加功能"仍然偏紧。真要再扩展，裁剪顺序（从安全到激进，改
> `src/main/target/STM32_UNIFIED/target.h` 末尾，集中写成一段 `#undef` 便于以后合并）：
>
> 1. `USE_SBUS_OUTPUT` / `USE_SPORT_MASTER` —— 你用 PWM 舵机 + CRSF，不用总线舵机和 S.Port master
> 2. 只留 CRSF：`USE_SERIALRX_IBUS`、`_IBUS2`、`_SBUS`、`_SPEKTRUM`、`_SUMD`
> 3. 只留 CRSF 遥测：`USE_TELEMETRY_SRXL`、`USE_TELEMETRY_GHST`、`USE_TELEMETRY_FRSKY_HUB`、
>    `USE_TELEMETRY_SMARTPORT`、`USE_TELEMETRY_HOTT`、`USE_TELEMETRY_LTM`、`USE_TELEMETRY_IBUS`、
>    `_IBUS2`、`_IBUS_EXTENDED`、`USE_TELEMETRY_JETIEXBUS`、`USE_TELEMETRY_MAVLINK`
> 4. `USE_LED_STRIP`（你的板级 config 里 `feature LED_STRIP` 开着，若没接灯带可关）
> 5. `USE_CRSF_SENSORS`、`USE_TUNE_ADVISOR`（不打算用就关，省得最多）
> 6. 最后手段：`make/source.mk` 里删掉 `fbus_xact.c`，并同时删掉 `msp.c` 里对应的 XACT 命令分支
>    （否则链接报未定义）

---

## 3. 合并步骤

> **这一节已经执行完毕。** 合并结果在分支 `ak700-4.7.0`：合并提交 `86e6930`（双父：本地 `800d514`
> 含 11-10 的改动快照 + 上游 `3bc524d`），随后 `f39ea06`（cell count 补丁）与 `512d328`（刷机 + 发布）；
> 当前 HEAD `d6165dc`（+ AK7HUD RFSuite 桥接）。临时 worktree `/c/tmp/rf-merge` 已于 2026-11-20 删除，
> 之后直接在仓库主目录构建。下面保留原始步骤，供复核或重做时对照。

### 3.1 准备

```bash
cd /c/project/rotorflight-firmware
git switch -c ak700-4.7.0 ak700-4.6.0
git add -A && git commit -m "TEMP: wip 2026-11-10"   # 实际得到 800d514
git merge master                                     # 实际得到 86e6930
```

### 3.2 冲突一：`README.md`（3 块，纯文字）

你整篇重写成中文项目说明，上游只是把文档链接改到 doc.rotorflight.org。**全取本地**：

```bash
git checkout --ours README.md && git add README.md
```

### 3.3 冲突二：`src/main/msp/msp.c`（2 块）

**出包（MSP_BATTERY_CONFIG）**——取上游的 profile 访问器，但保留你「回报实际生效节数」的意图：

```c
        sbufWriteU16(dst, getBatteryCapacity());
        // 回报实际生效的节数（自动识别或手动），配置值只是没插电池时的兜底
        sbufWriteU8(dst, getBatteryCellCount() ? getBatteryCellCount() : getBatteryProfileCellCount());
        sbufWriteU8(dst, batteryConfig()->voltageMeterSource);
        sbufWriteU8(dst, batteryConfig()->currentMeterSource);
```

**入包（MSP_SET_BATTERY_CONFIG）**——保留上游那 54 字节的分 profile 解析块，块尾补一句：

```c
        if (sbufBytesRemaining(src) >= 9 * BATTERY_PROFILE_COUNT) {
            ... 上游原有 5 个 for 循环 ...
        }

        // 写完立刻生效，不必断电重插电池
        batteryRefreshCellCount();
        break;
```

### 3.4 冲突三：`src/main/sensors/battery.c`（1 块）

`batteryUpdatePresence()` 里**保留本地的 `batteryApplyCellCount();`**，删掉上游那段内联的
「取 profile 节数 + 算阈值」——本地函数已经包含这些，并且多了三段式识别和 13S/14S。

### 3.5 自动合并不出来、但一定编译不过的 7 处

`batteryCellCount` / `vbat*cellvoltage` 现在是数组了，本地代码还当标量用：

| 位置 | 现在的写法 | 改成 |
| --- | --- | --- |
| `batteryGuessCellCount()` | `batteryConfig()->vbatmincellvoltage` | `getBatteryMinCellVoltage()` |
| 同上 | `batteryConfig()->vbatmaxcellvoltage` | `getBatteryMaxCellVoltage()` |
| `batteryUpdateCellThresholds()` | `batteryConfig()->vbatwarningcellvoltage` | `getBatteryWarningCellVoltage()` |
| 同上 | `batteryConfig()->vbatmincellvoltage` | `getBatteryMinCellVoltage()` |
| `batteryApplyCellCount()` | `batteryConfig()->batteryCellCount != 0` | `getBatteryProfileCellCount() != 0` |
| 同上 | `batteryCellCount = batteryConfig()->batteryCellCount` | `= getBatteryProfileCellCount()` |
| `batteryRefreshCellCount()` | `= (batteryConfig()->batteryCellCount != 0)` | `= (getBatteryProfileCellCount() != 0)` |

### 3.6 一处语义补丁（不补会出问题）

上游新增了 `applyBatteryProfile()`：切电池 profile 时延后到解锁状态再生效。你加的
`batteryCellCountLocked` 会跨 profile 存活——切到 12S profile 后仍按锁定的 14S 跑。
必须补：

```c
static void applyBatteryProfile(void)
{
    batteryConfigMutable()->batteryProfile = pendingBatteryProfile;
    batteryProfileChanged = false;

    batteryCellCountLocked = false;      // ← 新增：换 profile 时释放手动锁

    if (voltageState != BATTERY_NOT_PRESENT) {
        voltageState = BATTERY_INIT;
    }
#ifdef USE_SMARTFUEL
    smartFuelInit();
#endif
}
```

### 3.7 提交

```bash
git add -A
git commit -m "Merge upstream 4.7.0 into AK700 branch"
git stash pop        # 恢复你的 11-10 未提交改动（如有冲突按 3.5/3.6 合）
```

---

## 4. 参数怎么处理（核心问题）

### 4.1 结论：只有 5 行要改，其余 290 行原样

我比对了两个版本的完整 CLI 设置表（各 705 / 712 项）：

- **没有任何设置项被删除** → 旧参数不会因为「名字不存在」而丢掉
- 只有 5 项从标量变成 6 元数组：`battery_cell_count`、`vbat_max/full/min/warning_cell_voltage`
- 新增 7 项：`cyclic_master_gain`、`yaw_master_gain`、`crsf_sensors_*`（5 项）
- 数组长度常量（`TELEM_SENSOR_SLOT_COUNT=40`、`GOV_THROTTLE_CURVE_POINTS=9`、`MAX_SUPPORTED_MOTORS=4`、`RPM_FILTER_NOTCH_COUNT=16`）**全部未变**

### 4.2 迁移文件

`AK700/config/AK700_cli_restore_4.7.0.txt` —— 基于飞机实读数据生成，315 行，改动仅此：

```
set battery_cell_count      = 14  →  14,14,14,14,14,14
set vbat_max_cell_voltage   = 420 →  420,420,420,420,420,420
set vbat_full_cell_voltage  = 420 →  420,420,420,420,420,420
set vbat_warning_cell_voltage = 345 → 345,345,345,345,345,345
set vbat_min_cell_voltage   （新增）= 330,330,330,330,330,330
```

为什么 6 个都一样：6 个 profile 数值一致，才能保证你以后用 `bat_profile` 切换时行为不变。
如果你打算真正用 #508 的多电池组能力，可以把 profile 1 改成 13S：

```
profile 0 之外，另起一段（示例，按实际电池改）
set bat_profile = 1
set battery_cell_count = 13,13,13,13,13,13
set bat_capacity = 5000,5000,0,0,0,0
```

### 4.3 几个可选项

- **节数自动识别**：把 `battery_cell_count` 改成 `0,0,0,0,0,0`，交给你的 13S/14S 三段式识别；
  改成 `14,...` 则是锁死 14S（当前飞机的状态）。
- **新遥测传感器**：`SYSTEM_STATUS` = 120、`SYSTEM_CONFIG` = 121。现在的 `telemetry_sensors`
  有 40 个槽、尾部是 0，要的话把其中两个 0 换成 120、121 即可（会占带宽，不必要就别加）。
- **master gain**：#538 的 `cyclic_master_gain` / `yaw_master_gain` 默认 100，按 PID profile 存。
  以后换桨、换旋翼头想整体缩放反馈量时再用，不用改 PID 数值。

### 4.4 绝对不要做的

- **不要**把 `AK700_config_sector_16k.bin`（4.6.0 参数区）回灌到 4.7.0。PG 版本 4 组都变了，
  固件会判定不匹配并整组恢复默认，等于白灌。
- **不要**用 `AK700_flash_full_512k_20261109.bin` 的「部分还原」——整片还原可以（那是连固件一起
  回到 4.6.0），单独挑配置区不行。

---

## 5. 刷机与恢复顺序

1. **先备份**（沿用你 README 里的流程）
   - 整片：`dfu-util -a 0 -d 0483:df11 -s 0x08000000:0x80000:leave -U AK700_flash_full_512k_20261119.bin`
   - 参数区 16 KB 一份（可选，反正 4.7.0 用不上，只为留档）
   - 本次实读的 `diff all` 已存 `AK700_cli_diff_all_20261119.txt`
   - 遥控器 SD 卡的 `WIDGETS/AK7HUD/*.cfg` 与 `cells_log.txt`
2. 刷**已补齐 custom defaults** 的发布版 `AK700/firmware/AK700_firmware_4.7.0_20261119.hex`
   （地面站「固件烧写」直接选它最省事；或按第 0 节拼成单个 512 KB 镜像后 `dfu-util -D` 一次写入，
   只写固件区，不碰 `0x08004000` 起的 16 KB 配置区）。
   **不要直接刷** `downloads/rotorflight_4.7.0_STM32F7X2_merge-4.7.0_20261119.hex` —— 那是合并后
   未经补齐的构建产物，**缺板级 custom defaults**，只用于核对与 MD5 对照。
   若想自己重编：`downloads/build.ps1 TARGET=STM32F7X2 -j`（工具链在 `%USERPROFILE%\.dsh\toolchains`，
   见 `AGENTS.md` 的 Build 一节）
3. 首次上电后进 CLI，敲 `version`，应显示 `4.7.0 ... MSP API: 12.10`
4. 粘贴 `AK700_cli_restore_4.7.0.txt` 全文 → 自动 `save` → **拔插一次 USB**
5. 再进 CLI 核对：
   ```
   version                        # 4.7.0 / MSP API: 12.10
   get battery_cell_count         # 应打印 6 个值（14,14,14,14,14,14）
   get vbat_min_cell_voltage      # 应打印 6 个值
   status                         # ARM 状态、传感器、电池电压
   diff all                       # 与迁移文件逐行对一遍
   ```

---

## 6. 地面验证清单（不装桨）

| 组别 | 检查项 | 期望 |
| --- | --- | --- |
| 电池 | 插 14S 包，配置器电池页 / `status` 看节数 | 14（或按你的自动识别结果） |
| 电池 | 6 个 profile 逐一切换（`bat_profile`） | 节数与门限都跟着变，不掉回默认 |
| 告警 | 电压低于 warning 门限 | 告警触发；低于 critical 触发 LVC 逻辑 |
| 定速器 | 起转（`gov_startup_time`） | 平滑上升，无超调；RPM 信号丢失时进恢复而不飞车 |
| 定速器 | 三档转速切换 1250/1900/2200 | 下切档位不误触发超速保护、不清油门 |
| 救援 | SH 触发 RESCUE（CLIMB） | 总距有上限、变化平缓，不自旋时来回甩 |
| HUD | 遥控器 AK7HUD 主屏 | 电池节数、转速、告警正常；写入节数功能可用 |
| 遥测 | 配置器遥测页 | CRSF 传感器列表正常（若加了 120/121 可见） |
| 整机 | `status` / 电机转向 / 舵机方向 | 与升级前一致 |

> AK7HUD 那边要注意：MSP_BATTERY_CONFIG 回复从 27 字节变成 81 字节。`cellcount.lua` 是
> 「读整包 → 只改第 3 字节 → 整包写回」，逻辑上兼容（上游写入口有 `>= 54 字节` 的守卫），
> 但文件里的长度注释和检查要同步更新，建议先在台架上点一次确认。

---

## 7. 回滚

整片还原即可，不需要额外准备：

```bash
dfu-util -a 0 -d 0483:df11 -s 0x08000000:0x80000:leave -D AK700_flash_full_512k_20261119.bin
```

回滚后固件、参数、飞行统计一起回到 4.6.0 的当前状态。

---

## 8. 验证状态与风险

1. **构建与刷入状态**：工具链在 `%USERPROFILE%\.dsh\toolchains\`（xpack GCC 12.2.1 + mingw32-make，
   2026-11-20 从仓库 `downloads/` 移出），入口 `downloads/build.ps1`。合并树编译 0 error；2026-11-20
   从当前 HEAD 重编通过（`obj/rotorflight_4.7.0_STM32F7X2.hex`）。**已刷入并验证启动**（2026-11-19，
   版本行 `4.7.0 Nov 19 2026 / 16:27:30 · MSP API 12.10`，custom defaults 生效、参数 183 行逐行一致、
   154 次飞行统计完好）；**仍未飞行验证**——首次飞行前的拆桨地面测试清单见第 6 节。
2. **配置器版本**：API 12.10 需要 4.7 代的 Rotorflight Configurator，旧版会提示版本不支持。
3. **KSE4 / AK7HUD 的 API 门槛（已确认）**：脚本只有 `>= 12.09` 的下限判断，12.10 直接通过；
   2026-11-19 又补了 RFSuite 桥接（`rfsuite_bridge.lua`），见 `AK700/AK7HUD/README.md` 第十二、十三节。
4. **统一目标的行为变化**：`#514` 关掉 GHOST / PPM / PARALLEL_PWM，`#492` 全局关掉 CMS。
   你走 CRSF + 遥控器 HUD，理论上无影响，但 CMS 没了意味着 OSD 菜单调参这条路彻底不通。
5. **文档与发布（已完成）**：`AK700/README.md`、`AK700/AK7HUD/README.md` 已同步到 4.7.0 / MSP API 12.10；
   tag `ak700-4.7.0-20261119` 与 Release（6 个资产）已于 2026-11-20 发布。
6. **PID 手感会变**：#538 引入 master gain（默认 100 = 等同原行为），但 `pid.c` 内部重构过，
   升级后第一次悬停建议按新机首飞对待，先看 30 秒振动与转速保持。

---

## 附：备选路线 —— 只摘部分提交（本轮不走，留作退路）

只摘这几个提交（都不碰 `battery.c` / `msp.c` / 版本号）：

```bash
git cherry-pick 3bc524d   # #538 cyclic/yaw master gains
git cherry-pick 9e93d27   # #533 SYSTEM_STATUS / SYSTEM_CONFIG 遥测
git cherry-pick 4b5c315   # #540 板子自动找平
git cherry-pick 7fea6d7   # #507 连续调整死区
git cherry-pick e6cda80 6fe6691   # #515/#516 总线舵机速度限制
git cherry-pick 87665f4   # #517 UART / GPS 加固
```

这样固件仍是 4.6.0 / API 12.9，参数语法完全不用迁移，但要注意两个 PG 重置：

| 提交 | 副作用 | 要做的事 |
| --- | --- | --- |
| #538 | `PG_PID_PROFILE` 0→1，**三个 profile 的 PID 与定速器参数全部恢复默认** | 刷完重贴 `profile 0/1/2` 三段 |
| #533 | `PG_TELEMETRY_CONFIG` 7→8，`telemetry_sensors` 恢复默认 | 刷完重贴 `set telemetry_sensors = ...` |
| 其余 5 个 | 不动 PG | 无需处理 |

另外 #538 给 `MSP_PID_PROFILE` 尾部加了 2 字节却没 bump API 号，4.6 代的配置器读 PID 页
可能报「长度不符」，建议直接用最新配置器连。

代价是拿不到多电池 profile（#508 是整块 battery 体系重构，没法只摘）。

