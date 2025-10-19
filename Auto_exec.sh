#!/bin/bash
set -euo pipefail

# ================= 配置 =================
AIR_USER=""  #你的邮箱
AIR_API_TOKEN="" #https://air.nvidia.com/settings 申请的api
DEFAULT_CMD="sudo ls -la"  #初始指令
CPU=1
MEMORY=1
DISK=10
SERVICE_PORTS="22"
START_ONLY=false
EXEC_CMD=""
FORCE_EXEC=false
RETRY_MAX=5
SSH_USERNAME="ubuntu"
SSH_PASS="nvidia"
SSH_EXEC_PORT=22   # SSH 命令只执行在这个端口
USER_SET_CPU=false
USER_SET_MEM=false
USER_SET_DISK=false
USER_SET_SERVICES=false
RENEW_LOADED=false
# 可选变量（可在外部 export）
TG_BOT_TOKEN=""
TG_CHAT_ID=""

# ================= 输出函数 =================
green() { echo -e "\033[32m$1\033[0m"; }
red()   { echo -e "\033[31m$1\033[0m"; }
yellow(){ echo -e "\033[33m$1\033[0m"; }


#安装必要的依赖
# ===== 静默安装依赖 =====
apt_first() {
yellow "📦 检查必要依赖..."
sudo apt update -y >/dev/null 2>&1
sudo apt install -y jq curl sshpass netcat-openbsd openssh-client >/dev/null 2>&1
# 检查安装结果
for cmd in jq curl sshpass nc ssh; do
  if ! command -v $cmd &>/dev/null; then
    red "❌ 未找到 $cmd，请手动检查安装"
  else
    green "✅ $cmd 已安装"
  fi
done

green "✅ 所有依赖安装完成"
}

apt_first
usage() {
  cat <<EOF
Usage: $0 [options]
Options:
  -c <cpu>        CPU cores (integer, default 1)
  -m <mem>        Memory in GB (integer, default 1)
  -d <disk>       Disk in GB (integer, default 10)
  -s <ports>      Service ports (comma separated), e.g. -s 22,3389
  -S              START mode (uppercase S): don't create; start STOPPED/STORED sims
  -e "<command>"  Execute custom command after SSH (overrides default)
  -E "<command>"  Force execute command even if LOADED
  -r              renew
  -h              Show this help
Notes:
  - Uppercase -S is START (only). Lowercase -s is service ports.
EOF
}

# ================= 参数解析 =================
PORT_ARR=()
while getopts "c:m:d:s:Se:E:h:r" opt; do
  case $opt in
    c) CPU="$OPTARG"; USER_SET_CPU=true ;;
    m) MEMORY="$OPTARG"; USER_SET_MEM=true ;;
    d) DISK="$OPTARG"; USER_SET_DISK=true ;;
    s) SERVICE_PORTS="$OPTARG"; USER_SET_SERVICES=true ;;
    S) START_ONLY=true ;;
    e) EXEC_CMD="$OPTARG" ;;
    E) FORCE_EXEC=true ;EXEC_CMD="$OPTARG"  ;;
    r) RENEW_LOADED=true ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [ "$RENEW_LOADED" = true ] && ( $USER_SET_CPU || $USER_SET_MEM || $USER_SET_DISK || $USER_SET_SERVICES || $START_ONLY ); then
  red "❌ -r 模式与 -c/-m/-d/-s 冲突"
  exit 1
fi

# 检查 -E 是否单独使用
if [ "$FORCE_EXEC" = true ] && [ "$START_ONLY" != true ]; then
    echo "❌ -E 必须和 -S 一起使用"
    exit 1
fi


if [ "$START_ONLY" = true ] && ( $USER_SET_CPU || $USER_SET_MEM || $USER_SET_DISK || $USER_SET_SERVICES ); then
  red "❌ -S 模式与 -c/-m/-d/s 冲突"
  exit 1
fi

IFS=',' read -r -a PORT_ARR <<< "$SERVICE_PORTS"
for p in "${PORT_ARR[@]}"; do
  if ! [[ "$p" =~ ^[0-9]+$ ]] || [ "$p" -lt 1 ] || [ "$p" -gt 65535 ]; then
    red "❌ 服务端口不合法: $p"; exit 1
  fi
done

# ================= 登录 =================
login() {
  yellow "🟢 登录 NVIDIA Air..."
  LOGIN_RESPONSE=$(curl -s -X POST "https://air.nvidia.com/api/v1/login/" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${AIR_USER}\",\"password\":\"${AIR_API_TOKEN}\"}")
  AIR_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token' || true)
  if [ -z "$AIR_TOKEN" ] || [ "$AIR_TOKEN" = "null" ]; then
    red "❌ 登录失败，请检查账号密码"
    exit 1
  fi
  export AIR_TOKEN
  green "✅ 登录成功"
}
login_password(){
  yellow "🟢 登录 NVIDIA Air..."
  LOGIN_RESPONSE=$(curl -s -X POST "https://air.nvidia.com/api/v1/login/" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${AIR_USER}\",\"password\":\"${AIR_PASSWORD}\"}")
  AIR_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token' || true)
  if [ -z "$AIR_TOKEN" ] || [ "$AIR_TOKEN" = "null" ]; then

    red "❌ 登录失败，请检查账号密码"
  echo "$LOGIN_RESPONSE" | jq . 2>/dev/null || echo "$LOGIN_RESPONSE"
    exit 1
  fi
  export AIR_TOKEN
  green "✅ 登录成功"
}


# ================= 仿真 =================
list_simulations() {
  curl -s -H "Authorization: Bearer $AIR_TOKEN" \
    "https://air.nvidia.com/api/v2/simulations/" | jq -r '.results[] | [.id, .title, .state] | @tsv'
}

start_simulation() {
  local SIM_ID="$1"
  local MAX_RETRIES=3
  local RETRY_DELAY=5
  local attempt=1

  while [ $attempt -le $MAX_RETRIES ]; do
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
      -H "Authorization: Bearer $AIR_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{}' \
      "https://air.nvidia.com/api/v2/simulations/$SIM_ID/load/")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "204" ]]; then
      green "✅ 仿真 $SIM_ID 启动成功"
    
#自行配置
  if [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
      -F chat_id="$TG_CHAT_ID" \
      -F text="✅ 仿真 ${sim_id} 启动成功" >/dev/null
  fi

      return 0 

    else
      yellow "⚠️ 仿真 $SIM_ID 启动失败 (HTTP:$HTTP_CODE)，重试..."
      sleep $RETRY_DELAY
    fi
    ((attempt++))
  done
  red "❌ 仿真 $SIM_ID 启动失败"; return 1
}

# ================= 节点/接口/服务 =================
create_node() {
    MEMORY=$((MEMORY * 1024))  # 转为 MB
    STORAGE=$DISK
    CPU=$CPU
    IMAGE_NAME="generic/ubuntu2204"

    # 查询镜像 ID
    IMAGE_ID=$(curl -s -H "Authorization: Bearer $AIR_TOKEN" \
        "https://air.nvidia.com/api/v2/images/?name=$IMAGE_NAME" | jq -r '.results[0].id')

    if [ -z "$IMAGE_ID" ] || [ "$IMAGE_ID" = "null" ]; then
        red "❌ 镜像 $IMAGE_NAME 未找到"
        exit 1
    fi

    NODE_JSON=$(jq -n \
      --arg simulation "$SIM_ID" \
      --arg name "auto-node" \
      --arg os "$IMAGE_ID" \
      --argjson memory "$MEMORY" \
      --argjson storage "$STORAGE" \
      --argjson cpu "$CPU" \
      --arg state "RUNNING" \
      '{simulation:$simulation,name:$name,os:$os,memory:$memory,storage:$storage,cpu:$cpu,state:$state}')

    RESPONSE=$(curl -s -X POST "https://air.nvidia.com/api/v2/simulations/nodes/" \
        -H "Authorization: Bearer $AIR_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$NODE_JSON")
    NODE_ID=$(echo "$RESPONSE" | jq -r '.id')

    if [ -z "$NODE_ID" ] || [ "$NODE_ID" = "null" ]; then
        red "❌ 节点创建失败"
        exit 1
    fi
    green "✅ 节点创建完成: $NODE_ID"
}



# ================= 创建网络接口 =================
create_interface() {
    SIM_JSON=$(jq -n --arg node "$NODE_ID" '{
        link_up: true,
        port_number: 2147483647,
        node: $node,
        name: "eth0",
        interface_type: "DATA_PLANE_INTF",
        preserve_mac: true,
        outbound: true,
        netq_auto_enabled: true
    }')
    RESPONSE=$(curl -s -X POST "https://air.nvidia.com/api/v2/simulations/nodes/interfaces/" \
        -H "Authorization: Bearer $AIR_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$SIM_JSON")
    INTERFACE_ID=$(echo "$RESPONSE" | jq -r '.id')
    if [ -z "$INTERFACE_ID" ] || [ "$INTERFACE_ID" = "null" ]; then
        red "❌ 网络接口创建失败"
        exit 1
    fi
    green "✅ 网络接口创建完成: $INTERFACE_ID"
}

# ================= 创建服务 =================
create_services() {
    for P in "${PORT_ARR[@]}"; do
        SERVICE_JSON=$(jq -n \
            --arg name "svc-$P" \
            --arg simulation "$SIM_ID" \
            --arg interface "$INTERFACE_ID" \
            --argjson dest_port "$P" \
            --arg link "" \
            --arg service_type "other" \
            '{name:$name,simulation:$simulation,interface:$interface,dest_port:$dest_port,link:$link,service_type:$service_type}')
        RESPONSE=$(curl -s -X POST "https://air.nvidia.com/api/v1/service/" \
            -H "Authorization: Bearer $AIR_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$SERVICE_JSON")

        # 有时返回数组，取第一个元素
        SRC_PORT=$(echo "$RESPONSE" | jq -r 'if type=="array" then .[0].src_port else .src_port end')
        HOST=$(echo "$RESPONSE" | jq -r 'if type=="array" then .[0].host else .host end')
        USER=$(echo "$RESPONSE" | jq -r 'if type=="array" then .[0].os_default_username else .os_default_username end')

        if [ -z "$HOST" ] || [ -z "$SRC_PORT" ]; then
            red "❌ 服务创建失败: 端口 $P"
            continue
        fi

        green "🔌 服务已创建：$P -> $HOST:$SRC_PORT (user:$USER)"

        # 如果是 SSH 端口，则执行命令
          if [ "$P" -eq "$SSH_EXEC_PORT" ] && { [ "$FORCE_EXEC" = true ] || [ "$EXEC_CMD" != "" ]; }; then
        wait_for_ssh "$HOST" "$SRC_PORT"
        ssh_exec "$HOST" "$SRC_PORT" "$USER"
    fi

    done
}
get_nodes() {
  local SIM_ID="$1"
  curl -s -H "Authorization: Bearer $AIR_TOKEN" \
    "https://air.nvidia.com/api/v2/simulations/nodes/?simulation=$SIM_ID" | jq -r '.results[] | [.id,.name] | @tsv'
}

get_interfaces() {
  local NODE_ID="$1"
  curl -s -H "Authorization: Bearer $AIR_TOKEN" \
    "https://air.nvidia.com/api/v2/simulations/nodes/interfaces/?node=$NODE_ID" | jq -r '.results[] | [.id,.name] | @tsv'
}

get_services() {
  local SIM_ID="$1"
  local RAW=$(curl -s -H "Authorization: Bearer $AIR_TOKEN" \
    "https://air.nvidia.com/api/v1/service/?simulation=$SIM_ID")

  # 判断返回类型
  if echo "$RAW" | jq -e 'type=="array"' >/dev/null; then
    echo "$RAW" | jq -r '.[] | [.src_port,.host,.os_default_username] | @tsv'
  else
    echo "$RAW" | jq -r '.results[] | [.src_port,.host,.os_default_username] | @tsv'
  fi

}

wait_for_ssh() {
  local H="$1"
  local P="$2"
  local MAX_WAIT=60
  local SLEEP_INTERVAL=5
  local waited=0
  yellow "⏳ 等待 SSH 服务 $H:$P 开放..."
  while ! nc -z "$H" "$P"; do
    sleep $SLEEP_INTERVAL
    waited=$((waited + SLEEP_INTERVAL))
    if [ $waited -ge $MAX_WAIT ]; then
      red "❌ SSH 服务 $H:$P 未开放"
      exit 1
    fi
  done
  green "✅ 端口 $H:$P 开放"
}

SSH_DONE=()

ssh_exec() {
    local H="$1"
    local P="$2"
    local KEY="$H:$P"

    # 检查是否已处理过
    for k in "${SSH_DONE[@]}"; do
        if [[ "$k" == "$KEY" ]]; then
            return
        fi
    done

    local CMD="${EXEC_CMD:-$DEFAULT_CMD}"
    local ATTEMPT=1

    while [ $ATTEMPT -le $RETRY_MAX ]; do
        yellow "🔑 SSH 尝试第 $ATTEMPT 次：$SSH_USERNAME@$H:$P"
        if nc -z "$H" "$P"; then
            if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$P" "$SSH_USERNAME@$H" "$CMD"; then
                green "✅ $H:$P 命令执行成功"
                SSH_DONE+=("$KEY")
                break
            else
                yellow "❌ SSH 连接或命令执行失败，重试..."
            fi
        else
            yellow "⏳ 端口 $H:$P 未开放，等待..."
        fi
        ((ATTEMPT++))
        sleep 3
    done



  
}

renew_simulation() {
    local SIM_ID="$1"
    local TARGET_SEC=$((6*24*3600 + 23*3600 + 59))  # 目标剩余秒数

    while true; do
        RESPONSE=$(curl -s -X POST \
            -H "Authorization: Bearer $AIR_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"action":"extend"}' \
            "https://air.nvidia.com/api/v1/simulation/$SIM_ID/control/")

        # 解析到期时间
        EXPIRY=$(echo "$RESPONSE" | jq -r '.message')
        if [[ -z "$EXPIRY" || "$EXPIRY" == "null" ]]; then
            red "❌ 仿真 $SIM_ID 续期失败，响应: $RESPONSE"
            return 1
        fi

        # 当前 UTC 时间
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        REMAIN_SEC=$(( $(date -d "$EXPIRY" +%s) - $(date -d "$NOW" +%s) ))

        if [[ $REMAIN_SEC -ge $TARGET_SEC ]]; then
            green "✅ 仿真 $SIM_ID 已续期到目标时间: $EXPIRY (剩余 $(($REMAIN_SEC/3600)) 小时)"
            break
        else
#            yellow "⚠️ 仿真 $SIM_ID 当前剩余 $(($REMAIN_SEC/3600)) 小时，未达到目标，继续续期..."
            sleep 2
        fi
    done
}



# ================= 主流程 =================


#login_password
login


if [ "${RENEW_LOADED:-false}" = true ]; then
    yellow "🔄 一键续期 LOADED 仿真到 6天23小时59秒"
    list_simulations | while IFS=$'\t' read -r SIM_ID TITLE STATE; do
        if [[ "$STATE" == "LOADED" ]]; then
            yellow "▶ 续期仿真: $TITLE ($SIM_ID)"
            renew_simulation "$SIM_ID"
        else
            yellow "⏩ 仿真 $TITLE ($SIM_ID) 状态 $STATE，跳过"
        fi
    done
    green "✅ 一键续期完成"
    exit 0
fi


if [ "$START_ONLY" = true ]; then
  yellow "🚀 START 模式：遍历启动 NEWD/STORED 仿真"

  while IFS=$'\t' read -r SIM_ID TITLE STATE; do
    FORCE_EXEC=false

    if [[ "$STATE" == "NEW" || "$STATE" == "STORED" ]]; then
      yellow "▶ 启动仿真：$TITLE ($SIM_ID)"
      start_simulation "$SIM_ID"

    elif [[ "$STATE" == "LOADED" && ( "$FORCE_EXEC" == true || -n "$EXEC_CMD" ) ]]; then
      green "✅ -E 参数生效，LOADED 仿真也将执行命令"
    else
      yellow "⏩ 仿真 $SIM_ID 状态 $STATE，跳过"
      continue
    fi

    if [[ "$FORCE_EXEC" == true || -n "$EXEC_CMD" ]]; then
      green "💻 执行命令：${EXEC_CMD:-$DEFAULT_CMD}"

      while IFS=$'\t' read -r NODE_ID NODE_NAME; do
        while IFS=$'\t' read -r IFACE_ID IFACE_NAME; do
          while IFS=$'\t' read -r PORT HOST USER; do
            ssh_exec "$HOST" "$PORT" "$USER"
          done < <(get_services "$SIM_ID")
        done < <(get_interfaces "$NODE_ID")
      done < <(get_nodes "$SIM_ID")
    fi
  done < <(list_simulations)

  exit 0
fi


  # 创建流程
NOW=$(date +%Y%m%d%H%M%S) 
  SIM_ID=$(curl -s -X POST -H "Authorization: Bearer $AIR_TOKEN" -H "Content-Type: application/json" \
    -d "{\"title\":\"sim_$NOW\",\"owner\":\"$AIR_USER\",\"netq_auto_enabled\":true}" \
    "https://air.nvidia.com/api/v2/simulations/" | jq -r '.id')
  green "🧩 仿真已创建: $SIM_ID"
  
  create_node
  create_interface
  
  start_simulation "$SIM_ID"
  
  # 创建服务
  for P in "${PORT_ARR[@]}"; do
    create_services "$P"
    if [ "$P" -eq "$SSH_EXEC_PORT" ]; then
      wait_for_ssh "$HOST" "$SRC_PORT"
      ssh_exec "$HOST" "$SRC_PORT"
    fi
  done

green "✅ 全部完成"
