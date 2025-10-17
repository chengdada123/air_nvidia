#!/bin/bash
AIR_USER=""
AIR_API_TOKEN=""
# ================= 登录函数 =================
login() {
    echo "🟢 登录 NVIDIA Air..."
    LOGIN_RESPONSE=$(curl -s -X POST "https://air.nvidia.com/api/v1/login/" \
      -H "Content-Type: application/json" \
      -d "{
        \"username\": \"${AIR_USER}\",
        \"password\": \"${AIR_API_TOKEN}\"
      }")

    TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token' || true)
    if [ -z "$TOKEN" ]; then
        echo "❌ 登录失败，请检查 AIR_USER/AIR_API_TOKEN。"
        echo "$LOGIN_RESPONSE" | jq . 2>/dev/null || echo "$LOGIN_RESPONSE"
        exit 1
    fi
    export AIR_TOKEN="$TOKEN"
    echo "✅ 登录成功，Bearer token 获取完毕."
}

# ================= 获取镜像列表 =================
list_images() {
    curl -s -H "Authorization: Bearer $AIR_TOKEN" \
      "https://air.nvidia.com/api/v2/images/" | jq '.results[] | {id, name, version}'
}

# ================= 获取镜像 ID by name =================
get_image_id() {
    local OS_NAME="$1"
    IMAGE_LIST=$(curl -s -H "Authorization: Bearer $AIR_TOKEN" "https://air.nvidia.com/api/v2/images/?name=$OS_NAME")
    IMAGE_ID=$(echo "$IMAGE_LIST" | jq -r '.results[0].id' || true)
    if [ -z "$IMAGE_ID" ]; then
        echo "❌ 未找到镜像 '$OS_NAME'。请使用选项8查看可用镜像。"
        return 1
    fi
    echo "$IMAGE_ID"
}

# ================= 获取仿真列表 =================
list_simulations() {
    curl -s -H "Authorization: Bearer $AIR_TOKEN" \
      "https://air.nvidia.com/api/v2/simulations/" | jq '.results[] | {id,title,state}'
}

# ================= 查看仿真详情 =================
show_simulation() {
    read -p "请输入仿真ID: " SIM_ID
    curl -s -H "Authorization: Bearer $AIR_TOKEN" \
      "https://air.nvidia.com/api/v2/simulations/$SIM_ID/" | jq . 2>/dev/null || echo "响应: $RESPONSE"
}

# ================= 创建仿真 =================
create_simulation() {
    read -p "请输入仿真标题: " TITLE
    read -p "请输入 owner 邮箱: " OWNER
    SIM_JSON=$(jq -n \
      --arg title "$TITLE" \
      --arg owner "$OWNER" \
      '{
        title: $title,
        owner: $owner,
        netq_auto_enabled: true
      }'
    )
    RESPONSE=$(curl -s -X POST "https://air.nvidia.com/api/v2/simulations/" \
      -H "Authorization: Bearer $AIR_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$SIM_JSON")
    echo "$RESPONSE" | jq . 2>/dev/null || echo "响应: $RESPONSE"
}

# ================= 创建节点 =================
create_node() {
    read -p "请输入仿真ID: " SIM_ID
    # 检查仿真是否存在
    echo "🟡 检查仿真 $SIM_ID 是否存在..."
    SIM_CHECK=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $AIR_TOKEN" "https://air.nvidia.com/api/v2/simulations/$SIM_ID/")
    HTTP_CODE=$(echo "$SIM_CHECK" | tail -n1)
    BODY=$(echo "$SIM_CHECK" | sed '$d')
    if [ "$HTTP_CODE" -ne 200 ]; then
        echo "❌ 仿真 $SIM_ID 不存在或无法访问 (HTTP $HTTP_CODE)。请检查仿真列表。"
        echo "$BODY" | jq . 2>/dev/null || echo "响应: $BODY"
        return 1
    fi
    echo "✅ 仿真存在。"

    read -p "请输入节点名称: " NODE_NAME
    read -p "请输入 OS 镜像名称 (例如: generic/ubuntu2204 或 cumulus-vx-4.2.1.7): " OS_NAME
    # 获取镜像 ID
    IMAGE_ID=$(get_image_id "$OS_NAME")
    if [ $? -ne 0 ]; then
        return 1
    fi
    echo "✅ 找到镜像 ID: $IMAGE_ID"

    read -p "请输入内存大小 (MB, 默认1024): " MEMORY
    MEMORY=${MEMORY:-1024}
    read -p "请输入 CPU 核心数 (默认2): " CPU
    CPU=${CPU:-2}
    read -p "请输入存储大小 (GB, 默认100): " STORAGE
    STORAGE=${STORAGE:-100}

    # 默认值基于提供的成功参数
    CONSOLE_PORT=2147483647
    SERIAL_PORT=2147483647
    STATE="RUNNING"
    CONSOLE_USER="ubuntu"
    CONSOLE_PASS="ubuntu"
    VERSION=0
    POS_X=0
    POS_Y=0
    BOOT_GROUP=0

    NODE_JSON=$(jq -n \
      --arg simulation "$SIM_ID" \
      --argjson console_port "$CONSOLE_PORT" \
      --argjson serial_port "$SERIAL_PORT" \
      --arg state "$STATE" \
      --arg console_username "$CONSOLE_USER" \
      --arg console_password "$CONSOLE_PASS" \
      --arg name "$NODE_NAME" \
      --arg os "$IMAGE_ID" \
      --argjson memory "$MEMORY" \
      --argjson storage "$STORAGE" \
      --argjson cpu "$CPU" \
      --argjson version "$VERSION" \
      --argjson pos_x "$POS_X" \
      --argjson pos_y "$POS_Y" \
      --argjson boot_group "$BOOT_GROUP" \
      '{
        simulation: $simulation,
        console_port: $console_port,
        serial_port: $serial_port,
        state: $state,
        console_username: $console_username,
        console_password: $console_password,
        name: $name,
        os: $os,
        memory: $memory,
        storage: $storage,
        cpu: $cpu,
        version: $version,
        pos_x: $pos_x,
        pos_y: $pos_y,
        boot_group: $boot_group
      }'
    )

    echo "🟡 创建节点 $NODE_NAME ..."
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "https://air.nvidia.com/api/v2/simulations/nodes/" \
      -H "Authorization: Bearer $AIR_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$NODE_JSON")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 200 ]; then
        echo "✅ 节点创建完成，返回信息如下："
        echo "$BODY" | jq . 2>/dev/null || echo "原始响应: $BODY"
    else
        echo "❌ 节点创建失败 (HTTP 状态码: $HTTP_CODE)，返回信息如下："
        echo "$BODY" | jq . 2>/dev/null || echo "原始响应: $BODY"
    fi
}

# ================= 删除节点 =================
delete_node() {
    
    read -p "请输入节点ID: " NODE_ID
    RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE "https://air.nvidia.com/api/v2/simulations/nodes/$NODE_ID/" \
      -H "Authorization: Bearer $AIR_TOKEN")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    if [ "$HTTP_CODE" -eq 204 ] || [ "$HTTP_CODE" -eq 200 ]; then
        echo "✅ 节点删除完成"
    else
        echo "❌ 节点删除失败 (HTTP 状态码: $HTTP_CODE)：$BODY"
    fi
}

# ================= 删除仿真 =================
delete_simulation() {
    read -p "请输入仿真ID: " SIM_ID
    RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE "https://air.nvidia.com/api/v2/simulations/$SIM_ID/" \
      -H "Authorization: Bearer $AIR_TOKEN")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    if [ "$HTTP_CODE" -eq 204 ] || [ "$HTTP_CODE" -eq 200 ]; then
        echo "✅ 仿真删除完成"
    else
        echo "❌ 仿真删除失败 (HTTP 状态码: $HTTP_CODE)：$BODY"
    fi
}

# ================= 获取节点列表 =================
list_nodes() {
   read -p "请输入仿真ID: " SIM_ID    
    curl -s -H "Authorization: Bearer $AIR_TOKEN" \
      "https://air.nvidia.com/api/v2/simulations/nodes/" | jq '.results[] | {id, name, state}'
}
# ================= 获取接口列表 =================

list_port() {
    read -p "请输入节点ID: " NODE_ID

    curl -sS -H "Authorization: Bearer $AIR_TOKEN" \
      "https://air.nvidia.com/api/v2/simulations/nodes/interfaces/?node=$NODE_ID" \
    | jq -r '.results[]? | {id, name, state}'
}
create_service() {
    read -p "请输入服务名称 (例如 rdp): " NAME
    read -p "请输入仿真ID: " SIMULATION_ID
    read -p "请输入接口ID: " INTERFACE_ID
    read -p "请输入目标端口 (例如 3389): " DEST_PORT
    read -p "请输入服务类型 (例如 other): " SERVICE_TYPE

    # 用 jq 构造 JSON，防止引号转义错误
    SERVICE_JSON=$(jq -n \
      --arg name "$NAME" \
      --arg simulation "$SIMULATION_ID" \
      --arg interface "$INTERFACE_ID" \
      --argjson dest_port "$DEST_PORT" \
      --arg link "" \
      --arg service_type "$SERVICE_TYPE" \
      '{
        name: $name,
        simulation: $simulation,
        interface: $interface,
        dest_port: $dest_port,
        link: $link,
        service_type: $service_type
      }'
    )

    RESPONSE=$(curl -sS -w "\n%{http_code}" -X POST \
      "https://air.nvidia.com/api/v1/service/" \
      -H "accept: application/json" \
      -H "Authorization: Bearer $AIR_TOKEN" \
      -H "Content-Type: application/json" \
      -H "X-CSRFTOKEN: $AIR_CSRF_TOKEN" \
      -d "$SERVICE_JSON")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 200 ]; then
        echo "✅ 服务创建成功："
        echo "$BODY" | jq .
    else
        echo "❌ 创建失败 (HTTP 状态码: $HTTP_CODE)：$BODY"
    fi
}



create_port() {
    read -p "请输入节点ID: " NODE

    SIM_JSON=$(jq -n \
      --arg node "$NODE" \
      '{
        link_up: true,
        port_number: 2147483647,
        node: $node,
        name: "eth0",
        interface_type: "DATA_PLANE_INTF",
        preserve_mac: true,
        outbound: true,
        netq_auto_enabled: true
      }'
    )

    RESPONSE=$(curl -sS -X POST "https://air.nvidia.com/api/v2/simulations/nodes/interfaces/" \
      -H "Authorization: Bearer $AIR_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$SIM_JSON")

    echo "$RESPONSE" | jq . 2>/dev/null || echo "响应: $RESPONSE"
}


#启动模拟


start_simulation() {
    read -p "请输入仿真ID: " SIM_ID

    # 使用空 JSON 发送 POST 请求，保证 Content-Length 被正确设置
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
      "https://air.nvidia.com/api/v2/simulations/$SIM_ID/load/" \
      -H "Authorization: Bearer $AIR_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{}')

    # 分离 HTTP 状态码和响应体
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    # 判断状态码
    if [ "$HTTP_CODE" -eq 204 ] || [ "$HTTP_CODE" -eq 200 ]; then
        echo "✅ 仿真已启动成功"
    else
        echo "❌ 启动失败 (HTTP 状态码: $HTTP_CODE)：$BODY"
    fi
}



stop_simulation() {
    read -p "请输入仿真ID: " SIM_ID

    # 使用空 JSON 发送 POST 请求，保证 Content-Length 被正确设置
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
      "https://air.nvidia.com/api/v2/simulations/$SIM_ID/store/" \
      -H "Authorization: Bearer $AIR_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{}')

    # 分离 HTTP 状态码和响应体
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    # 判断状态码
    if [ "$HTTP_CODE" -eq 204 ] || [ "$HTTP_CODE" -eq 200 ]; then
        echo "✅ 已停止"
    else
        echo "❌ 停止失败 (HTTP 状态码: $HTTP_CODE)：$BODY"
    fi
}

# renew
simulation_renew() {
    read -p "请输入仿真ID: " SIM_ID

    if [[ -z "$SIM_ID" ]]; then
        echo "⚠️ 仿真ID不能为空，请重新执行命令。"
        return 1
    fi

    echo "🔄 正在发送续期请求到 NVIDIA Air…"

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
      "https://air.nvidia.com/api/v1/simulation/$SIM_ID/control/" \
      -H "Authorization: Bearer $AIR_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{ "action": "extend"}')

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [[ "$HTTP_CODE" -ne 200 ]]; then
        echo "❌ 仿真续期失败，HTTP 状态码: $HTTP_CODE"
        echo "响应内容: $BODY"
        return 1
    fi

    # 解析 JSON 获取新的到期时间
    # 这里假设返回 {"result": "success", "message": "2025-10-24T08:50:56.537Z"}
    EXPIRY=$(echo "$BODY" | grep -oP '"message"\s*:\s*"\K[^"]+')
    if [[ -z "$EXPIRY" ]]; then
        echo "⚠️ 未能解析到新的到期时间。"
        return 1
    fi

    # 当前 UTC 时间
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # 计算剩余秒数
    REMAIN_SEC=$(( $(date -d "$EXPIRY" +%s) - $(date -d "$NOW" +%s) ))
    if [[ $REMAIN_SEC -le 0 ]]; then
        echo "⚠️ 仿真已过期或到期时间错误: $EXPIRY"
        return 1
    fi

    # 转换成天/小时/分钟
    DAYS=$((REMAIN_SEC/86400))
    HOURS=$(( (REMAIN_SEC%86400)/3600 ))
    MINUTES=$(( (REMAIN_SEC%3600)/60 ))

    echo "✅ 仿真续期成功！"
    echo "📅 新到期时间: $EXPIRY (UTC)"
    echo "⏳ 距离到期还有: ${DAYS}天 ${HOURS}小时 ${MINUTES}分钟"
}




# ================= 菜单 =================
while true; do
    echo "=============================="
    echo "1. 登录"
    echo "2. 获取仿真列表"
    echo "3. 查看仿真详情"
    echo "4. 创建仿真"
    echo "5. 创建节点"
    echo "6. 删除节点"
    echo "7. 删除仿真"
    echo "8. 获取镜像列表 (用于选择 OS)"
    echo "9. 获取节点列表 (指定仿真ID)"
    echo "10.给节点创建网络"
    echo "11.启动仿真"
    echo "12.停止仿真"
    echo "13.列出网络接口"
    echo "14.创建服务（端口转发）"
    echo "15.增加睡眠时间"
    echo "0. 退出"
    echo "=============================="
    read -p "请输入选项: " CHOICE

    case $CHOICE in
        1) login ;;
        2) list_simulations ;;
        3) show_simulation ;;
        4) create_simulation ;;
        5) create_node ;;
        6) delete_node ;;
        7) delete_simulation ;;
        8) list_images ;;
        9) list_nodes ;;
        10) create_port ;;
        11) start_simulation ;;
        12) stop_simulation ;;
        13) list_port ;;
        14) create_service ;;
        15) simulation_renew ;;
        0) exit ;;
        *) echo "无效选项" ;;
    esac
done
