<h1>🚀 Auto_exec.sh</h1>

<blockquote>
  自动化控制 <b>NVIDIA Air 仿真环境</b> 的一键脚本<br>
  支持仿真创建、节点管理、端口开放、命令执行、SSH 自动登录等功能。
</blockquote>

<hr>

<h2>📋 目录</h2>
<ul>
  <li><a href="#简介">📖 简介</a></li>
  <li><a href="#环境要求">⚙️ 环境要求</a></li>
  <li><a href="#自动安装依赖">📦 自动安装依赖</a></li>
  <li><a href="#使用方法">🚀 使用方法</a></li>
  <ul>
    <li><a href="#创建仿真--节点--服务">创建仿真 + 节点 + 服务</a></li>
    <li><a href="#启动已有仿真并执行命令">启动已有仿真并执行命令</a></li>
  </ul>
  <li><a href="#特性说明">🧠 特性说明</a></li>
  <li><a href="#参数说明">🧩 参数说明</a></li>
  <li><a href="#示例命令">⚡ 示例命令</a></li>
  <li><a href="#目录结构">🧱 目录结构</a></li>
  <li><a href="#注意事项">🔐 注意事项</a></li>
  <li><a href="#常见问题-faq">💬 常见问题 (FAQ)</a></li>
  <li><a href="#作者与维护">🧩 作者与维护</a></li>
</ul>

<hr>

<h2 id="简介">📖 简介</h2>
<p>
  <code>Auto_exec.sh</code> 是一个为 <b>NVIDIA Air 云仿真平台</b> 定制的自动化脚本，
  提供从 <b>仿真创建 → 节点配置 → SSH 登录 → 自动执行命令</b> 的完整流程。
</p>

<p>💡 功能包括：</p>
<ul>
  <li>自动登录并创建 Simulation / Node / Interface / Service</li>
  <li>自动安装系统依赖</li>
  <li>自动执行命令（支持批量）</li>
  <li>支持遍历启动 STOPPED/STORED 仿真</li>
  <li>支持强制命令执行（无论仿真是否 LOADED）</li>
</ul>

<hr>

<h2 id="环境要求">⚙️ 环境要求</h2>
<table>
  <tr><th>项目</th><th>要求</th></tr>
  <tr><td>系统</td><td>Ubuntu / Debian (支持 apt)</td></tr>
  <tr><td>权限</td><td>root 或具备 sudo 权限</td></tr>
  <tr><td>网络</td><td>可访问 https://air.nvidia.com</td></tr>
</table>

<hr>

<h2 id="自动安装依赖">📦 自动安装依赖</h2>
<p>脚本会在首次运行时自动静默安装以下依赖：</p>

<table>
  <tr><th>工具</th><th>用途</th></tr>
  <tr><td>jq</td><td>JSON 解析</td></tr>
  <tr><td>curl</td><td>API 请求</td></tr>
  <tr><td>sshpass</td><td>SSH 自动登录</td></tr>
  <tr><td>netcat-openbsd</td><td>端口检测</td></tr>
  <tr><td>openssh-client</td><td>SSH 客户端</td></tr>
</table>

<pre><code>sudo apt update -y &gt;/dev/null 2&gt;&amp;1
sudo apt install -y jq curl sshpass netcat-openbsd openssh-client &gt;/dev/null 2&gt;&amp;1
</code></pre>

<hr>

<h2 id="使用方法">🚀 使用方法</h2>

<h3 id="创建仿真--节点--服务">🧱 创建仿真 + 节点 + 服务</h3>

<pre><code>bash Auto_exec.sh -c 2 -m 4 -d 10 -s 22,3389
</code></pre>

<table>
  <tr><th>参数</th><th>说明</th></tr>
  <tr><td>-c</td><td>CPU 核数（默认 1）</td></tr>
  <tr><td>-m</td><td>内存大小（GB，默认 1）</td></tr>
  <tr><td>-d</td><td>磁盘大小（GB，默认 10）</td></tr>
  <tr><td>-s</td><td>服务端口（例如 -s 22,3389）</td></tr>
</table>

<p>执行流程：</p>
<ol>
  <li>登录 NVIDIA Air</li>
  <li>创建 Simulation</li>
  <li>创建 Node</li>
  <li>创建 Interface</li>
  <li>创建服务端口</li>
  <li>检测端口可用后执行命令</li>
</ol>

<hr>

<h3 id="启动已有仿真并执行命令">🔁 启动已有仿真并执行命令</h3>

<pre><code>bash Auto_exec.sh -S -E "sudo apt update -y"
</code></pre>

<table>
  <tr><th>参数</th><th>功能</th></tr>
  <tr><td>-S</td><td>启动 STOPPED/STORED 仿真（不新建）</td></tr>
  <tr><td>-E "&lt;命令&gt;"</td><td>强制执行命令（即使仿真已 LOADED）</td></tr>
  <tr><td>-e "&lt;命令&gt;"</td><td>普通执行命令（仅对新建仿真）</td></tr>
</table>

<pre><code>bash Auto_exec.sh -S -E "curl -fsSL https://get.docker.com | sh &amp;&amp; sudo systemctl enable docker --now"
</code></pre>

<hr>

<h2 id="特性说明">🧠 特性说明</h2>

<table>
  <tr><th>功能</th><th>描述</th></tr>
  <tr><td>✅ 端口检测</td><td>使用 nc 检查端口是否开放</td></tr>
  <tr><td>🔑 SSH 自动登录</td><td>通过 sshpass 自动输入密码（默认 nvidia）</td></tr>
  <tr><td>♻️ 防重复执行</td><td>已执行的主机不会重复执行命令</td></tr>
  <tr><td>⚙️ 自定义端口执行</td><td>默认仅在端口 22 执行，可修改变量</td></tr>
  <tr><td>🧩 静默安装依赖</td><td>自动检测并安装缺失的依赖</td></tr>
  <tr><td>🔒 错误防护</td><td>启用 <code>set -euo pipefail</code> 保证稳定性</td></tr>
</table>

<hr>

<h2 id="参数说明">🧩 参数说明</h2>

<table>
  <tr><th>参数</th><th>说明</th></tr>
  <tr><td>-c</td><td>CPU 核数</td></tr>
  <tr><td>-m</td><td>内存大小（GB）</td></tr>
  <tr><td>-d</td><td>磁盘大小（GB）</td></tr>
  <tr><td>-s</td><td>服务端口（逗号分隔）</td></tr>
  <tr><td>-S</td><td>启动已有仿真</td></tr>
  <tr><td>-e "&lt;命令&gt;"</td><td>执行命令</td></tr>
  <tr><td>-E "&lt;命令&gt;"</td><td>强制执行命令</td></tr>
  <tr><td>-r </td><td>一键增加休眠时间</td></tr>
  <tr><td>-h</td><td>显示帮助信息</td></tr>
</table>

<hr>

<h2 id="示例命令">⚡ 示例命令</h2>

<h3>🐳 创建仿真并安装 Docker</h3>
<pre><code>bash Auto_exec.sh -c 4 -m 8 -d 100 -s 22 \
  -e "curl -fsSL https://get.docker.com | sh &amp;&amp; sudo systemctl enable --now docker"
</code></pre>

<h3>🧰 启动已有仿真并更新系统</h3>
<pre><code>bash Auto_exec.sh -S -E "sudo apt update -y &amp;&amp; sudo apt upgrade -y"
</code></pre>

<h3>🖥️ 开放多个端口（SSH + RDP）</h3>
<pre><code>bash Auto_exec.sh -c 2 -m 4 -d 50 -s 22,3389
</code></pre>

<hr>

<h2 id="目录结构">🧱 目录结构</h2>

<pre><code>.
├── Auto_exec.sh       # 主脚本
├── Air_Nvidia.sh      # 管理脚本               
└── README.md          # 使用说明（本文件）
</code></pre>

<hr>

<h2 id="注意事项">🔐 注意事项</h2>

<ul>
  <li>首次运行会自动登录 NVIDIA Air 并获取 Token（仅本次有效）</li>
  <li>默认镜像为 <code>generic/ubuntu2204</code>，可修改脚本中的 <code>IMAGE_NAME</code></li>
  <li>所有 API 请求均为 HTTPS 安全通信</li>
  <li>若出现 <code>jq: error (at &lt;stdin&gt;:0)</code>，请重新登录（Token 可能过期）</li>
</ul>

<hr>

<h2 id="常见问题-faq">💬 常见问题 (FAQ)</h2>

<p><b>Q:</b> 为什么命令没执行？<br>🟢 请检查端口是否开放（默认 22）。</p>

<p><b>Q:</b> 为什么重复执行命令？<br>🟠 老版本问题，本脚本使用 <code>SSH_DONE[]</code> 阻止重复。</p>

<p><b>Q:</b> 如何修改 SSH 用户或密码？<br>编辑脚本顶部变量：</p>

<pre><code>SSH_USERNAME="ubuntu"
SSH_PASS="nvidia"
</code></pre>

<hr>

<h2 id="作者与维护">🧩 维护</h2>

<table>
  <tr><th>信息</th><th>内容</th></tr>

  <tr><td>🧾 版本</td><td>v4.0</td></tr>
  <tr><td>🖥️ 平台</td><td>Linux (x86_64 / ARM64)</td></tr>
  <tr><td>🗓️ 更新时间</td><td>2025-10-14</td></tr>
</table>

<hr>

<blockquote>
💡 如果你觉得这个项目有帮助，请点个 ⭐Star 支持一下！<br>
📬 有问题欢迎提交 Issue 或 PR 一起改进。
</blockquote>
