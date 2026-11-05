# AK700 · Rotorflight 4.6.0（含定速器 / 救机本地修复）

这是我（yanglipeng）的 **AK700 700 级直升机**固件树，基于 Rotorflight 上游提交
[`be6a67f`](https://github.com/rotorflight/rotorflight-firmware/commit/be6a67f)（`snapshot/4.6.0-20260208`，
固件版本 **4.6.0**，MSP API **12.9**），在本地叠加了几处修复（定速器 / 救机 / 电池节数 / 定速器恢复），
其余与上游一致。具体见下方「与上游的差异」。

| 项 | 值 |
| --- | --- |
| 机体 | AK700 |
| 飞控 | FlyDragon V2.2（`board_name FLYDRAGON_V2_2`） |
| MCU | STM32F722 · 统一目标 `STM32F7X2` · 512 KB flash |
| 飞机里实际运行的固件 | `4.6.0 Nov 5 2026 / 21:54:15 (norevision)` |
| 配套地面站 | Rotorflight Configurator 2.3.0-20260208 |

> 上游说明文档保留在 [README-upstream.md](README-upstream.md)。

## 直接下载

| 文件 | 说明 |
| --- | --- |
| **[`AK700/firmware/AK700_firmware_4.6.0_20261105_governor-recovery.hex`](AK700/firmware/AK700_firmware_4.6.0_20261105_governor-recovery.hex)** | **最新固件**（2026-11-05：定速器恢复安全修复 + 电池刷新 + 13S/14S 检测） |
| [`AK700/firmware/AK700_firmware_4.6.0_20261103_battery-refresh.hex`](AK700/firmware/AK700_firmware_4.6.0_20261103_battery-refresh.hex) | 2026-11-03 构建（不含定速器恢复修复），回退用 |
| [`AK700/firmware/AK700_firmware_4.6.0_20261023.hex`](AK700/firmware/AK700_firmware_4.6.0_20261023.hex) | 飞机最初那一版的原样镜像（从飞控 DFU 整片读出） |
| [`AK700/firmware/AK700_flash_full_512k_20261105.bin`](AK700/firmware/AK700_flash_full_512k_20261105.bin) | 2026-11-05 刷机前的整片 512 KB 备份（固件 + 参数 + 统计） |
| [`AK700/config/AK700_cli_restore_20261102.txt`](AK700/config/AK700_cli_restore_20261102.txt) | 全部参数（CLI `diff all`），粘进 CLI 即可恢复 |

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
- 自动检测表扩到 13/14（**不含 9/11**，否则 12S 半电会被判成 11S），检测窗口改为固定窄窗口
  `3.91–4.20 V/节`（`13×4.20 < 14×3.91`），找不到时回退宽窗口。

**4. `src/main/flight/governor.c` —— 恢复（bailout）不再冲向满油门**

- 恢复 / BAILOUT 原来把油门**开环爬向输入油门**（定速器用户曲线通常 100%），实测 2100 档超调 5%，
  低转速档更严重；
- 新增 `govRecoveryControl()`：把 **I 项预置成 `requestedHeadSpeed / motorRPMK`**（目标转速需要的稳态
  油门），转子朝「平衡点 = 目标转速」加速——既是最快加速，也不可能超速；PID 仍修残差；
- `motorRPMLatch` 在转子实际停转（转速比 < 5%）时清零，避免给不转的电机加油门。

查看具体改动：

```bash
git log -1 --stat
git diff be6a67f HEAD -- src/main/flight/
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

产物：`obj/rotorflight_4.6.0_STM32F7X2.hex`。

## 一致性验证

用本仓库源码 `make clean` 全量重编，与从飞控 DFU 读出的整片 512 KB 镜像逐字节比对：

| 区域 | 大小 | 差异 |
| --- | --- | --- |
| `.isr_vector` | 480 B | 0 |
| `.pg_registry`（参数组注册表） | 2 156 B | 0 |
| `.pg_resetdata`（参数默认值） | 848 B | 0 |
| `.text`（全部代码） | 460 412 B | 22（仅编译日期字符串） |
| `.data` | 13 068 B | 0 |

> 上表是 **2026-11-02 基线**的核对结果（当时飞机里那版 = 本仓库源码构建）。之后每次改动都只增代码、
> 不动参数组（PG），所以 **参数布局依旧一致**，各版本之间互刷不会重置参数。
> 每次刷机后都会用 DFU 回读参数区与刷前备份逐字节比对（最近一次 2026-11-05：0/16384 差异）。

## 许可

沿用上游 [GPLv3](LICENSE)。Rotorflight 项目：<https://github.com/rotorflight/rotorflight-firmware>
