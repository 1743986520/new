# 建立腳本檔案
cat > /tmp/deploy-frp.sh << 'EOF'
#!/bin/bash
set -e

echo "=================================================="
echo "🚀 帝acg.xyz 免費 Frp 公網穿透服務 - 一鍵部署"
echo "💝 由 善良的人的遊戲庫 提供"
echo "=================================================="

# 檢查是否為 root
if [ "$EUID" -ne 0 ]; then
    echo "❌ 請用 root 權限執行"
    exit 1
fi

# 自動偵測系統並安裝必要套件（Docker + Compose + UFW）
install_dependencies() {
    echo "🔧 偵測系統並安裝依賴..."
    apt-get update -y
    apt-get install -y curl wget ca-certificates gnupg lsb-release tar ufw

    # 安裝 Docker（官方方式）
    if ! command -v docker >/dev/null; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io
        systemctl enable --now docker
    fi

    # 安裝 Docker Compose（如果沒有）
    if ! command -v docker-compose >/dev/null; then
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "v\K[^"]*')
        curl -L "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi

    echo "✅ 依賴安裝完成"
}

# 建立目錄
setup_directories() {
    mkdir -p /opt/frp-public/web-content/{css,js}
    cd /opt/frp-public
    echo "✅ 目錄建立完成"
}

# 建立 Frp 伺服器配置 (frps.toml)
create_frps_config() {
    cat > frps.toml << 'EOF'
bindPort = 7000
subdomainHost = "t.帝acg.xyz"
vhostHTTPPort = 80
vhostHTTPSPort = 443

maxPortsPerClient = 5
maxPoolCount = 2

log.level = "error"
log.maxDays = 1

allowPorts = [
  { start = 10000, end = 30000 }
]

tcpMux = true
heartbeatTimeout = 180
EOF
    echo "✅ frps.toml 建立完成"
}

# 建立 Docker Compose 配置
create_docker_compose() {
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  frps:
    image: snowdreamtech/frps:latest
    container_name: frps-public
    volumes:
      - ./frps.toml:/etc/frp/frps.toml
    ports:
      - "7000:7000"
      - "80:80"
      - "443:443"
      - "10000-30000:10000-30000"
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.5'

  web-interface:
    image: nginx:alpine
    container_name: frp-web-interface
    ports:
      - "8080:80"
    volumes:
      - ./web-content:/usr/share/nginx/html
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 64M
          cpus: '0.2'
EOF
    echo "✅ docker-compose.yml 建立完成"
}

# 建立客戶端安裝腳本 (install.sh) - 完整版，從你的原始文件內嵌
create_install_script() {
    cat > web-content/install.sh << 'EOF'
#!/bin/bash

echo ""
echo "🎯 免費 Frp 內網穿透服務"
echo "========================================"
echo "💝 由 善良的人的遊戲庫 提供"
echo "🌐 主站: https://帝acg.xyz"
echo "========================================"

# 從參數獲取配置
TUNNEL_NAME="$1"
TUNNEL_TYPE="$2"
LOCAL_PORT="$3"
LOCAL_IP="${4:-127.0.0.1}"
REMOTE_PORT="$5"

# 伺服器配置
FRP_SERVER="2001:19f0:6001:36e:5400:2ff:feb1:bbae"
FRP_SERVER_PORT="7000"

# 驗證輸入
if [ -z "$TUNNEL_NAME" ] || [ -z "$TUNNEL_TYPE" ] || [ -z "$LOCAL_PORT" ]; then
    echo "❌ 錯誤: 參數不完整"
    echo "📖 使用方法:"
    echo "  curl -fsSL http://你的伺服器IP:8080/install.sh | bash -s -- 隧道名 類型 本地端口 [本地IP] [遠端端口]"
    echo ""
    echo "🎯 示例:"
    echo "  # HTTP網站"
    echo "  bash -s -- \"myweb\" \"http\" \"80\""
    echo "  # SSH連接"  
    echo "  bash -s -- \"myssh\" \"tcp\" \"22\" \"127.0.0.1\""
    exit 1
fi

echo "🔧 開始配置隧道..."
echo "✅ 隧道名稱: $TUNNEL_NAME"
echo "✅ 服務類型: $TUNNEL_TYPE"
echo "✅ 本地服務: ${LOCAL_IP}:${LOCAL_PORT}"

# 偵測系統架構
ARCH=$(uname -m)
case $ARCH in
    x86_64)   ARCH="amd64" ;;
    aarch64)  ARCH="arm64" ;;
    armv7l)   ARCH="arm" ;;
    armv6l)   ARCH="arm" ;;
    *)        echo "❌ 不支援的架構: $ARCH"; exit 1 ;;
esac

echo "✅ 系統架構: $ARCH"

# 建立臨時工作目錄
WORK_DIR="/tmp/frp-$$"
mkdir -p $WORK_DIR
cd $WORK_DIR

# 清理函數
cleanup() {
    echo "🧹 清理臨時文件..."
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# 下載 Frp - 使用多鏡像源
echo "⬇️ 下載 Frp 客戶端..."
FRP_VERSION="0.60.0"
DOWNLOAD_SUCCESS=0

# 鏡像源列表
MIRRORS=(
    "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
    "https://ghproxy.com/https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
    "https://download.fastgit.org/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
)

for mirror in "${MIRRORS[@]}"; do
    echo "嘗試從: $mirror"
    if wget --timeout=30 --tries=2 -O frp.tar.gz "$mirror"; then
        if tar -tzf frp.tar.gz >/dev/null 2>&1; then
            echo "✅ 下載並驗證成功"
            DOWNLOAD_SUCCESS=1
            break
        else
            echo "❌ 文件損壞，嘗試下一個鏡像..."
            rm -f frp.tar.gz
        fi
    else
        echo "❌ 下載失敗，嘗試下一個鏡像..."
    fi
done

if [ $DOWNLOAD_SUCCESS -ne 1 ]; then
    echo "❌ 所有鏡像下載失敗，請檢查網路連接"
    exit 1
fi

# 解壓文件
echo "📦 解壓文件..."
if ! tar -xzf frp.tar.gz; then
    echo "❌ 解壓失敗，文件可能損壞"
    exit 1
fi

# 查找 frpc 可執行文件
FRPC_PATH=$(find . -name "frpc" -type f | head -1)
if [ -z "$FRPC_PATH" ]; then
    echo "❌ 找不到 frpc 可執行文件"
    exit 1
fi

echo "✅ 找到 frpc: $FRPC_PATH"

# 設定執行權限
chmod +x "$FRPC_PATH"

# 生成配置
echo "⚙️ 生成配置文件..."
if [ "$TUNNEL_TYPE" = "http" ] || [ "$TUNNEL_TYPE" = "https" ]; then
    # HTTP/HTTPS 服務
    cat > frpc.toml << EOF
serverAddr = "[${FRP_SERVER}]"
serverPort = ${FRP_SERVER_PORT}

[[proxies]]
name = "${TUNNEL_NAME}-web"
type = "http"
localIP = "${LOCAL_IP}"
localPort = ${LOCAL_PORT}
customDomains = ["${TUNNEL_NAME}.t.帝acg.xyz"]
EOF
    ACCESS_INFO="🌐 訪問地址: http://${TUNNEL_NAME}.t.帝acg.xyz"
else
    # TCP 服務
    if [ -z "$REMOTE_PORT" ]; then
        REMOTE_PORT=$((10000 + RANDOM % 10000))
        echo "🎲 自動分配遠端端口: $REMOTE_PORT"
    fi
    
    cat > frpc.toml << EOF
serverAddr = "[${FRP_SERVER}]"
serverPort = ${FRP_SERVER_PORT}

[[proxies]]
name = "${TUNNEL_NAME}-tcp"
type = "tcp"
localIP = "${LOCAL_IP}"
localPort = ${LOCAL_PORT}
remotePort = ${REMOTE_PORT}
EOF
    
    if [ "$TUNNEL_TYPE" = "ssh" ]; then
        ACCESS_INFO="💻 SSH連接: ssh -p ${REMOTE_PORT} 你的用戶名@${TUNNEL_NAME}.t.帝acg.xyz"
    else
        ACCESS_INFO="🔌 TCP連接: ${TUNNEL_NAME}.t.帝acg.xyz:${REMOTE_PORT}"
    fi
fi

echo "📋 配置文件內容:"
cat frpc.toml

# 啟動 Frp 客戶端
echo "🚀 啟動 Frp 客戶端..."
"$FRPC_PATH" -c frpc.toml &

CLIENT_PID=$!
sleep 3

# 檢查是否啟動成功
if kill -0 $CLIENT_PID 2>/dev/null; then
    echo ""
    echo "========================================"
    echo "🎉 Frp 隧道啟動成功！"
    echo "========================================"
    echo "🔧 隧道名稱: $TUNNEL_NAME"
    echo "🔧 服務類型: $TUNNEL_TYPE"
    echo "🔧 本地服務: ${LOCAL_IP}:${LOCAL_PORT}"
    echo "🌐 $ACCESS_INFO"
    echo "========================================"
    echo "💡 提示:"
    echo "   • 按 Ctrl+C 停止隧道服務"
    echo "   • 關閉終端後隧道會自動停止"
    echo "   • 需要24小時運行請使用 systemd 服務"
    echo "========================================"
    echo "💝 感謝使用 善良的人的遊戲庫 提供的服務"
    echo "🌐 主站: https://帝acg.xyz"
    echo "========================================"
    
    # 等待用戶中斷
    wait $CLIENT_PID
else
    echo "❌ Frp 客戶端啟動失敗"
    echo "🔍 檢查日誌..."
    if [ -f "frpc.log" ]; then
        cat frpc.log
    fi
    exit 1
fi
EOF
    chmod +x web-content/install.sh
    echo "✅ install.sh 建立完成"
}

# 建立網頁介面 (index.html) - 完整版，從你的原始文件內嵌
create_web_interface() {
    cat > web-content/index.html << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🚀 免費內網穿透服務 - 善良的人的遊戲庫</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh; 
            color: #333;
            line-height: 1.6;
        }
        .container { max-width: 800px; margin: 0 auto; padding: 20px; }
        
        /* 導航欄 */
        .navbar {
            background: rgba(255, 255, 255, 0.95);
            padding: 1rem 0;
            margin-bottom: 2rem;
            border-radius: 10px;
        }
        .nav-container {
            max-width: 800px;
            margin: 0 auto;
            padding: 0 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .nav-logo {
            font-size: 1.5rem;
            font-weight: bold;
            color: #007cba;
        }
        .nav-link {
            text-decoration: none;
            color: #007cba;
            font-weight: 500;
            padding: 10px 20px;
            border: 2px solid #007cba;
            border-radius: 25px;
            transition: all 0.3s ease;
        }
        .nav-link:hover {
            background: #007cba;
            color: white;
        }
        
        /* 主內容 */
        .hero {
            background: white;
            border-radius: 15px;
            padding: 40px;
            text-align: center;
            margin-bottom: 2rem;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        .hero h1 {
            font-size: 2.5rem;
            margin-bottom: 1rem;
            background: linear-gradient(135deg, #007cba, #764ba2);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .hero-badge {
            display: inline-block;
            background: linear-gradient(135deg, #ff6b6b, #ee5a24);
            color: white;
            padding: 8px 16px;
            border-radius: 20px;
            font-weight: bold;
            margin-top: 1rem;
        }
        
        /* 配置表單 */
        .config-section {
            background: white;
            border-radius: 15px;
            padding: 30px;
            margin-bottom: 2rem;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        .form-group {
            margin-bottom: 1.5rem;
        }
        label {
            display: block;
            margin-bottom: 0.5rem;
            font-weight: bold;
        }
        input, select {
            width: 100%;
            padding: 12px;
            border: 2px solid #e1e5e9;
            border-radius: 8px;
            font-size: 16px;
        }
        input:focus, select:focus {
            border-color: #007cba;
            outline: none;
        }
        .form-hint {
            margin-top: 0.5rem;
            color: #666;
            font-size: 0.9rem;
        }
        .domain-preview {
            color: #007cba;
            font-weight: bold;
        }
        .generate-btn {
            width: 100%;
            background: linear-gradient(135deg, #007cba, #005a87);
            color: white;
            border: none;
            padding: 15px;
            border-radius: 8px;
            font-size: 1.1rem;
            font-weight: bold;
            cursor: pointer;
            transition: transform 0.3s ease;
        }
        .generate-btn:hover {
            transform: translateY(-2px);
        }
        
        /* 結果區域 */
        .result-section {
            background: white;
            border-radius: 15px;
            padding: 30px;
            margin-bottom: 2rem;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        .command-box {
            background: #1e1e1e;
            color: #00ff00;
            padding: 20px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            margin: 1rem 0;
            border: 2px solid #333;
        }
        .copy-btn {
            background: #28a745;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 6px;
            cursor: pointer;
            margin-top: 1rem;
        }
        .copy-btn:hover {
            background: #218838;
        }
        
        /* 頁腳 */
        .footer {
            text-align: center;
            color: white;
            margin-top: 3rem;
            padding: 2rem 0;
        }
        .footer a {
            color: white;
            text-decoration: none;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <!-- 導航欄 -->
    <nav class="navbar">
        <div class="nav-container">
            <div class="nav-logo">🚀 Frp 內網穿透</div>
            <a href="https://帝acg.xyz" class="nav-link">返回主站</a>
        </div>
    </nav>

    <div class="container">
        <!-- 頭部橫幅 -->
        <header class="hero">
            <h1>免費內網穿透服務</h1>
            <p>一條命令，讓本地服務擁有公網域名</p>
            <div class="hero-badge">由 善良的人的遊戲庫 提供</div>
        </header>

        <!-- 配置表單 -->
        <section class="config-section">
            <h2 style="margin-bottom: 1.5rem; text-align: center;">⚙️ 隧道配置</h2>
            
            <div class="form-group">
                <label for="tunnelName">隧道名稱（英文）</label>
                <input type="text" id="tunnelName" placeholder="例如: my-web, game-server" required>
                <div class="form-hint">域名預覽: <span id="domainPreview" class="domain-preview">輸入後顯示</span></div>
            </div>

            <div class="form-group">
                <label for="tunnelType">服務類型</label>
                <select id="tunnelType" required>
                    <option value="">-- 請選擇 --</option>
                    <option value="http">🌐 HTTP 網站</option>
                    <option value="https">🔒 HTTPS 網站</option>
                    <option value="ssh">💻 SSH 連接</option>
                    <option value="tcp">🔌 其他 TCP 服務</option>
                </select>
            </div>

            <div class="form-group">
                <label for="localPort">本地服務端口</label>
                <input type="number" id="localPort" placeholder="例如: 80, 22, 3000" required>
                <div class="form-hint">你的服務在本地運行的端口號</div>
            </div>

            <div class="form-group" id="remotePortGroup" style="display: none;">
                <label for="remotePort">遠端端口 (TCP服務專用)</label>
                <input type="number" id="remotePort" placeholder="留空自動分配">
            </div>

            <div class="form-group">
                <label for="localIp">本地服務IP地址</label>
                <input type="text" id="localIp" value="127.0.0.1" placeholder="默認 127.0.0.1">
            </div>

            <button class="generate-btn" onclick="generateCommand()">生成安裝命令</button>
        </section>

        <!-- 命令結果顯示 -->
        <section id="commandResult" class="result-section" style="display: none;">
            <h2 style="margin-bottom: 1.5rem; text-align: center;">📋 安裝命令</h2>
            
            <div class="command-box">
                <code id="commandOutput"></code>
            </div>
            
            <button class="copy-btn" onclick="copyCommand()">複製命令</button>
            
            <div style="margin-top: 1.5rem; padding: 1rem; background: #e7f3ff; border-radius: 8px;">
                <h4>🌐 訪問信息</h4>
                <p id="accessInfo" style="margin: 0.5rem 0;"></p>
                <p style="margin: 0.5rem 0; font-size: 0.9rem; color: #666;">
                    💡 在需要穿透的設備上執行上方命令，等待連接成功即可通過訪問地址使用。
                </p>
            </div>
        </section>

        <!-- 使用示例 -->
        <section class="config-section">
            <h2 style="margin-bottom: 1.5rem; text-align: center;">🎯 使用示例</h2>
            
            <div style="display: grid; gap: 1rem;">
                <div style="padding: 1rem; background: #f8f9fa; border-radius: 8px;">
                    <h4>🌐 網站服務</h4>
                    <code>curl -fsSL http://你的伺服器IP:8080/install.sh | bash -s -- "myblog" "http" "8080"</code>
                    <p style="margin-top: 0.5rem;">訪問: <strong>http://myblog.t.帝acg.xyz</strong></p>
                </div>
                
                <div style="padding: 1rem; background: #f8f9fa; border-radius: 8px;">
                    <h4>💻 SSH 連接</h4>
                    <code>curl -fsSL http://你的伺服器IP:8080/install.sh | bash -s -- "myssh" "tcp" "22"</code>
                    <p style="margin-top: 0.5rem;">連接: <strong>ssh -p 端口號 user@myssh.t.帝acg.xyz</strong></p>
                </div>
            </div>
        </section>
    </div>

    <!-- 頁腳 -->
    <footer class="footer">
        <p>💝 由 <strong>善良的人的遊戲庫</strong> 提供免費服務</p>
        <p><a href="https://帝acg.xyz">🌐 返回主網站: https://帝acg.xyz</a></p>
    </footer>

    <script>
        // 即時顯示域名預覽
        document.getElementById('tunnelName').addEventListener('input', function() {
            const name = this.value.trim();
            const preview = document.getElementById('domainPreview');
            if (name) {
                preview.textContent = `${name}.t.帝acg.xyz`;
            } else {
                preview.textContent = '輸入後顯示';
            }
        });

        // 顯示/隱藏遠端端口
        document.getElementById('tunnelType').addEventListener('change', function() {
            const type = this.value;
            const remotePortGroup = document.getElementById('remotePortGroup');
            if (type === 'ssh' || type === 'tcp') {
                remotePortGroup.style.display = 'block';
            } else {
                remotePortGroup.style.display = 'none';
            }
        });

        // 生成安裝命令
        function generateCommand() {
            const tunnelName = document.getElementById('tunnelName').value.trim();
            const tunnelType = document.getElementById('tunnelType').value;
            const localPort = document.getElementById('localPort').value;
            const localIp = document.getElementById('localIp').value || '127.0.0.1';
            const remotePort = document.getElementById('remotePort').value;

            // 驗證輸入
            if (!tunnelName) {
                alert('請輸入隧道名稱！');
                return;
            }
            if (!tunnelType) {
                alert('請選擇服務類型！');
                return;
            }
            if (!localPort) {
                alert('請輸入本地端口！');
                return;
            }

            // 建構命令（替換為你的伺服器IP）
            let installCommand = `curl -fsSL http://你的伺服器IP:8080/install.sh | bash -s -- "${tunnelName}" "${tunnelType}" "${localPort}" "${localIp}"`;
            
            if (remotePort) {
                installCommand += ` "${remotePort}"`;
            }

            // 生成訪問信息
            let accessInfo = '';
            if (tunnelType === 'http') {
                accessInfo = `訪問地址: http://${tunnelName}.t.帝acg.xyz`;
            } else if (tunnelType === 'https') {
                accessInfo = `訪問地址: https://${tunnelName}.t.帝acg.xyz`;
            } else {
                const displayPort = remotePort ? remotePort : '隨機端口';
                accessInfo = `連接地址: ${tunnelName}.t.帝acg.xyz:${displayPort}`;
            }

            // 顯示結果
            document.getElementById('commandOutput').textContent = installCommand;
            document.getElementById('accessInfo').textContent = accessInfo;
            document.getElementById('commandResult').style.display = 'block';

            // 滾動到結果
            document.getElementById('commandResult').scrollIntoView({ behavior: 'smooth' });
        }

        // 複製命令
        function copyCommand() {
            const commandText = document.getElementById('commandOutput').textContent;
            navigator.clipboard.writeText(commandText).then(() => {
                alert('命令已複製到剪貼板！');
            }).catch(() => {
                // 降級方案
                const textArea = document.createElement('textarea');
                textArea.value = commandText;
                document.body.appendChild(textArea);
                textArea.select();
                document.execCommand('copy');
                document.body.removeChild(textArea);
                alert('命令已複製！');
            });
        }
    </script>
</body>
</html>
EOF
    echo "✅ index.html 建立完成"
}

# 啟動服務
start_services() {
    cd /opt/frp-public
    docker-compose up -d
    sleep 5  # 等待啟動
    echo "✅ 服務啟動完成"
}

# 配置防火牆
configure_firewall() {
    ufw --force enable
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 7000/tcp
    ufw allow 8080/tcp
    ufw allow 10000:30000/tcp
    ufw reload
    echo "✅ 防火牆配置完成"
}

# 主要執行流程
install_dependencies
setup_directories
create_frps_config
create_docker_compose
create_install_script
create_web_interface
start_services
configure_firewall

# 顯示結果
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
echo ""
echo "=================================================="
echo "🎉 部署完成！"
echo "=================================================="
echo "🌐 管理介面: http://${SERVER_IP}:8080"
echo "🌐 公網訪問: http://www.frp.帝acg.xyz:8080  （記得解析域名到 ${SERVER_IP}）"
echo "🌐 子域名: t.帝acg.xyz  （用於隧道，解析到 ${SERVER_IP}）"
echo ""
echo "💡 測試範例（替換你的IP）："
echo "curl -fsSL http://${SERVER_IP}:8080/install.sh | bash -s -- test http 8080"
echo ""
echo "🔍 檢查狀態: docker-compose -f /opt/frp-public/docker-compose.yml ps"
echo "🔍 查看日誌: docker-compose -f /opt/frp-public/docker-compose.yml logs -f"
echo ""
echo "💝 感謝使用 善良的人的遊戲庫 提供的免費服務"
echo "🌐 主站: https://帝acg.xyz"
echo "=================================================="
EOF

# 設定權限並執行
chmod +x /tmp/deploy-frp.sh
/tmp/deploy-frp.sh

# 清理
rm -f /tmp/deploy-frp.sh
