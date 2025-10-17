#!/bin/bash
set -euo pipefail

AIR_USER=""

AIR_API_TOKEN=""
DEFAULT_CMD="sudo ls -la"
CPU=1
MEMORY=1
DISK=10
SERVICE_PORTS="22"
START_ONLY=false
FORCE_EXEC_PARAM=false
EXEC_CMD=""
RETRY_MAX=5

USER_SET_CPU=false
USER_SET_MEM=false
USER_SET_DISK=false
USER_SET_SERVICES=false

# ====================== 输出函数 =====================
green() { echo -e "\033[32m$1\033[0m"; }
red()   { echo -e "\033[31m$1\033[0m"; }
yellow(){ echo -e "\033[33m$1\033[0m"; }

usage() {
  cat <<EOF
Usage: $0 [options]
Options:
  -c <cpu>        CPU cores (integer, default 1)
  -m <mem>        Memory in GB (integer, default 1)
  -d <disk>       Disk in GB (integer, default 10)
  -s <ports>      Service ports (comma separated), e.g. -s 22,80
  -S              START模式: 遍历启动 STOPPED/STORED 仿真
  -E "<command>"  强制执行命令，即使仿真是LOADED
  -e "<command>"  执行自定义命令（覆盖默认sudo ls）
  -h              显示帮助
EOF
}

# ====================== 参数解析 =====================
while getopts "c:m:d:s:Se:E:h" opt; do
  case $opt in
    c) CPU="$OPTARG"; USER_SET_CPU=true ;;
    m) MEMORY="$OPTARG"; USER_SET_MEM=true ;;
    d) DISK="$OPTARG"; USER_SET_DISK=true ;;
    s) SERVICE_PORTS="$OPTARG"; USER_SET_SERVICES=true ;;
    S) START_ONLY=true ;;
    e) EXEC_CMD="$OPTARG" ;;
    E) FORCE_EXEC_PARAM=true; EXEC_CMD="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

# 校验冲突
if [ "$START_ONLY" = true ] && ( $USER_SET_CPU || $USER_SET_MEM || $USER_SET_DISK || $USER_SET_SERVICES ); then
  red "❌ 错误：-S 模式与 -c/-m/-d/-s 冲突"
  exit 1
fi

# 数值校验
if ! [[ "$CPU" =~ ^[0-9]+$ && "$MEMORY" =~ ^[0-9]+$ && "$DISK" =~ ^[0-9]+$ ]]; then
  red "❌ CPU / 内存 / 磁盘必须为正整数"
  exit 1
fi

# 服务端口校验
IFS=',' read -r -a PORT_ARR <<< "$SERVICE_PORTS"
for p in "${PORT_ARR[@]}"; do
  if ! [[ "$p" =~ ^[0-9]+$ ]] || [ "$p" -lt 1 ] || [ "$p" -gt 65535 ]; then
    red "❌ 服务端口不合法: $p"
    exit 1
  fi
done

# ====================== 登录 =====================
login() {
  yellow "🟢 登录 NVIDIA Air..."
  LOGIN_RESPONSE=$(curl -s -X POST "https://air.nvidia.com/api/v1/login/" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${AIR_USER}\",\"password\":\"${AIR_API_TOKEN}\"}")
  AIR_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token')
  if [ -z "$AIR_TOKEN" ] || [ "$AIR_TOKEN" = "null" ]; then
    red "❌ 登录失败，请检查账号密码"
    echo "$LOGIN_RESPONSE"
    exit 1
  fi
  export AIR_TOKEN
  green "✅ 登录成功"
}

# ====================== 仿真相关 =====================
list_simulations() {
  curl -s -H "Authorization: Bearer $AIR_TOKEN" \
    "https://air.nvidia.com/api/v2/simulations/" | jq -r '.results[] | [.id, .title, .state] | @tsv'
}

start_simulation() {
  local SIM_ID="$1"
  local MAX_TRIES=2
  local TRY=0
  while [ $TRY -lt $MAX_TRIES ]; do
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
      "https://air.nvidia.com/api/v2/simulations/$SIM_ID/load/" \
      -H "Authorization: Bearer $AIR_TOKEN" -H "Content-Type: application/json" -d '{}')
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "204" ]]; then
      green "✅ 仿真 $SIM_ID 启动成功"
      return 0
    else
      yellow "⚠️ 仿真 $SIM_ID 启动失败 (HTTP:$HTTP_CODE)，重试..."
      sleep 3
    fi
    ((TRY++))
  done
  red "❌ 仿真 $SIM_ID 启动失败"
  return 1
}

# ====================== 节点/接口/服务 =====================
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

# ====================== SSH 执行 =====================
# ====================== SSH 执行 =====================
# ====================== SSH 执行 =====================
# 全局关联数组，记录已执行过的 host:port
declare -A SSH_DONE

ssh_exec() {
  local HOST="$1" PORT="$2" USER="$3"
  local CMD="${EXEC_CMD:-$DEFAULT_CMD}"
  local PASS="nvidia"
  local KEY="$HOST:$PORT"

  # 如果已经执行过该 host:port，则直接返回
  if [[ -n "${SSH_DONE[$KEY]:-}" ]]; then
    return 0
  fi

  local ATTEMPT=1
  while [ $ATTEMPT -le $RETRY_MAX ]; do
    yellow "🔑 SSH 尝试第 $ATTEMPT 次：$USER@$HOST:$PORT"

    # 使用 nc 检测端口
    if nc -z -w3 "$HOST" "$PORT" >/dev/null 2>&1; then
      green "✅ 端口 $HOST:$PORT 开放"

      # 自动添加 known_hosts 避免 yes/no 提示
      if ! ssh-keygen -F "$HOST" >/dev/null 2>&1; then
        yellow "⚠️ 添加 host 到 known_hosts"
        ssh-keyscan -p "$PORT" "$HOST" >> ~/.ssh/known_hosts 2>/dev/null
      fi

      # 执行命令
      if sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 -p "$PORT" "$USER@$HOST" "$CMD"; then
        green "✅ $HOST:$PORT 命令执行成功"
        SSH_DONE[$KEY]=1
        return 0
      else
        yellow "❌ SSH 连接或命令执行失败，重试..."
      fi
    else
      yellow "⏳ 端口 $HOST:$PORT 未开放，等待..."
    fi

    ((ATTEMPT++))
    sleep 3
  done

  red "❌ SSH 登录失败（$HOST:$PORT），超过重试次数 $RETRY_MAX"
  return 1
}



# ====================== 主流程 =====================
login

if [ "$START_ONLY" = true ]; then
  yellow "🚀 START 模式：遍历启动 STOPPED/STORED 仿真"
  list_simulations | while IFS=$'\t' read -r SIM_ID TITLE STATE; do
     FORCE_EXEC=false
    if [[ "$STATE" == "STOPPED" || "$STATE" == "STORED" ]]; then
      yellow "▶ 启动仿真：$TITLE ($SIM_ID)"
      start_simulation "$SIM_ID"
      FORCE_EXEC=true
    elif [[ "$STATE" == "LOADED" && "$FORCE_EXEC_PARAM" == true ]]; then
      FORCE_EXEC=true
      green "✅ -E 参数生效，LOADED 仿真也将执行命令"
    else
      yellow "⏩ 仿真 $SIM_ID 状态 $STATE，跳过"
      continue
    fi

    if [[ "$FORCE_EXEC" == true || -n "$EXEC_CMD" ]]; then
      green "💻 执行命令：${EXEC_CMD:-$DEFAULT_CMD}"
      get_nodes "$SIM_ID" | while IFS=$'\t' read -r NODE_ID NODE_NAME; do
        get_interfaces "$NODE_ID" | while IFS=$'\t' read -r IFACE_ID IFACE_NAME; do
          get_services "$SIM_ID" | while IFS=$'\t' read -r PORT HOST USER; do
            ssh_exec "$HOST" "$PORT" "$USER"
          done
        done
      done
    fi
  done
  exit 0
fi

# 默认创建模式
SIM_ID=$(curl -s -X POST -H "Authorization: Bearer $AIR_TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"auto-sim-'"$(date +%s)"'","netq_auto_enabled":true}' \
  "https://air.nvidia.com/api/v2/simulations/" | jq -r '.id')
yellow "🧩 仿真已创建: $SIM_ID"

# 节点/接口
NODE_ID=$(curl -s -X POST -H "Authorization: Bearer $AIR_TOKEN" -H "Content-Type: application/json" \
  -d "{\"simulation\":\"$SIM_ID\",\"name\":\"auto-node\",\"os\":\"generic/ubuntu2204\",\"memory\":$((MEMORY*1024)),\"storage\":$DISK,\"cpu\":$CPU,\"state\":\"RUNNING\"}" \
  "https://air.nvidia.com/api/v2/simulations/nodes/" | jq -r '.id')
yellow "💻 节点已创建: $NODE_ID"

IFACE_ID=$(curl -s -X POST -H "Authorization: Bearer $AIR_TOKEN" -H "Content-Type: application/json" \
  -d "{\"node\":\"$NODE_ID\",\"name\":\"eth0\",\"link_up\":true,\"interface_type\":\"DATA_PLANE_INTF\"}" \
  "https://air.nvidia.com/api/v2/simulations/nodes/interfaces/" | jq -r '.id')
yellow "🌐 接口已创建: $IFACE_ID"

# 启动仿真
start_simulation "$SIM_ID"

# 创建服务并执行命令
for P in "${PORT_ARR[@]}"; do
  read SRC_PORT HOST USER <<< "$(curl -s -X POST -H "Authorization: Bearer $AIR_TOKEN" -H "Content-Type: application/json" \
    -d "{\"name\":\"svc-$P\",\"simulation\":\"$SIM_ID\",\"interface\":\"$IFACE_ID\",\"dest_port\":$P,\"link\":\"\",\"service_type\":\"other\"}" \
    "https://air.nvidia.com/api/v1/service/" | jq -r '[.src_port,.host,.os_default_username] | @tsv')"
  green "🔌 服务已创建：$P -> $HOST:$SRC_PORT (user:$USER)"
  ssh_exec "$HOST" "$SRC_PORT" "$USER"
done

green "🎉 完成"
