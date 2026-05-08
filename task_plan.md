# 任务计划：F2BHub — Fail2ban 多服务器封禁记录 Web 看板

## 目标
构建 Flask Web 应用，聚合查看多台服务器上原生 fail2ban 的封禁记录。

## 当前阶段
阶段 4 完成

## 各阶段

### 阶段 1：需求与方案分析
- [x] 确认需求：原生 fail2ban + Flask Web 只读展示 + 多服务器
- [x] 设计数据采集架构方案
- [x] 用户选择 Agent 推送方式
- **状态：** complete

### 阶段 2：方案选择与架构设计
- [x] 用户确认：Agent 推送 + 项目名 F2BHub
- [x] 确定项目结构与数据库设计
- [x] 记录技术决策
- **状态：** complete

### 阶段 3：数据采集层实现
- [x] Agent 脚本（fail2ban 日志解析 + HTTP 推送）
- [x] Flask API 接收端点
- [x] 数据写入中央 SQLite
- **状态：** complete

### 阶段 4：Flask Web 界面实现
- [x] Flask 应用搭建
- [x] 服务器列表 / 概览页
- [x] 封禁记录列表与筛选
- [x] 服务器详情页
- **状态：** complete

### 阶段 5：测试与验证
- [x] API 报告/心跳端点测试通过
- [x] 去重机制验证通过
- [x] Web 四个页面全部 200
- **状态：** complete

### 阶段 6：交付
- [x] 统一管理脚本 install.sh（7项菜单）
- [x] 远程 Agent 安装脚本（curl 一键）
- [x] Agent 安装脚本下载端点 /api/agent/install.sh
- **状态：** complete

## 已做决策
| 决策 | 理由 |
|------|------|
| 使用原生 fail2ban | 用户明确要求 |
| Flask 只做展示层 | 用户明确"只需要查看" |
| 多服务器聚合 | 用户需求 |
| Agent 推送采集 | 用户选择 |
| SQLite 中央存储 | 轻量，单文件 |
| 项目名 F2BHub | 用户选择 |

## 遇到的错误
| 错误 | 尝试次数 | 解决方案 |
|------|---------|---------|
| SQLite DateTime naive/aware 冲突 | 1 | is_online 中 strip tzinfo 再比较 |