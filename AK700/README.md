# AK700 固件与参数备份（说明文档）

本目录是从飞控实际导出的产物，不是重建出来的。

| 项 | 值 |
| --- | --- |
| 导出时间 | 2026-11-02 |
| 飞控 | FlyDragon V2.2（`board_name FLYDRAGON_V2_2`，mcu_id `002600483433510931353834`） |
| MCU | STM32F722 / `STM32F7X2`，512 KB flash |
| 固件版本行 | `Rotorflight / STM32F7X2 (S7X2) 4.6.0 Oct 23 2026 / 16:07:29 (norevision) MSP API: 12.9` |
| 导出方式 | DFU 只读整片 512 KB（`dfu-util -U`）+ 飞控 CLI `diff all` |

## 一、文件清单

| 文件 | 大小 | 说明 |
| --- | --- | --- |
| `firmware/AK700_firmware_4.6.0_20261102.hex` | 1 382 199 B | **最新固件**：本仓库源码 2026-11-02 全量重编，地面站「固件烧写」直接选它 |
| `firmware/AK700_firmware_4.6.0_20261023.hex` | 1 182 550 B | **飞机里那份固件的原样镜像**（`Oct 23 2026 / 16:07:29`），从飞控整片读出的 |
| `firmware/AK700_flash_full_512k_20261023.bin` | 524 288 B | 整片 512 KB：固件 + 板级 custom defaults + 参数区 + 飞行统计 |
| `firmware/AK700_config_sector_16k.bin` | 16 384 B | 参数区单独一份（`0x08004000`–`0x08007FFF`） |
| `config/AK700_cli_diff_all_20261102.txt` | 7 501 B | 飞控 CLI `diff all` 原文（302 行） |
| `config/AK700_cli_restore_20261102.txt` | 7 489 B | 干净版（去掉回显行），可整段粘贴进 CLI |

**两个 hex 功能完全相同**，差别只有编译日期字符串（22 字节）。想保持版本行和飞机现状一致 → 刷
`20261023`；想刷当前源码最新构建 → 刷 `20261102`。二选一即可。

## 二、校验（SHA256）

```
204C8C33A6EFCD4F8062795166CE07B9D8CEF23B34B50F532F4466DC818DF2A0  firmware/AK700_firmware_4.6.0_20261102.hex
4222CB4545674020D870803C19A2FD70E3C6AC0D92CE010BAE09104BD556B386  firmware/AK700_firmware_4.6.0_20261023.hex
B7D6030D80626AC79532CD64CF01B3D5D7413831C56F41FB692C7404FB0E006D  firmware/AK700_flash_full_512k_20261023.bin
8363DACDAF8A52EAC50158D3DEA2904AEA65B37426EAE8C3BCC69F2689301084  firmware/AK700_config_sector_16k.bin
133092844103A9B6413225907D0287535C03C12486D0F62F7ADB3B32A85B7FB7  config/AK700_cli_diff_all_20261102.txt
C8584E6F34120BEDCB5B9EE13B1B4506678FED5255CDA784F9EFBF28E2E32DB9  config/AK700_cli_restore_20261102.txt
```

## 三、怎么刷

### 1. 只刷固件（日常推荐）

1. 地面站（Rotorflight Configurator，MSP API 12.9）连上飞控
2. 「固件烧写 / Firmware Flasher」→ 选 `firmware/AK700_firmware_4.6.0_*.hex`
3. **不要勾 Full chip erase**（参数在配置区 `0x08004000`，这两个 hex 都不含该区域）
4. 刷完进 CLI 敲 `version`，应显示 `4.6.0 ... MSP API: 12.9`

### 2. 整片还原（连参数和飞行统计一起）

先让飞控进 DFU：按住 BOOT 插 USB（或 CLI 敲 `dfu`），USB 会枚举成 `STM32 BOOTLOADER`（`0483:df11`），然后：

```bash
# Windows 下 dfu-util 0.11 可从 https://dfu-util.sourceforge.net/releases/ 下载
dfu-util -a 0 -d 0483:df11 -s 0x08000000:0x80000:leave -D AK700_flash_full_512k_20261023.bin
```

会把参数和 `stats_total_flights = 93`、`stats_total_time_s = 25259` 一起写回，写完自动重启。

> 导出时用的就是同一个工具的参数 `-U`，全程只读，没擦没写。

### 3. 只恢复参数（换固件版本之后）

地面站 → CLI，把 `config/AK700_cli_restore_20261102.txt` 全文粘贴进去。文件结构是标准的：

```
batch start
defaults nosave
…… 所有设置 ……
save
```

粘贴完自动执行并保存。末尾会切回 `profile 1` / `rateprofile 1`（导出时激活的档位）。

## 四、参数速查

- **3 个 PID profile 对应三档转速**：profile 0 = `gov_headspeed 1150`、profile 1 = 1600、profile 2 = 2100
- **救机**：`rescue_mode = CLIMB`，三个 profile 的 collective 分别为 950/900/800、860/800/700、860/800/674
- **训练模式**：`acro_trainer_angle_limit = 25`（profile 级参数，改手感不必动固件）
- **自平**：`angle_level_strength = 75`、`angle_level_limit = 30`
- **定速器**：`gov_mode = ELECTRIC`、`gov_handover_throttle = 10`、`gov_fallback_drop = 0`、`esc_sensor_protocol = ZTW`
- **调试**：`debug_mode = GOVERNOR`（分析完日志建议改回 `NONE`）
- **模式开关**：SF = 解锁、SG = ANGLE/TRAINER、SH = RESCUE、SB = 蜂鸣 / 静音

## 五、注意事项

1. 刷写前先让地面站断开连接，免得和刷写工具抢串口。
2. 别勾 Full chip erase，除非你打算刷完立刻粘贴上面的参数文件。
3. 刷写中断不用担心：STM32F7 有 ROM bootloader，飞控会停在 DFU 里，重新刷即可。
4. `dfu-util -e`（detach）在 STM32 ROM DFU 上不生效，读完 / 写完想回正常模式就**拔插一次 USB**。
5. Flash 已接近写满：480 KB 固件区只剩约 3.3 KB（镜像结束于 `0x0807F318`），后续加功能得先砍东西。
