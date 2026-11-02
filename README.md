# AK700 · Rotorflight 4.6.0（含定速器 / 救机本地修复）

这是我（yanglipeng）的 **AK700 700 级直升机**固件树，基于 Rotorflight 上游提交
[`be6a67f`](https://github.com/rotorflight/rotorflight-firmware/commit/be6a67f)（`snapshot/4.6.0-20260208`，
固件版本 **4.6.0**，MSP API **12.9**），**只加了两个本地修复，其余与上游逐字节一致**。

| 项 | 值 |
| --- | --- |
| 机体 | AK700 |
| 飞控 | FlyDragon V2.2（`board_name FLYDRAGON_V2_2`） |
| MCU | STM32F722 · 统一目标 `STM32F7X2` · 512 KB flash |
| 飞机里实际运行的固件 | `4.6.0 Oct 23 2026 / 16:07:29 (norevision)` |
| 配套地面站 | Rotorflight Configurator 2.3.0-20260208 |

> 上游说明文档保留在 [README-upstream.md](README-upstream.md)。

## 直接下载

| 文件 | 说明 |
| --- | --- |
| **[`AK700/firmware/AK700_firmware_4.6.0_20261102.hex`](AK700/firmware/AK700_firmware_4.6.0_20261102.hex)** | **最新固件**（由本仓库源码构建，2026-11-02） |
| [`AK700/firmware/AK700_firmware_4.6.0_20261023.hex`](AK700/firmware/AK700_firmware_4.6.0_20261023.hex) | 飞机里那一版的原样镜像（从飞控 DFU 整片读出） |
| [`AK700/firmware/AK700_flash_full_512k_20261023.bin`](AK700/firmware/AK700_flash_full_512k_20261023.bin) | 整片 512 KB 备份：固件 + 板级默认 + 参数 + 飞行统计 |
| [`AK700/config/AK700_cli_restore_20261102.txt`](AK700/config/AK700_cli_restore_20261102.txt) | 全部参数（CLI `diff all`），粘进 CLI 即可恢复 |

两个 hex **功能完全相同**，只差编译日期字符串（22 字节）。详细说明、SHA256、刷写步骤见
**[AK700/README.md](AK700/README.md)**。

## 与上游的差异（只有这两处）

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

即：**代码与飞机里运行的固件完全相同，参数布局也完全相同**，两版之间互刷不会重置参数。

## 许可

沿用上游 [GPLv3](LICENSE)。Rotorflight 项目：<https://github.com/rotorflight/rotorflight-firmware>
