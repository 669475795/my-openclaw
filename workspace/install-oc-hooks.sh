#!/bin/bash
#
# OpenClaw 安全操作钩子 - 安装脚本
# 在 .bashrc 中添加安全包装函数
#

HOOK_MARKER="# === OpenClaw Safety Hooks ==="

# 要添加的钩子代码
read -r -d '' HOOK_CODE << 'EOF'

# === OpenClaw Safety Hooks ===
# 在更新或重大改动前自动备份配置

# 配置备份目录
export OPENCLAW_BACKUP_DIR="${HOME}/.config/openclaw-backups"

# 自动备份函数
_oc_auto_backup() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_name="openclaw_backup_${timestamp}"
    local backup_path="${OPENCLAW_BACKUP_DIR}/${backup_name}.tar.gz"
    
    mkdir -p "$OPENCLAW_BACKUP_DIR"
    
    echo "[oc-hook] 自动备份配置到: ${backup_name}.tar.gz"
    
    tar -czf "$backup_path" \
        --exclude='logs/*' \
        --exclude='*.log' \
        --exclude='delivery-queue/*' \
        -C "$(dirname ~/.config/openclaw)" \
        "$(basename ~/.config/openclaw)" 2>/dev/null
    
    echo "$backup_path"
}

# 安全更新 OpenClaw
oc-update() {
    echo "[oc-hook] 🔄 准备安全更新 OpenClaw..."
    local backup=$(_oc_auto_backup)
    
    echo "[oc-hook] 执行 npm update..."
    if npm update -g openclaw; then
        echo "[oc-hook] ✅ 更新成功！"
        echo "[oc-hook] 📦 备份位置: $backup"
        echo "[oc-hook] 如需回退: npm install -g openclaw@<旧版本号>"
    else
        echo "[oc-hook] ❌ 更新失败！配置未改动"
        return 1
    fi
}

# 安全安装指定版本
oc-install-version() {
    local version="$1"
    if [ -z "$version" ]; then
        echo "用法: oc-install-version <版本号>"
        echo "示例: oc-install-version 2026.2.20"
        return 1
    fi
    
    echo "[oc-hook] 🔄 准备安装 OpenClaw v${version}..."
    local backup=$(_oc_auto_backup)
    
    echo "[oc-hook] 执行 npm install..."
    if npm install -g "openclaw@${version}"; then
        echo "[oc-hook] ✅ 安装成功！"
        echo "[oc-hook] 📦 备份位置: $backup"
    else
        echo "[oc-hook] ❌ 安装失败！"
        return 1
    fi
}

# 安全设置配置
oc-config-set() {
    local key="$1"
    local value="$2"
    
    if [ -z "$key" ] || [ -z "$value" ]; then
        echo "用法: oc-config-set <key> <value>"
        return 1
    fi
    
    echo "[oc-hook] 🔄 准备设置配置: $key = $value"
    local backup=$(_oc_auto_backup)
    
    echo "[oc-hook] 执行配置修改..."
    if openclaw config set "$key" "$value"; then
        echo "[oc-hook] ✅ 配置修改成功！"
        echo "[oc-hook] 📦 备份位置: $backup"
    else
        echo "[oc-hook] ❌ 配置修改失败！"
        return 1
    fi
}

# 安全修改配置文件
oc-edit-config() {
    local config_file="${HOME}/.config/openclaw/openclaw.json"
    
    echo "[oc-hook] 📝 准备编辑配置文件..."
    local backup=$(_oc_auto_backup)
    
    echo "[oc-hook] 使用默认编辑器打开..."
    ${EDITOR:-nano} "$config_file"
    
    echo "[oc-hook] ✅ 编辑完成"
    echo "[oc-hook] 📦 备份位置: $backup"
    echo "[oc-hook] 如需恢复: cp ${backup} ~/.config/openclaw/"
}

# 列出所有备份
oc-backup-list() {
    local backup_dir="${HOME}/.config/openclaw-backups"
    
    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A $backup_dir/*.tar.gz 2>/dev/null)" ]; then
        echo "[oc-hook] 暂无备份"
        return 0
    fi
    
    echo "[oc-hook] 可用备份列表:"
    echo
    
    for backup in "$backup_dir"/openclaw_backup_*.tar.gz; do
        [ -f "$backup" ] || continue
        local name=$(basename "$backup" .tar.gz)
        local date=$(stat -c %y "$backup" 2>/dev/null || stat -f %Sm "$backup" 2>/dev/null)
        local size=$(du -h "$backup" | cut -f1)
        printf "  %-35s %8s\n" "$name" "$size"
    done
}

# 恢复指定备份
oc-restore() {
    local backup_name="$1"
    local backup_dir="${HOME}/.config/openclaw-backups"
    
    if [ -z "$backup_name" ]; then
        echo "用法: oc-restore <备份名>"
        echo "可用备份:"
        oc-backup-list
        return 1
    fi
    
    local backup_path="${backup_dir}/${backup_name}.tar.gz"
    
    if [ ! -f "$backup_path" ]; then
        echo "[oc-hook] ❌ 备份不存在: $backup_name"
        echo "[oc-hook] 可用备份:"
        oc-backup-list
        return 1
    fi
    
    echo "[oc-hook] ⚠️  即将恢复备份: $backup_name"
    read -p "[oc-hook] 确定要覆盖当前配置吗？当前配置将被备份 [y/N] " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "[oc-hook] 操作已取消"
        return 0
    fi
    
    # 先备份当前
    echo "[oc-hook] 备份当前配置..."
    _oc_auto_backup > /dev/null
    
    # 停止服务
    echo "[oc-hook] 停止 OpenClaw 服务..."
    openclaw gateway stop 2>/dev/null || true
    
    # 恢复
    echo "[oc-hook] 恢复配置..."
    rm -rf ~/.config/openclaw
    tar -xzf "$backup_path" -C "$(dirname ~/.config/openclaw)"
    
    echo "[oc-hook] ✅ 恢复完成！"
    echo "[oc-hook] 请手动启动服务: openclaw gateway start"
}

# 清理旧备份
oc-backup-cleanup() {
    local days="${1:-30}"
    local backup_dir="${HOME}/.config/openclaw-backups"
    
    echo "[oc-hook] 清理 ${days} 天前的备份..."
    
    local count=0
    find "$backup_dir" -name "openclaw_backup_*.tar.gz" -mtime +$days -print0 2>/dev/null | \
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((count++))
    done
    
    echo "[oc-hook] 清理完成"
}

# 显示帮助
oc-help() {
    cat << 'HELP'
OpenClaw 安全操作命令:

  oc-update              安全更新到最新版本
  oc-install-version X   安装指定版本
  oc-config-set K V      安全设置配置项
  oc-edit-config         安全编辑配置文件
  oc-backup-list         列出所有备份
  oc-restore NAME        恢复到指定备份
  oc-backup-cleanup [N]  清理N天前的备份 (默认30天)

这些命令会在操作前自动备份配置，出问题时可以恢复。
HELP
}

# === End of OpenClaw Safety Hooks ===
EOF

# 安装函数
install_hooks() {
    local shell_rc=""
    
    # 检测当前 shell
    if [ -n "$BASH_VERSION" ]; then
        shell_rc="$HOME/.bashrc"
    elif [ -n "$ZSH_VERSION" ]; then
        shell_rc="$HOME/.zshrc"
    else
        # 默认尝试 bashrc
        shell_rc="$HOME/.bashrc"
    fi
    
    echo "检测到 shell: ${shell_rc##*/}"
    
    # 检查是否已安装
    if grep -q "$HOOK_MARKER" "$shell_rc" 2>/dev/null; then
        echo "钩子已安装，是否更新？"
        read -p "[y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "已取消"
            return 0
        fi
        # 删除旧版本
        sed -i "/$HOOK_MARKER/,/End of OpenClaw Safety Hooks/d" "$shell_rc"
    fi
    
    # 追加钩子代码
    echo "$HOOK_CODE" >> "$shell_rc"
    
    echo "✅ 钩子已安装到 $shell_rc"
    echo ""
    echo "请运行以下命令使其生效:"
    echo "  source $shell_rc"
    echo ""
    echo "安装后可用命令:"
    echo "  oc-update, oc-config-set, oc-edit-config, oc-restore 等"
    echo ""
    echo "查看完整帮助:"
    echo "  oc-help"
}

# 卸载函数
uninstall_hooks() {
    local shell_rc=""
    
    if [ -n "$BASH_VERSION" ]; then
        shell_rc="$HOME/.bashrc"
    elif [ -n "$ZSH_VERSION" ]; then
        shell_rc="$HOME/.zshrc"
    else
        shell_rc="$HOME/.bashrc"
    fi
    
    if ! grep -q "$HOOK_MARKER" "$shell_rc" 2>/dev/null; then
        echo "钩子未安装"
        return 0
    fi
    
    echo "确定要卸载 OpenClaw 安全钩子吗？"
    read -p "[y/N] " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "已取消"
        return 0
    fi
    
    # 删除钩子代码
    sed -i "/$HOOK_MARKER/,/End of OpenClaw Safety Hooks/d" "$shell_rc"
    
    echo "✅ 钩子已卸载"
    echo "请运行: source $shell_rc"
}

# 主逻辑
case "${1:-install}" in
    install)
        install_hooks
        ;;
    uninstall)
        uninstall_hooks
        ;;
    *)
        echo "用法: $0 [install|uninstall]"
        exit 1
        ;;
esac
