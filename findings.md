# Fail2ban Web 看板 - 项目结构

## 目录结构

```
Fail2ban/
├── app/                        # Flask Web 应用（中央服务器）
│   ├── __init__.py
│   ├── models.py                # SQLAlchemy 数据模型
│   ├── api.py                   # Agent 数据推送接收 API
│   ├── views.py                 # Web 页面路由
│   ├── templates/
│   │   ├── base.html
│   │   ├── dashboard.html       # 概览页
│   │   ├── servers.html         # 服务器列表
│   │   ├── bans.html            # 封禁记录列表
│   │   └── server_detail.html   # 单服务器详情
│   └── static/
│       └── style.css
├── agent/                       # 部署到各被监控服务器
│   ├── f2b_agent.py             # Agent 主脚本
│   ├── agent.conf               # Agent 配置文件
│   └── install.sh              # 一键部署脚本
├── config.py                    # Flask 配置
├── run.py                       # 入口
├── requirements.txt
└── README.md
```

## 数据库设计 (SQLite)

### servers - 服务器表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK | 自增主键 |
| hostname | TEXT UNIQUE | 服务器主机名 |
| ip | TEXT | 服务器 IP |
| last_heartbeat | DATETIME | 最后一次收到数据时间 |
| created_at | DATETIME | 首次注册时间 |

### bans - 封禁记录表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK | 自增主键 |
| server_id | INTEGER FK | 关联 servers.id |
| jail | TEXT | fail2ban jail 名称 (sshd, nginx, etc.) |
| ip | TEXT | 被封禁的 IP |
| timestamp | DATETIME | 封禁时间 |
| reason | TEXT | 封禁原因/匹配的日志行 |
| unban_timestamp | DATETIME | 解封时间 (NULL=仍在封禁) |
| agent_hash | TEXT UNIQUE | 去重哈希 (jail+ip+timestamp) |

### 索引
- bans.server_id, bans.timestamp (按服务器+时间查询)
- bans.ip (按 IP 查询)
- bans.jail (按 jail 类型筛选)
- bans.agent_hash UNIQUE (Agent 推送去重)

## Agent 推送 API 设计

### POST /api/report
接收 Agent 推送的封禁记录

**请求体：**
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

**响应：**
```json
{
  "status": "ok",
  "received": 5,
  "duplicates": 1
}
```

### GET /api/heartbeat
Agent 心跳检测

## Agent 工作流程

1. 启动时读取 agent.conf 获取中央服务器地址
2. 回扫 fail2ban.log 获取历史记录，批量推送
3. tail -f 模式监听日志增量，实时推送新封禁
4. 每 60s 发送心跳
5. 通过 agent_hash (jail+ip+timestamp SHA256) 去重