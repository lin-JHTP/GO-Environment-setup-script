# Gomid Go 环境搭建脚本

> 适用平台：WSL / Ubuntu
> 支持断点续建：已完成的步骤自动跳过，不会产生重复操作

---

## ⚠️ 适用范围说明

此脚本**不是通用的 Go 环境搭建脚本**，它是专门为 `gomid` 私有工程设计的一键部署脚本。

| 步骤 | 通用 Go 项目 | 本脚本（gomid 专用）|
|------|:-----------:|:------------------:|
| 安装 Go 运行时 | ✅ | ✅ |
| 配置 PATH / GOPATH | ✅ | ✅ |
| 安装 protobuf 工具链（protoc-gen-go 等）| ❌ | ✅ |
| 克隆 gomid 私有仓库 | ❌ | ✅ |
| 配置私有域名 GOPRIVATE | ❌ | ✅ |
| 创建 /usr/local/include/google proto 路径 | ❌ | ✅ |
| 生成 sample 工程 & go.work | ❌ | ✅ |

> 如果你只需要运行普通 Go 项目，只需完成 **STEP 0 ~ STEP 1**（安装 Go + 配置 PATH）即可。

---

## 🚀 使用方式

```bash
# 1. 赋予执行权限
chmod +x setup_gomid.sh

# 2. 运行脚本（已完成的步骤会自动跳过）
./setup_gomid.sh
```

---

## 📋 脚本执行步骤

| 步骤 | 内容 | 检测方式（断点续建）|
|------|------|--------------------|
| STEP 0 | 安装基础依赖（git、curl、make、protobuf 等）| `dpkg -s` 检查包是否已安装 |
| STEP 1 | 安装 Go 1.22.1，配置 PATH | `command -v go` |
| STEP 2 | 生成 SSH Key 用于克隆私有仓库 | `~/.ssh/id_*.pub` 是否存在 |
| STEP 3 | 克隆 gomid 仓库 | `gomid/.git` 目录是否存在 |
| STEP 4 | `make setup` 安装工具链 | 检测各工具是否在 PATH 中 |
| STEP 5 | 创建 proto include 路径 | `/usr/local/include/google/api` 是否存在 |
| STEP 6 | 配置 GOPRIVATE / GONOSUMDB | `go env` 检查当前值 |
| STEP 7 | `go mod tidy` + `make` 编译 | `bin/` 目录是否非空 |
| STEP 8 | 生成 sample 工程 | `sample/` 目录是否存在 |
| STEP 9 | 生成 go.work 多模块工作区 | `go.work` 是否存在且包含两个条目 |

---

## 📝 原始搭建文档中的已知问题修复

1. **PATH 未配置**：手动安装 Go 后补充写入 `~/.bashrc`
2. **GOPRIVATE 路径错误**：移除错误拼接的本地文件路径，只保留域名
3. **SSH Key 未提及**：脚本自动检测并引导生成
4. **硬编码用户名路径**：改用 `$(go env GOPATH)` + `find` 动态获取
5. **go.work 时序问题**：调整为在 sample 工程生成后才创建 go.work
6. **缺少 protoc 安装说明**：在 STEP 0 中自动安装 `protobuf-compiler`

---

## 💡 WSL 使用注意事项

- **请将项目放在 Linux 文件系统下**（`~/workspace/`），不要放在 `/mnt/c/...`（Windows 盘），否则 I/O 速度会极慢
- 脚本默认工作目录为 `~/workspace`，可在脚本顶部 `WORKSPACE_DIR` 变量处修改
- 首次运行后执行 `source ~/.bashrc` 或重新打开终端使 PATH 生效
