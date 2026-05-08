# F2BHub — Fail2ban 多服务器封禁记录看板

集中化 Web 平台，聚合查看多台服务器上原生 fail2ban 的封禁记录。

## 架构

```
远程服务器                 中央服务器
┌─────────────┐           ┌──────────────────┐
│  fail2ban   │           │  Flask Web 面板   │
│  Agent 推送  │──HTTP──→  │  SQLite 中央存储   │
└─────────────┘           └──────────────────┘
```

- Agent 部署到各被监控服务器，解析 fail2ban 日志并推送到中央 Hub
- 中央 Hub 提供 Web 面板查看所有服务器的封禁状态

## 功能

- 多服务器封禁记录聚合展示
- 服务器在线状态监控（心跳检测）
- 封禁记录筛选（按 IP、Jail、状态）
- 安全威胁等级可视化（8 小时时间线）
- IP 地址脱敏显示
- Agent 一键远程安装

## 在线安装（推荐）

```bash
curl -sSL https://raw.githubusercontent.com/strobe111/Fail2ban/master/install.sh | bash
```

## 手动安装

```bash
git clone https://github.com/strobe111/Fail2ban.git
cd Fail2ban
chmod +x install.sh
./install.sh
```

安装脚本克隆仓库到 `/opt/F2BHub`，已有则 `git pull` 更新，然后启动管理菜单。

## 目录结构

```
Fail2ban/
├── app/                      # Flask Web 应用
│   ├── __init__.py           # 应用工厂
│   ├── api.py                # Agent 数据接收 API
│   ├── views.py              # Web 页面路由
│   ├── models.py             # 数据模型 (Server, Ban)
│   ├── templates/            # Jinja2 模板
│   │   ├── base.html         # 基础布局
│   │   ├── dashboard.html    # 概览页
│   │   ├── servers.html      # 服务器列表
│   │   ├── server_detail.html # 单服务器详情
│   │   └── bans.html         # 封禁记录列表
│   └── static/
│       └── style.css         # 暗色主题样式
├── agent/                    # 部署到远程服务器
│   ├── f2b_agent.py          # Agent 主脚本
│   ├── agent.conf            # Agent 配置模板
│   ├── f2b_agent_install.sh # Agent 远程一键安装脚本
│   └── test_fail2ban.log    # 测试日志
├── config.py                 # Flask 配置
├── run.py                    # 应用入口
├── install.sh                # 在线安装引导脚本
└── requirements.txt          # Python 依赖
```

## API 端点

| 端点 | 方法 | 认证 | 说明 |
|------|------|------|------|
| `/api/report` | POST | X-API-Key | Agent 推送封禁记录 |
| `/api/heartbeat` | POST | X-API-Key | Agent 心跳（60s 间隔） |
| `/api/agent/f2b_agent_install.sh` | GET | 无 | 下载 Agent 远程安装脚本 |

### POST /api/report

```json
{
  "hostname": "web-server-01",
  "ip": "10.0.1.5",
  "bans": [
    {
      "jail": "sshd",
      "ip": "1.2.3.4",
      "timestamp": "2026-05-07T10:30:00",
      "reason": "Invalid user admin from 1.2.3.4"
    }
  ]
}
```

通过 `agent_hash`（jail+ip+timestamp 的 SHA256）去重。

## Agent 工作流程

1. 读取 `agent.conf` 获取 Hub 地址和 API Key
2. 回扫 fail2ban.log 历史记录，批量推送
3. `tail -f` 模式监听增量日志，实时推送
4. 每 60s 发送心跳保持在线状态

## 添加远程服务器

在 F2BHub 管理菜单中选择"生成 Fail2ban Agent"，输入远程服务器信息后生成安装命令：

```bash
curl -sSL http://<HUB_IP>:5001/api/agent/f2b_agent_install.sh | bash -s -- \
  --hub http://<HUB_IP>:5001 \
  --api-key <API_KEY> \
  --hostname <SERVER_NAME>
```

## 技术栈

- Python 3 / Flask
- SQLAlchemy + SQLite
- 原生 fail2ban
- 暗色 GitHub 风格 UI
