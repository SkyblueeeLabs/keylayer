#!/bin/bash
# fix-permissions.sh — 一次性修复 KeyLayer 的辅助功能 / 输入监控授权
# 必须在你自己的「终端」里运行：bash fix-permissions.sh
# 作用：清掉绑定旧签名的失效授权记录，改用稳定的自签名证书，之后不再反复失效。
set -uo pipefail
cd "$(dirname "$0")/.."

APP="KeyLayer.app"
BUNDLE="com.skyblueee.keylayer"
CERT="KeyLayer Local Dev"

echo "[1/5] 退出正在运行的 KeyLayer"
pkill -x KeyLayer 2>/dev/null || true
# 改名前的旧进程，一并清掉，避免两个实例同时挂钩子
pkill -x KeyMapMac 2>/dev/null || true
sleep 1

echo "[2/5] 清空失效的旧授权记录"
tccutil reset Accessibility "$BUNDLE" 2>&1 || echo "  (辅助功能：无记录或已清)"
tccutil reset ListenEvent "$BUNDLE" 2>&1 || echo "  (输入监控：无记录或已清)"

echo "[3/5] 创建稳定的自签名证书（只需一次）"
if security find-certificate -c "$CERT" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
    echo "  证书已存在，跳过"
else
    TMP="$(mktemp -d)"
    cat > "$TMP/openssl.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = KeyLayer Local Dev
[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
    openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
        -config "$TMP/openssl.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >/dev/null 2>&1
    # OpenSSL 3 默认加密格式 macOS 钥匙串不认，必须用 legacy 或 3DES/sha1
    if ! openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
        -out "$TMP/cert.p12" -passout pass:keylayer-local >/dev/null 2>&1; then
        openssl pkcs12 -export -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
            -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
            -out "$TMP/cert.p12" -passout pass:keylayer-local
    fi
    security import "$TMP/cert.p12" \
        -k "$HOME/Library/Keychains/login.keychain-db" \
        -P keylayer-local -T /usr/bin/codesign -A
    rm -rf "$TMP"
    echo "  证书已创建（首次可能弹钥匙串授权，点「始终允许」）"
fi

echo "[4/5] 用稳定证书重签 App"
if codesign --force --deep --sign "$CERT" "$APP" 2>/dev/null; then
    echo "  重签完成，新的签名要求："
    codesign -dr - "$APP" 2>&1 | tail -1
else
    echo "  [警告] 证书签名失败，保持现有 ad-hoc 签名继续"
fi

echo "[5/5] 从当前终端启动 App"
open "$APP"

echo ""
echo "现在只需做最后一次授权："
echo "  系统设置 → 隐私与安全性 → 设备控制与数据访问 → 勾选 KeyLayer"
echo "  系统设置 → 隐私与安全性 → 输入监控 → 勾选 KeyLayer"
echo "  弹窗选「退出并重新打开」"
echo ""
echo "完成后状态灯应变绿。若仍不绿，把 KeyLayer.runtime.log 最后几行发我。"
