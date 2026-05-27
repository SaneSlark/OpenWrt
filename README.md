# GitHub 自动编译 OpenWrt

这是一个基于 GitHub Actions 的 OpenWrt 自动编译框架，用来集中管理编译配置、自定义脚本和固件产物。

当前仓库保留两套 x86_64 构建方案：

- `OpenWrt lede Build`：基于 `coolsnowwolf/lede`，优先保证经典 LEDE 固件稳定产出。
- `OpenWrt Immortal Build`：基于 `immortalwrt/immortalwrt`，用于较新的代理插件和最新固件。

## 目录结构

```text
.
|-- .github/workflows/build-lede.yml
|-- .github/workflows/build-immortal.yml
|-- config/
|   |-- lede_x86_64.config
|   `-- immortal_x86_64.config
`-- scripts/
    |-- diy-lede.sh
    `-- diy-immortal.sh
```

## 使用方法

1. 将当前仓库推送到 GitHub。
2. 打开仓库的 `Actions` 页面。
3. 根据需要运行 `OpenWrt lede Build` 或 `OpenWrt Immortal Build`。
4. 按需填写以下参数：
   - `repo_url`：OpenWrt 源码仓库地址
   - `repo_branch`：源码分支
   - `config_file`：当前仓库中的配置文件路径
   - `script_file`：当前仓库中的自定义脚本路径
   - `artifact_name`：上传后的产物名称
   - `compile_threads`：编译线程数，`0` 表示自动使用全部 CPU
   - `upload_release`：是否同时创建 GitHub Release

## 默认入口

LEDE 构建：

- 默认源码：`https://github.com/coolsnowwolf/lede`
- 默认分支：`master`
- 默认配置：`config/lede_x86_64.config`
- 默认脚本：`scripts/diy-lede.sh`

ImmortalWrt 构建：

- 默认源码：`https://github.com/immortalwrt/immortalwrt`
- 默认分支：`openwrt-24.10`
- 默认配置：`config/immortal_x86_64.config`
- 默认脚本：`scripts/diy-immortal.sh`

两个脚本都支持两个执行阶段：

- `STAGE=pre`：添加 feeds、主题和额外插件
- `STAGE=post`：在复制 `.config` 之后修改默认配置

## 主题与插件说明

LEDE 方案默认启用 `luci-theme-edge`、常用 LuCI 应用、`SSR-Plus`、`PassWall2` 和基础命令行工具。

ImmortalWrt 方案默认启用 `luci-theme-edge`、`SSR-Plus`、`PassWall2`、`HomeProxy` 和 `Nikki`。

默认情况下，两个方案都会把 LAN IP 改为 `192.168.2.1`，将 LuCI 默认语言设置为简体中文，并将默认主题设置为 `edge`。

## 已包含功能

- 支持手动触发编译
- LEDE workflow 支持 `repository_dispatch` 触发
- 支持 `dl` 和 `ccache` 缓存
- 自动上传编译产物
- 可选自动创建 GitHub Release
- 支持通过脚本切换主题和常用插件

## 扩展建议

- 新增机型时，可以在 `config/` 下添加新的 `.config` 文件。
- 切换源码仓库或分支时，可以直接在工作流输入参数中修改。
- 如果后续需要多机型并行编译，可以继续扩展 matrix 构建。
