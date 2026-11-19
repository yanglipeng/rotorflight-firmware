# AK700 · Rotorflight 4.7.0（上游 4.7.0 + 定速器 / 救机 / 电池本地修复）

这是我（yanglipeng）的 **AK700 700 级直升机**固件树：以 Rotorflight 上游 `master`
[`3bc524d`](https://github.com/rotorflight/rotorflight-firmware/commit/3bc524d)（固件版本 **4.7.0**，
MSP API **12.10**）为基础合并，并在其上保留本地几处修复（定速器恢复 / 起转自限幅 / 独立超速保护、
救机总距限速、电池节数检测）。具体见下方「与上游的差异」。

| 项 | 值 |
| --- | --- |
| 机体 | AK700 |
| 飞控 | FlyDragon V2.2（`board_name FLYDRAGON_V2_2`） |
| MCU | STM32F722 · 统一目标 `STM32F7X2` · 512 KB flash |
| 飞机里实际运行的固件 | `4.7.0 Nov 19 2026 / 16:27:30 (norevision)` · MSP API **12.10** |
| 配套地面站 | 需 **4.7 代** Rotorflight Configurator（API 12.10；旧版会提示版本不支持） |
| Flash 占用 | 488 516 B / 491 520 B，余 **3 004 B** |

> 上游说明文档保留在 [README-upstream.md](README-upstream.md)。

## 直接下载

| 文件 | 说明 |
| --- | --- |
| **[`AK700/firmware/AK700_firmware_4.7.0_20261119.hex`](AK700/firmware/AK700_firmware_4.7.0_20261119.hex)** | **最新固件（4.7.0）**。地面站刷这个：已含 custom defaults（板级资源映射），可直接刷到同为 FlyDragon V2.2 的飞控；**不含参数区**，不会把本机参数带过去 |
| [`AK700/firmware/AK700_flash_full_512k_20261119.bin`](AK700/firmware/AK700_flash_full_512k_20261119.bin) | 2026-11-19 刷机前的整片 512 KB 备份（4.6.0 固件 + 当日参数 + 154 次飞行统计），整片回滚用 |
| [`AK700/config/AK700_cli_restore_4.7.0.txt`](AK700/config/AK700_cli_restore_4.7.0.txt) | **4.7.0 参数恢复文件**（315 行，5 个电池项已改成 6 元数组），刷完粘进 CLI |
| [`AK700/config/AK700_cli_diff_all_20261119.txt`](AK700/config/AK700_cli_diff_all_20261119.txt) | 4.6.0 刷机前的原始 `diff all` 留档 |
| **[`AK700/firmware/AK700_firmware_4.6.0_20261109_overspeed-fix.hex`](AK700/firmware/AK700_firmware_4.6.0_20261109_overspeed-fix.hex)** | 4.6.0 最后一版（2026-11-09），回退用 |
| [`AK700/firmware/AK700_firmware_4.6.0_20261106_battery-apply.hex`](AK700/firmware/AK700_firmware_4.6.0_20261106_battery-apply.hex) | 2026-11-06 构建（电池节数立即生效），回退用 |
| [`AK700/firmware/AK700_firmware_4.6.0_20261105_governor-recovery.hex`](AK700/firmware/AK700_firmware_4.6.0_20261105_governor-recovery.hex) | 2026-11-05 构建（定速器恢复修复），回退用 |
| [`AK700/firmware/AK700_firmware_4.6.0_20261103_battery-refresh.hex`](AK700/firmware/AK700_firmware_4.6.0_20261103_battery-refresh.hex) | 2026-11-03 构建（不含定速器恢复修复），回退用 |
| [`AK700/firmware/AK700_firmware_4.6.0_20261023.hex`](AK700/firmware/AK700_firmware_4.6.0_20261023.hex) | 飞机最初那一版的原样镜像（从飞控 DFU 整片读出） |
| [`AK700/firmware/AK700_flash_full_512k_20261109.bin`](AK700/firmware/AK700_flash_full_512k_20261109.bin) | 2026-11-09 整片备份（11-07 固件 + 当日参数 + 统计） |
| [`AK700/firmware/AK700_config_sector_16k.bin`](AK700/firmware/AK700_config_sector_16k.bin) | 参数区 16 KB 备份（`0x08004000–0x08007FFF`，2026-11-09 状态） |

> **刷 4.7.0 前必读**：[AK700/UPGRADE-4.7.0.md](AK700/UPGRADE-4.7.0.md) —— 含参数迁移、刷机安全流程、
> 以及 2026-11-19 那次 `dfu-util` 静默失败（固件未落盘导致 USB 不枚举）的完整复盘。

多个 hex 之间只差编译日期串和所带修复的多少；详细说明、SHA256、刷写步骤、逐版本 changelog 见
**[AK700/README.md](AK700/README.md)**。

## 与上游的差异

**1. `src/main/flight/governor.c` —— 定速器转速信号故障处理**

上游在转速传感器出现单个毛刺时就判故障，会退出闭环甚至切油门；实测中出现过转速瞬时跳变、频繁掉速。
本修复的做法：

- 故障判定去抖 **100 ms**（`GOV_HS_FAULT_DELAY`），单采样毛刺不改变状态、不动油门；
- `govDataUpdate()` 在滤波前做**合理性闸门**：门限 = `max(0.25 × 当前转速, 0.10 × 设定转速)`，
  越界样本冻结估计值而不是跟随（正常飞行不触发，0 延迟）；
- `motorRPMLatch`：本次启动只要测到过一次有效转速，之后信号故障**只保持油门、绝不切油**；
- FALLBACK 油门改用 `slewUpDownLimit`，进出 fallback 不再台阶；
- 起转段 `govSlowStartRate()`：油门底部 15% 按 1/4 速率爬升，抑制起转瞬间尾桨反扭；
- 转速 ≥95% 目标时直接回 ACTIVE（`GOV_HS_RESUME_RATIO`），不绕一圈 RECOVERY。

**2. `src/main/flight/rescue.c` —— 救机总距限幅**

`max_collective` 原来只被高度控制器使用，CLIMB 模式的救机总距没有上限；且总距设定值随倾斜角缩放，
快速旋转时会在满正 / 满负之间摆动。本修复加了硬上限 + 800 units/s 的斜坡限速（`RESCUE_COLL_MAX_RATE`）。

**3. `src/main/sensors/battery.c` / `src/main/msp/msp.c` —— 电池节数立即生效 + 13S/14S**

- MSP 写入 `battery_cell_count` 后立即重算生效节数 / 告警 / 临界 / 迟滞电压（不再等拔插电池或重启）；
  **2026-11-06 修正**：原来的提前返回条件是 `voltageState != BATTERY_OK`，节数设错时电压被判为
  CRITICAL，刷新会被跳过 —— 现在只在「完全没插电池」时跳过；
- 自动检测表扩到 13/14（**不含 9/11**，否则 12S 半电会被判成 11S），检测窗口改为固定窄窗口
  `3.91–4.20 V/节`（`13×4.20 < 14×3.91`），找不到时回退宽窗口。

**4. `src/main/flight/governor.c` —— 恢复（bailout）不再冲向满油门**

- 恢复 / BAILOUT 原来把油门**开环爬向输入油门**（定速器用户曲线通常 100%），实测 2100 档超调 5%，
  低转速档更严重；
- 新增 `govRecoveryControl()`：把 **I 项预置成 `requestedHeadSpeed / motorRPMK`**（目标转速需要的稳态
  油门），转子朝「平衡点 = 目标转速」加速——既是最快加速，也不可能超速；PID 仍修残差；
- `motorRPMLatch` 在转子实际停转（转速比 < 5%）时清零，避免给不转的电机加油门。

**5. `src/main/flight/governor.c` —— 起转自限幅 + 独立超速保护（2026-11-07），以及切档掉油门的修复（2026-11-09）**

背景：2026-11-07 起转险情 —— 转速估计冻结在 59 rpm，定速器的 P/I 完全失明，起转的开环油门一路上爬，
实际冲到 2425 转（目标 1150）。据此加了三条：

- **起转 / 恢复前馈限幅**：`govSpoolupThrottleTarget()` 的起转目标从「输入油门（通常 100%）」改为
  `min(输入, 目标转速所需稳态油门 × 1.10)`，恢复段被 `×1.20` 限住。**不依赖转速估计**，即使估计全死，
  油门也只停在平衡点附近（1150 档 ~37%、2100 档 ~68%）；
- **合理性闸门分上下**：起转段（估计低于 90% 目标）向上的大跳变**去抖 100 ms 后跟随**（原来会永久冻结，
  正是 11-07 那次的原因）；到达/超过目标后仍然永久冻结（假超速保护不变）；
- **独立超速跳闸** `govOverspeedCheck()`：用**电机侧转速**（不经过闸门）判断，> 1.2× 目标持续 1 s
  或 > 1.5× 持续 250 ms 就强制把油门清零；顺带新增跨电池通用的电机常数 `motorRPMKV`
  （转速 /（油门 × 电压），14S 与 7S 实测 60.7 vs 59.7，差 1.5%）。

**2026-11-09 修复**：上面的跳闸原来拿「瞬变的 `requestedHeadSpeed`」当基准，于是**每次往下切转速档**
（1950 → 1150）都被判成超速 —— 开关一拨，目标瞬间变成 1150，而转子还在 1930 rpm（>1.5× 新目标），
250 ms 后油门被清零、转速掉到 ~400 rpm、1–2 秒才拉回来。2026-11-08 的三个架次 **3/3 复现**
（旧固件没有这个现象）。现在的判据是：基准**向上立刻跟请求、向下等转子真的掉进新目标 1.2× 以内才跟**，
请求一变就清超速计时器，另加 2500 ms 兜底防止卡死。仿真验证：切档不再切油，而「目标不变、转速持续
超 1.2×」仍然在 251 ms 内跳闸（保护完好）。

**6. 2026-11-19 合并上游 4.7.0**

从 `be6a67f`（4.6.0）合并到上游 `master` `3bc524d`（4.7.0，29 个提交）。上游带来的主要新功能：

- **#508 电池配置改为「每个 profile 各存一份节数和 4 个单节电压」** —— 对 7S / 13S / 14S 混用最实用；
- #538 cyclic / yaw **master gain**（按比例缩放 P/D/I，换旋翼头不用重调 PID）；
- #533 `SYSTEM_STATUS` / `SYSTEM_CONFIG` 遥测传感器；
- #499 / #500 RX 串口与 ESC 遥测**接线自动识别**；#540 飞控板**自动找平**；
- #518 XACT 舵机 F.Bus 编程；#497 CRSF 外置传感器解码；#523 tune advisor；
- 行为变更：#527 遥测**默认打开**；#514 统一目标禁用 GHOST / PPM / PARALLEL_PWM；#492 关闭 CMS。

冲突只有 3 个文件 6 块，解决方式：

- `README.md`：取本地中文版（上游只是把文档链接改到 doc 站）；
- `src/main/sensors/battery.c`：保留本地的节数检测（armed 锁定、4.05/3.91/3.80 三段窗口、13S/14S），
  把 7 处标量字段换成 `getBatteryProfileCellCount()` / `getBattery*CellVoltage()` 访问器，
  `batteryCellCountLocked` 声明上移，并在 `applyBatteryProfile()` 里清锁（切 profile 时交回自动检测）；
- `src/main/msp/msp.c`：回复里报告**实际生效**的节数；保留上游 54 字节的分 profile 解析块并在尾部调用
  `batteryRefreshCellCount()`；legacy 标量字节在数组之后生效，保证遥控器 `cellcount.lua` 的
  「读出整包→改字节→写回」仍然有效。

**`governor.c` 与 `rescue.c` 上游一次都没碰**，所以 1–5 节的本地修复合并后逐字未变。

> ⚠️ **PG 版本变化**：battery 5→6、pid 0→1、feature 1→2、telemetry 6→8。刷 4.7.0 后这些参数组会
> 恢复默认值，必须重新灌 CLI。跨版本**不能**只回灌参数区 dump。迁移文件见
> [`AK700/config/AK700_cli_restore_4.7.0.txt`](AK700/config/AK700_cli_restore_4.7.0.txt)。

查看具体改动：

```bash
git log -1 --stat
git diff be6a67f HEAD -- src/main/flight/
git log --oneline be6a67f..HEAD -- src/main/    # 上游 29 个提交
```

## 编译

```bash
git clone https://github.com/yanglipeng/rotorflight-firmware.git
cd rotorflight-firmware

# 上游 Makefile 期望 ARM GCC 9.3.1；本机用 12.2.1，需要放行新警告
make TARGET=STM32F7X2 \
     ARM_SDK_DIR=/path/to/xpack-arm-none-eabi-gcc-12.2.1-1.2 \
     GCC_REQUIRED_VERSION=12.2.1 \
     EXTRA_FLAGS=-Wno-error
```

产物：`obj/rotorflight_4.7.0_STM32F7X2.hex`。

> ⚠️ **编出来的 hex 不含 custom defaults！** 板级资源映射（BEEPER / MOTOR / SERVO / SPI / ADC /
> timer / dma / 陀螺仪 / 串口）存在独立的 `0x08002808–0x08003FFF` 区，由链接脚本预留位置但**不在 hex 里**。
> 直接刷这个 hex，飞控会报 `###WARNING: NO CUSTOM DEFAULTS FOUND###`，板级映射全部缺失。
>
> 所以刷机要用**整片 512 KB 镜像**：把 hex 的固件段 + 从旧备份取来的 custom defaults 与参数区拼在一起。
> 本仓库的 `AK700/firmware/AK700_firmware_4.7.0_20261119.hex` 已经补齐 custom defaults，可直接用。

## 一致性验证

4.7.0 刷入后，在 DFU 模式下逐处读回比对：

| 地址 | 内容 | 结果 |
| --- | --- | --- |
| `0x08000000` | 向量表：SP=`0x20010000`、Reset=`0x080671F1` | 逐字节一致 |
| `0x08002808` | `## Rotorflight Custom Defaults` 标记 | 一致，板级映射生效 |
| `0x08008000` | 代码段首 `08 4A 03 46` | 一致 |
| `0x0807F443` | 代码段末，之后全 `FF` | 一致 |

> ⚠️ **不要相信 `dfu-util` 的返回码。** 2026-11-19 出现过三段写入全部报 `EXIT=0` /
> `File downloaded successfully`、实际 flash 一个字节都没写进去的情况（起因：把 `.hex` 直接喂给 `-D`，
> dfu-util 不支持 Intel HEX，地址算到 `0x08151493` 越界，设备进入 `firmware is corrupt` 状态后
> 后续写入静默失效）。**每次写完必须 `-U` 读回比对。** 详见 [AGENTS.md](AGENTS.md) 的
> 「Local Build and Flash Safety」与 [AK700/UPGRADE-4.7.0.md](AK700/UPGRADE-4.7.0.md)。

Flash 占用（480 KB 代码区 `0x08008000–0x0807FFFF` = 491 520 B）：

| 构建 | 占用 | 余量 |
| --- | --- | --- |
| 4.6.0 + 本地改动（2026-11-10，刷机前在飞） | 490 100 B | 1 420 B |
| 纯上游 4.7.0（未叠加本地修复） | 486 280 B | 5 240 B |
| **4.7.0 + 本地改动（当前）** | **488 516 B** | **3 004 B** |

> 上游 4.7.0 反而比 4.6.0 小：新增 `fbus_xact` / `crsf_sensors` / `tune_advisor` / `status` 约 5.4 KB，
> 但 #514 关掉 GHOST / PPM / PARALLEL_PWM、#492 关掉 CMS，连带剔掉一批协议栈，净减约 1.6 KB。
> 本地三块修复（定速器 + 救机 + 电池）实测只占 2 220 B。
> RAM 不是瓶颈：DTCM 40 760 / 64 KB（62%），SRAM1 92 184 / 176 KB（51%）。

## 许可

沿用上游 [GPLv3](LICENSE)。Rotorflight 项目：<https://github.com/rotorflight/rotorflight-firmware>
