# GitHub 自动编译 OpenWrt

这是一个基于 GitHub Actions 的 OpenWrt 自动编译框架，用来集中管理编译配置、自定义脚本和固件产物。

[固件更新日志](CHANGELOG.md)

仓库提供三套 x86_64 构建方案：

- `OpenWrt lede Build`：基于 `coolsnowwolf/lede`，优先保证经典 LEDE 固件稳定产出。
- `OpenWrt Immortal Build`：基于 `immortalwrt/immortalwrt` 的 24.10 分支。
- `OpenWrt Official Build`：基于 `openwrt/openwrt` 的 `v25.12.6` 官方源码标签，使用本仓库的固件配置和插件。

## 目录结构

```text
.
|-- .github/workflows/build-lede.yml
|-- .github/workflows/build-immortal.yml
|-- .github/workflows/build-openwrt.yml
|-- config/
|   |-- lede_x86_64.config
|   |-- immortal_x86_64.config
|   `-- openwrt_x86_64.config
`-- scripts/
    |-- diy-lede.sh
    `-- diy-immortal.sh
```

## 使用方法

推送到 `main` 后，三套工作流会使用默认参数自动构建。也可以在仓库的 `Actions` 页面手动运行其中一个工作流，并按需填写参数。

- `repo_url`：OpenWrt 源码仓库地址
- `repo_branch`：源码分支或标签
- `config_file`：当前仓库中的配置文件路径
- `script_file`：当前仓库中的自定义脚本路径
- `artifact_name`：上传后的产物名称
- `compile_threads`：编译线程数，`0` 表示自动使用全部 CPU
- `upload_release`：是否同时创建 GitHub Release，默认 `true`；选择 `false` 时只上传 Actions Artifact

## 默认入口

LEDE 构建：

- 默认源码：`https://github.com/coolsnowwolf/lede`
- 默认分支：`master`
- 默认配置：`config/lede_x86_64.config`
- 默认脚本：`scripts/diy-lede.sh`

ImmortalWrt 构建：

- 默认源码：`https://github.com/immortalwrt/immortalwrt`
- 默认分支：`openwrt-24.10`（保留此前因主题兼容而回退的版本基础，每次构建拉取该分支最新代码）
- 默认配置：`config/immortal_x86_64.config`
- 默认脚本：`scripts/diy-immortal.sh`

OpenWrt 官方源码构建：

- 默认源码：`https://github.com/openwrt/openwrt`
- 默认标签：`v25.12.6`，软件包管理器为 `apk`
- 默认配置：`config/openwrt_x86_64.config`
- 默认脚本：`scripts/diy-immortal.sh`，主机名设为 `OpenWrt`
- Actions 产物名：`OpenWrt_x86_64_Official`，Release 标签以 `openwrt-` 开头
- APK 软件包管理器只使用与固件版本对应的 OpenWrt 官方源。PassWall、SSR-Plus 和 Vantage 等第三方软件包随固件构建。

两个脚本都支持两个执行阶段：

- `STAGE=pre`：添加 feeds、主题和额外插件
- `STAGE=post`：在复制 `.config` 之后修改默认配置

## 主题与插件说明

三套固件都内置 Edge、Vantage 和 Bootstrap。默认使用 Edge，可在「系统 → 系统 → 语言和界面」切换主题。固件包含 OpenClash、SSR-Plus、PassWall、HomeProxy 和常用 LuCI 应用。网络共享服务 Samba 和 FTP 已移除，LuCI 文件管理器仍可管理路由器本机文件。

OpenClash 来自 `vernesong/OpenClash`，PassWall 及其依赖来自 `Openwrt-Passwall`，Vantage 来自 `anothaDev/luci-theme-vantage`。OpenClash 使用独立目录下的稳定版 Mihomo amd64-compatible 核心，并在构建时验证下载文件的 SHA256。

SSR-Plus 保留 Xray，同时内置经 SHA256 校验的 Mihomo 1.19.34，安装在 `/usr/bin/mihomo`。同一 LAN 只开启一个插件的透明代理和 DNS 接管。

三套构建的代理核心版本至少为 Xray 26.11.9、sing-box 1.14.4、Hysteria 2.14.0、TUIC Client 1.8.11 和 NaiveProxy 154.0.8037.49-5。LEDE 的 Xray 和 sing-box 沿用上游源码配方，其余代理核心使用经 SHA256 校验的上游 x86_64 发布文件。发布时根据固件清单核对版本。

各构建配置均包含：

- 基本路由、NAT、防火墙、LuCI 网络管理、DHCP 上网和 PPPoE 拨号。
- IPv6 内核、DHCPv6 客户端、前缀委派（PD）、odhcpd 的 DHCPv6 服务、RA 与 SLAAC。
- dnsmasq-full：DNS 缓存、DHCPv4、静态租约、DNSSEC 和 IPv6 DNS 解析支持；IPv6 地址分配由 odhcpd 负责。
- firewall4/nftables/nftset，供 PassWall 和 SSR-Plus 使用 nftables 透明代理后端。

全新刷机时，LAN 为 `192.168.2.1/24`，DHCP 地址池为 `.100` 至 `.249`，租期 12 小时。WAN 自动请求 IPv6 地址和前缀委派（PD）。收到 PD 时，LAN 从该前缀分配一个 /64，并通过 RA/SLAAC 和 DHCPv6 为设备配置 IPv6。上游无 PD 且支持中继时，odhcpd 在上游与 LAN 之间中继 RA、DHCPv6 和 NDP。LAN 保留 AAAA 解析。

IPv6 中继按标准拓扑配置，上游接 WAN，设备接 LAN。首次启用时根据 WAN 协议选择中继主接口，DHCP 使用 `wan6`，PPPoE 使用 `wan_6`。收到 PD 后，在 LuCI 的「网络 → 接口」中，WAN6 显示上游委派前缀，LAN 显示从该前缀分配的地址。以后更换 WAN 协议时，在 LuCI 中将中继主接口切换到新的 IPv6 上游接口。标准路由配置可通过保留设置升级启用中继，已经自定义了 RA、DHCPv6 或 NDP 的配置继续沿用现有设置。

上游支持中继时，有 PD 也可以手动使用中继。将上游主接口和 LAN 的 RA、DHCPv6、NDP 均设为「中继模式」，LAN 客户端通过中继获取上游提供的 IPv6，地址可能属于上游链路的网段。要恢复从委派前缀自动为 LAN 分配地址，将两端的三项服务改回「混合模式」。

OpenClash 和 PassWall 默认关闭。HomeProxy 使用三套固件内置的 sing-box，预装简体中文界面，默认未选客户端节点，服务端也关闭。配置节点后，选择一个代理接管透明代理和 DNS，以免争抢规则和端口。

ImmortalWrt 使用 `openwrt-24.10`，LEDE 使用 `master` 源码和 `openwrt-24.10` LuCI。官方源码构建使用 `v25.12.6` 标签指定的上游 feeds。构建时为 Edge 的 Lua 模板应用 LuCI 兼容补丁，并校验 `luci-compat`、`luci-lua-runtime` 和 `ucode-mod-lua`。固件也内置 Bootstrap 备用主题。

Actions 产物的 `metadata/` 目录保存 `build.config`、`feeds.conf.default`、固件软件包清单、`source-versions.txt` 和 `openclash-core-version.txt`，方便核对实际构建配置和版本。Release 只附带固件镜像和对应的 `SHA256SUMS`。完整 OpenWrt 源码由 Actions 在构建时克隆。

工作流在 `make defconfig` 后检查必需配置，编译后检查 BIOS/UEFI 镜像、gzip 完整性和固件 manifest。实机验收还需确认 WAN、LAN DHCP、IPv4 NAT、IPv6 PD/RA/DHCPv6、AAAA 解析、防火墙、主题和各代理分别运行。编译或镜像校验失败时，Actions 保留诊断日志并跳过 Release 发布。

ESXi 三套固件都包含 VMXNET3 网卡驱动。将与虚拟机固件模式匹配的磁盘镜像解压，再转换为 ESXi 可挂载的 VMDK。UEFI 选择 `*-combined-efi.img.gz`，并关闭 Secure Boot。Legacy BIOS 选择 `*-combined.img.gz`。

默认情况下，三套方案都会把 LAN IP 改为 `192.168.2.1`，将 LuCI 默认语言设置为简体中文，并将默认主题设置为 `edge`。

## 已包含功能

- 支持推送到 `main` 时自动编译，也可手动触发
- 支持 `dl` 和 `ccache` 缓存
- 自动上传编译产物
- 编译及校验成功后默认创建 GitHub Release（可手动关闭）
- 支持通过脚本切换主题和常用插件

## 构建兼容性

- 各配置使用 LuCI 提供的 `luci-app-filemanager`。
- 清理 SSR-Plus 上游已移除的旧配置开关。Hysteria、TUIC 等核心仍通过独立软件包选择，具体协议支持以 SSR-Plus 界面提供的选项为准。
- LEDE 的 gettext 0.22.5 使用固定的 gnulib `c99c8d491850dc3a6e0b8604a2729d8bc5c0eff1`（24.10 基线）。gettext 0.24.2 等其他版本使用上游源码指定的 gnulib。工作流先构建 gettext 主机工具，提前发现兼容问题。
- LEDE 为 elfutils 补齐 Bison/Flex 构建依赖，确保解析器生成工具及数据安装完成后再编译。工具预编译遵守 `compile_threads`；并行失败时单线程重试。
- 三套工作流分别恢复缓存。Git tag 和 Release 标题使用发布时的北京时间，格式为 `方案名-YYYYMMDD-HHMMSS`。构建编号可从 Release 正文中的 Actions 链接查到。
- 固件清单检查 PPPoE、IPv6、VMXNET3、常用 LuCI 应用、firewall4、代理核心和透明代理所需的内核模块，以及已移除的主题和服务。每种已生成的根文件系统都需配有 BIOS 和 UEFI 两种引导镜像。
- `make defconfig` 后逐项比对输入配置中明确选择的软件包及其选项；上游移除或改名时立即报错，避免带着缺失功能继续编译。

源码和 feeds 的移动分支仍会随上游变化；配置检查、编译成功和镜像校验不能替代硬件启动及联网测试。每次更换源码分支后仍应核验主题页面、WAN/PPPoE、IPv6 和各代理的实际运行。

## 扩展建议

- 新增机型时，可以在 `config/` 下添加新的 `.config` 文件。
- 切换源码仓库或分支时，可以直接在工作流输入参数中修改。
- 如果后续需要多机型并行编译，可以继续扩展 matrix 构建。
