#!/usr/bin/env bash
# =============================================================================
# Gomid 环境自动搭建脚本 (WSL / Ubuntu)
# 支持断点续建：已完成的步骤自动跳过，不会重复操作
# =============================================================================

set -euo pipefail

# ── 颜色定义 ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✔ $1${NC}"; }
skip() { echo -e "${YELLOW}  ↷ 跳过: $1${NC}"; }
info() { echo -e "${BLUE}  → $1${NC}"; }
err()  { echo -e "${RED}  ✘ 错误: $1${NC}"; exit 1; }

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      Gomid 环境搭建脚本 (WSL/Ubuntu)     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── 配置变量（按需修改）────────────────────────────────────────────────────────
GO_VERSION="1.22.1"
GO_ARCH="linux-amd64"
GO_TARBALL="go${GO_VERSION}.${GO_ARCH}.tar.gz"
GO_DOWNLOAD_URL="https://dl.google.com/go/${GO_TARBALL}"
GO_INSTALL_DIR="/usr/local/go"

GOMID_REPO="git@10.110.80.44:platform/gomid.git"
WORKSPACE_DIR="$HOME/workspace"   # 项目根目录，可按需修改
GOMID_DIR="$WORKSPACE_DIR/gomid"
SAMPLE_PROTO="gomid/testdata/proto/sample.proto"
SAMPLE_PACKAGE="git.joint520.com/demo/sample"

# ── 工具函数 ──────────────────────────────────────────────────────────────────
command_exists() { command -v "$1" &>/dev/null; }

reload_path() {
  export PATH=$PATH:/usr/local/go/bin
  export GOPATH=$HOME/go
  export PATH=$PATH:$GOPATH/bin
}

# =============================================================================
# STEP 0: 基础工具检查与安装
# =============================================================================
echo -e "\n${BLUE}[STEP 0] 检查基础依赖工具${NC}"

MISSING_PKGS=()
for pkg in git curl wget make gcc build-essential protobuf-compiler; do
  if ! dpkg -s "$pkg" &>/dev/null 2>&1; then
    MISSING_PKGS+=("$pkg")
  fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
  info "安装缺失的基础包: ${MISSING_PKGS[*]}"
  sudo apt update -qq
  sudo apt install -y "${MISSING_PKGS[@]}"
  ok "基础工具安装完毕"
else
  skip "基础工具已全部就绪"
fi

# =============================================================================
# STEP 1: 安装 Go
# =============================================================================
echo -e "\n${BLUE}[STEP 1] 检查 Go 安装${NC}"

reload_path

if command_exists go; then
  CURRENT_GO=$(go version | awk '{print $3}' | sed 's/go//')
  skip "Go 已安装，版本: $CURRENT_GO（需要 ${GO_VERSION}+，如需升级请手动执行）"
else
  info "未检测到 Go，开始安装 Go ${GO_VERSION}..."

  if [ ! -f "/tmp/${GO_TARBALL}" ]; then
    info "下载 ${GO_TARBALL}..."
    wget -q --show-progress -O "/tmp/${GO_TARBALL}" "${GO_DOWNLOAD_URL}"
  else
    skip "安装包已存在，跳过下载"
  fi

  sudo rm -rf "${GO_INSTALL_DIR}"
  sudo tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
  ok "Go ${GO_VERSION} 解压完毕"

  # 写入 PATH（幂等：先检查是否已存在）
  BASHRC="$HOME/.bashrc"
  if ! grep -q 'export PATH=\$PATH:/usr/local/go/bin' "$BASHRC"; then
    {
      echo ''
      echo '# Go environment'
      echo 'export PATH=$PATH:/usr/local/go/bin'
      echo 'export GOPATH=$HOME/go'
      echo 'export PATH=$PATH:$GOPATH/bin'
    } >> "$BASHRC"
    ok "PATH 已写入 ~/.bashrc"
  else
    skip "PATH 已在 ~/.bashrc 中配置"
  fi

  reload_path
  command_exists go || err "Go 安装后仍无法找到，请检查 PATH"
  ok "Go 安装成功: $(go version)"
fi

# =============================================================================
# STEP 2: 检查 SSH Key（用于 clone 私有仓库）
# =============================================================================
echo -e "\n${BLUE}[STEP 2] 检查 SSH Key${NC}"

if [ -f "$HOME/.ssh/id_rsa.pub" ] || [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
  skip "SSH Key 已存在"
else
  info "未检测到 SSH Key，自动生成..."
  echo -e "${YELLOW}  请输入你的邮箱地址（用于 SSH Key 注释）:${NC}"
  read -r USER_EMAIL
  ssh-keygen -t ed25519 -C "$USER_EMAIL" -f "$HOME/.ssh/id_ed25519" -N ""
  ok "SSH Key 生成完毕"
  echo ""
  echo -e "${YELLOW}  ⚠️  请将以下公钥添加到 GitLab (10.110.80.44) 的 SSH Keys 中:${NC}"
  echo ""
  cat "$HOME/.ssh/id_ed25519.pub"
  echo ""
  echo -e "${YELLOW}  添加完毕后按 Enter 继续...${NC}"
  read -r
fi

# =============================================================================
# STEP 3: Clone gomid 仓库
# =============================================================================
echo -e "\n${BLUE}[STEP 3] 检查 gomid 仓库${NC}"

mkdir -p "$WORKSPACE_DIR"

if [ -d "$GOMID_DIR/.git" ]; then
  skip "gomid 仓库已存在: $GOMID_DIR"
else
  info "克隆 gomid 仓库到 $GOMID_DIR ..."
  git clone "$GOMID_REPO" "$GOMID_DIR" || err "克隆失败，请确认 SSH Key 已添加到 GitLab"
  ok "gomid 克隆完毕"
fi

# =============================================================================
# STEP 4: make setup
# =============================================================================
echo -e "\n${BLUE}[STEP 4] 检查 make setup 完成状态${NC}"

SETUP_TOOLS=(protoc-gen-go protoc-gen-gogo mockery goimports nats-server)
MISSING_TOOLS=()
for tool in "${SETUP_TOOLS[@]}"; do
  command_exists "$tool" || MISSING_TOOLS+=("$tool")
done

if [ ${#MISSING_TOOLS[@]} -eq 0 ]; then
  skip "make setup 所需工具均已安装"
else
  info "缺少工具: ${MISSING_TOOLS[*]}，执行 make setup..."
  cd "$GOMID_DIR"
  make setup
  ok "make setup 完成"
fi

# =============================================================================
# STEP 5: 创建 proto include 路径
# =============================================================================
echo -e "\n${BLUE}[STEP 5] 检查 proto include 路径${NC}"

PROTO_API_DST="/usr/local/include/google/api"

if [ -d "$PROTO_API_DST" ]; then
  skip "proto include 路径已存在: $PROTO_API_DST"
else
  info "创建 proto include 路径..."
  sudo mkdir -p /usr/local/include/google

  # 动态查找 grpc-gateway 路径（不依赖硬编码用户名）
  GW_PATH=$(find "$(go env GOPATH)/pkg/mod/github.com/grpc-ecosystem" \
    -maxdepth 1 -name 'grpc-gateway@*' 2>/dev/null | sort -V | tail -1)

  if [ -z "$GW_PATH" ]; then
    err "未找到 grpc-gateway 模块，请先完成 make setup (STEP 4)"
  fi

  sudo cp -r "${GW_PATH}/third_party/googleapis/google/api" /usr/local/include/google/
  ok "proto include 路径创建完毕: $PROTO_API_DST"
fi

# =============================================================================
# STEP 6: 配置 go env 私有仓库
# =============================================================================
echo -e "\n${BLUE}[STEP 6] 检查 go env 私有仓库配置${NC}"

CURRENT_GONOSUMDB=$(go env GONOSUMDB 2>/dev/null || echo "")
CURRENT_GOPRIVATE=$(go env GOPRIVATE 2>/dev/null || echo "")

if echo "$CURRENT_GONOSUMDB" | grep -q "git.joint520.com"; then
  skip "GONOSUMDB 已配置"
else
  go env -w GONOSUMDB=git.joint520.com
  ok "GONOSUMDB 设置完毕"
fi

if echo "$CURRENT_GOPRIVATE" | grep -q "git.joint520.com"; then
  skip "GOPRIVATE 已配置"
else
  go env -w GOPRIVATE=git.joint520.com
  ok "GOPRIVATE 设置完毕"
fi

# =============================================================================
# STEP 7: make（编译 gomid）
# =============================================================================
echo -e "\n${BLUE}[STEP 7] 编译 gomid${NC}"

GOMID_BIN="$GOMID_DIR/bin"
if [ -d "$GOMID_BIN" ] && [ "$(ls -A "$GOMID_BIN" 2>/dev/null)" ]; then
  skip "gomid 已编译（bin 目录非空），跳过 make"
else
  info "执行 go mod tidy + make..."
  cd "$GOMID_DIR"
  go mod tidy
  make
  ok "gomid 编译完毕"
fi

# =============================================================================
# STEP 8: 生成 sample 工程
# =============================================================================
echo -e "\n${BLUE}[STEP 8] 检查 sample 工程${NC}"

SAMPLE_DIR="$WORKSPACE_DIR/sample"
GOGEN="$GOMID_DIR/3rd_party/gogen/gogen_linux_amd64"

if [ -d "$SAMPLE_DIR" ]; then
  skip "sample 工程已存在: $SAMPLE_DIR"
else
  if [ ! -f "$GOGEN" ]; then
    err "未找到 gogen 工具: $GOGEN，请确认 STEP 7 编译成功"
  fi
  info "生成 sample 工程..."
  cd "$WORKSPACE_DIR"
  "$GOGEN" create --type http "$SAMPLE_PACKAGE" "$SAMPLE_PROTO"
  ok "sample 工程生成完毕"
fi

# =============================================================================
# STEP 9: 生成 go.work
# =============================================================================
echo -e "\n${BLUE}[STEP 9] 检查 go.work 文件${NC}"

GOWORK_FILE="$WORKSPACE_DIR/go.work"

if [ -f "$GOWORK_FILE" ]; then
  if grep -q "gomid" "$GOWORK_FILE" && grep -q "sample" "$GOWORK_FILE"; then
    skip "go.work 已配置完毕"
  else
    info "go.work 存在但条目不完整，追加缺失条目..."
    cd "$WORKSPACE_DIR"
    grep -q "gomid"  "$GOWORK_FILE" || go work use gomid
    grep -q "sample" "$GOWORK_FILE" || go work use sample
    ok "go.work 更新完毕"
  fi
else
  info "生成 go.work..."
  cd "$WORKSPACE_DIR"
  go work init
  go work use gomid
  go work use sample
  ok "go.work 生成完毕"
fi

# =============================================================================
# 完成汇总
# =============================================================================
echo ""
echo -e "${GREEN}╔════════════════════��═════════════════════╗${NC}"
echo -e "${GREEN}║          🎉 所有步骤执行完毕！           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  工作目录: ${BLUE}$WORKSPACE_DIR${NC}"
echo -e "  运行示例:"
echo -e "    ${YELLOW}cd $SAMPLE_DIR && make run${NC}"
echo ""
echo -e "  ARM 交叉编译（可选）:"
echo -e "    ${YELLOW}GOARCH=arm GOOS=linux go build -o ./bin/sample ./cmd/sample${NC}"
echo ""
echo -e "  更新 proto（可选）:"
echo -e "    ${YELLOW}cd $SAMPLE_DIR && $GOGEN update${NC}"
echo ""
