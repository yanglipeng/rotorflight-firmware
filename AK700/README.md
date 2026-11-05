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
| `firmware/AK700_firmware_4.6.0_20261105_governor-recovery.hex` | 1 383 549 B | **最新固件（2026-11-05）**：定速器恢复（bailout）安全修复——恢复不再冲向满油门。地面站「固件烧写」直接选它 |
| `firmware/AK700_firmware_4.6.0_20261103_battery-refresh.hex` | 1 382 379 B | 2026-11-03 构建（电池刷新 + 13S/14S 检测），保留作对照 / 回退 |
| `firmware/AK700_firmware_4.6.0_20261102.hex` | 1 382 199 B | 2026-11-02 构建（不含电池刷新改动），保留作对照 / 回退 |
| `firmware/AK700_firmware_4.6.0_20261023.hex` | 1 182 550 B | **飞机里那份固件的原样镜像**（`Oct 23 2026 / 16:07:29`），从飞控整片读出的 |
| `firmware/AK700_flash_full_512k_20261023.bin` | 524 288 B | 整片 512 KB：固件 + 板级 custom defaults + 参数区 + 飞行统计 |
| `firmware/AK700_config_sector_16k.bin` | 16 384 B | 参数区单独一份（`0x08004000`–`0x08007FFF`），已更新为 2026-11-03 飞机实际状态 |
| `config/AK700_cli_diff_all_20261102.txt` | 7 501 B | 飞控 CLI `diff all` 原文（302 行） |
| `config/AK700_cli_restore_20261102.txt` | 7 489 B | 干净版（去掉回显行），可整段粘贴进 CLI |

> `AK7HUD/` 是配套的**遥控器主屏 widget**（从 KSE4 fork，治自动弹面板 / 地面震动 / 电池节数），
> 单独说明见 `AK7HUD/README.md`。

**四个 hex 的差别**：`20261023` 是飞机原样镜像；`20261102` / `20261103` / `20261105` 都是本仓库重编，
前两个只差编译日期串，**`20261103` 带电池刷新改动，`20261105` 再叠加定速器恢复修复**。日常刷 `20261105` 即可。

## 二、校验（SHA256）

```
782C13952B64F314D5C13F6EAA0F62258EBAC92A621F688A0B1BE3FBF739328D  firmware/AK700_firmware_4.6.0_20261105_governor-recovery.hex
7CD521BDA406925BEA425D1B8AC29E7670531A83B9DF6CCDD6DDD13A19C989EA  firmware/AK700_firmware_4.6.0_20261103_battery-refresh.hex
204C8C33A6EFCD4F8062795166CE07B9D8CEF23B34B50F532F4466DC818DF2A0  firmware/AK700_firmware_4.6.0_20261102.hex
4222CB4545674020D870803C19A2FD70E3C6AC0D92CE010BAE09104BD556B386  firmware/AK700_firmware_4.6.0_20261023.hex
B7D6030D80626AC79532CD64CF01B3D5D7413831C56F41FB692C7404FB0E006D  firmware/AK700_flash_full_512k_20261023.bin
4A63AE7D707D08E04310EE6C9F0F11BED805D7F88FA2DD20B36A58442A50C671  firmware/AK700_config_sector_16k.bin
133092844103A9B6413225907D0287535C03C12486D0F62F7ADB3B32A85B7FB7  config/AK700_cli_diff_all_20261102.txt
C8584E6F34120BEDCB5B9EE13B1B4506678FED5255CDA784F9EFBF28E2E32DB9  config/AK700_cli_restore_20261102.txt
```

## 二之二、版本更新记录

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
