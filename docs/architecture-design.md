# 销售数据分析 AI Agent - 系统架构设计文档

> 版本：1.0  
> 项目代号：salesAgent  
> 组织：com.zhuku

---

## 目录

1. [项目概述](#1-项目概述)
2. [系统架构总览](#2-系统架构总览)
3. [技术栈与版本](#3-技术栈与版本)
4. [后端分层架构](#4-后端分层架构)
5. [AI Agent 核心设计](#5-ai-agent-核心设计)
6. [数据库设计](#6-数据库设计)
7. [API 接口设计](#7-api-接口设计)
8. [安全与权限设计](#8-安全与权限设计)
9. [前端架构设计](#9-前端架构设计)
10. [缓存策略设计](#10-缓存策略设计)
11. [异常预警设计](#11-异常预警设计)
12. [部署方案](#12-部署方案)
13. [后端包结构规划](#13-后端包结构规划)
14. [前端目录结构规划](#14-前端目录结构规划)
15. [非功能性需求](#15-非功能性需求)

---

## 1. 项目概述

### 1.1 背景与痛点

当前后台系统的报表能力与业务需求之间存在严重脱节：每当业务侧提出新的数据查询需求，都需要开发团队编写新的接口、联调、测试、上线，周期长且成本高。

### 1.2 解决方案

构建一个基于大语言模型（LLM）的智能查询系统，其核心思路是：

- **将查询能力抽象为可复用的"工具集"（Tools）**，每个工具封装一类查询或分析能力
- **由 AI 模型理解用户自然语言意图**，自动选择并调用合适的工具
- **Tool Calling 机制**确保只要工具能力覆盖，用户任意问题都可自动处理，无需为每个新需求编写专门代码

### 1.3 核心功能

| 功能域 | 描述 |
|--------|------|
| 原始数据查询 | 按时间、客户、产品等维度检索原始订单记录 |
| 统计汇总分析 | 销售额统计、排名分析、占比计算等聚合功能 |
| 趋势分析 | 时间序列分析、同比环比计算、增长趋势预测 |
| 数据可视化 | 自动生成图表展示分析结果 |
| 异常预警 | 自动识别数据异常并发出预警通知 |
| 安全控制 | 拒绝超出业务范围的操作并给出合理解释 |

### 1.4 权限模型概述

| 角色 | 数据访问范围 |
|------|-------------|
| 销售员 | 仅限个人销售数据 |
| 销售主管（每大区一名） | 仅限所属大区销售数据 |
| 销售总监 | 全局数据访问权限 |

---

## 2. 系统架构总览

### 2.1 整体架构图（文本描述）

```
┌─────────────────────────────────────────────────────────────────┐
│                        用户层 (Browser)                         │
│                    Vue 3 + ECharts + Pinia                      │
└──────────────────────────┬──────────────────────────────────────┘
                           │ HTTP / SSE
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      接入层 (API Gateway)                       │
│          Spring Boot Controller + Sa-Token 认证过滤器            │
│                   统一响应封装 / 限流 / 日志                      │
└──────────────────────────┬──────────────────────────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
┌──────────────────┐ ┌──────────┐ ┌──────────────────┐
│  AI Agent 层     │ │ 业务服务层│ │  系统管理层       │
│  (LangChain4J)   │ │ (Service)│ │  (用户/角色/权限) │
│                  │ │          │ │                  │
│ ┌──────────────┐ │ │  报表服务 │ │  用户管理        │
│ │ AI Service   │ │ │  导出服务 │ │  角色管理        │
│ │ (Assistant)  │ │ │  预警服务 │ │  大区管理        │
│ └──────┬───────┘ │ │          │ │                  │
│        │         │ │          │ │                  │
│ ┌──────▼───────┐ │ │          │ │                  │
│ │ Tool Router  │ │ │          │ │                  │
│ │ (模型自动选择)│ │ │          │ │                  │
│ └──────┬───────┘ │ │          │ │                  │
│        │         │ │          │ │                  │
│ ┌──────▼───────┐ │ │          │ │                  │
│ │ Tools 工具集  │ │ │          │ │                  │
│ │ ┌──────────┐ │ │ │          │ │                  │
│ │ │订单查询   │ │ │ │          │ │                  │
│ │ │统计汇总   │ │ │ │          │ │                  │
│ │ │趋势分析   │ │ │ │          │ │                  │
│ │ │异常检测   │ │ │ │          │ │                  │
│ │ │图表生成   │ │ │ │          │ │                  │
│ │ └──────────┘ │ │ │          │ │                  │
│ └──────────────┘ │ │          │ │                  │
└────────┬─────────┘ └────┬─────┘ └────────┬─────────┘
         │                │                │
         └────────────────┼────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    数据访问层 (Repository)                       │
│               MyBatis-Plus + 数据权限拦截器                      │
└──────────────────────────┬──────────────────────────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │ MySQL 8  │ │  Redis   │ │ LLM API  │
        │ 业务数据  │ │ 缓存/会话 │ │ (外部)   │
        └──────────┘ └──────────┘ └──────────┘
```

### 2.2 核心交互流程

```
用户输入自然语言
       │
       ▼
 Controller 接收请求，Sa-Token 校验身份和权限
       │
       ▼
 注入当前用户上下文（userId, role, regionId）到 Tool 执行环境
       │
       ▼
 AI Service 将用户消息 + System Prompt + 用户上下文发送给 LLM
       │
       ▼
 LLM 分析意图，决定调用哪个/哪些 Tool（或直接拒绝）
       │
       ▼
 Tool 执行查询（自动附加数据权限过滤条件）
       │
       ▼
 Tool 返回结果给 LLM
       │
       ▼
 LLM 综合结果生成自然语言回答 + 可选的图表数据结构
       │
       ▼
 Controller 返回结构化响应（文本 + 图表配置）给前端
       │
       ▼
 前端渲染文本回答 + ECharts 图表
```

---

## 3. 技术栈与版本

### 3.1 后端技术栈

| 技术 | 版本 | 用途 |
|------|------|------|
| Java | 21 | 运行时环境 |
| Spring Boot | 3.5.11 | 应用框架 |
| LangChain4J | 1.12.1 | AI Agent 框架，Tool Calling 核心 |
| langchain4j-spring-boot-starter | 1.12.1 | LangChain4J Spring Boot 自动配置 |
| MySQL | 8.0+ | 主数据存储 |
| MyBatis-Plus | 3.5.x | ORM 框架，支持数据权限插件 |
| Redis | 7.x | 缓存、会话存储、限流 |
| Sa-Token | 1.39.x | 认证授权框架 |
| Hutool | 5.8.x | 工具类库 |
| MapStruct | 1.5.x | 对象映射 |
| Knife4j | 4.x | API 文档 |

### 3.2 前端技术栈

| 技术 | 版本 | 用途 |
|------|------|------|
| Vue | 3.5.x | UI 框架 |
| Vite | 8.x | 构建工具 |
| Vue Router | 5.x | 路由管理 |
| Pinia | 3.x | 状态管理 |
| ECharts | 5.x | 数据可视化 |
| Axios | 1.x | HTTP 客户端 |
| Element Plus | 2.x | UI 组件库 |

---

## 4. 后端分层架构

### 4.1 分层总览

```
controller     → 接入层：接收 HTTP 请求，参数校验，响应封装
    │
service        → 业务逻辑层：业务编排，事务管理
    │
agent          → AI Agent 层：LangChain4J 集成，Tool 定义与执行
    │
repository     → 数据访问层：MyBatis-Plus Mapper，数据权限拦截
    │
infrastructure → 基础设施层：Redis, Sa-Token, LLM Client 配置
```

### 4.2 各层职责

**Controller 层**
- 接收并校验前端请求参数
- 调用 Service 层处理业务逻辑
- 统一包装返回结果（`R<T>` 统一响应体）
- 不包含业务逻辑

**Service 层**
- 编排业务流程
- 管理事务边界
- 调用 Agent 层进行 AI 对话
- 调用 Repository 层进行数据操作

**Agent 层（核心）**
- 定义 AI Service 接口（`SalesAssistant`）
- 定义各业务 Tool 组件
- 管理 Chat Memory（对话记忆）
- 构建 System Prompt（含用户角色、权限上下文）
- 处理 Tool 调用结果的格式化

**Repository 层**
- MyBatis-Plus Mapper 接口
- 数据权限自动拦截（通过 MyBatis-Plus 插件）
- 复杂 SQL 查询的 XML 映射

**Infrastructure 层**
- Redis 配置与工具类
- Sa-Token 配置
- LLM 客户端配置（API Key、模型参数）
- 全局异常处理器
- 跨域配置

---

## 5. AI Agent 核心设计

### 5.1 LangChain4J 集成架构

本项目的核心创新在于利用 LangChain4J 的 **Tool Calling** 机制，将传统的"一问一码"模式转变为"一次定义、无限复用"模式。

#### 5.1.1 AI Service 定义

```java
@AiService
public interface SalesAssistant {

    @SystemMessage(fromResource = "prompts/sales-assistant-system.txt")
    String chat(@MemoryId String sessionId, @UserMessage String userMessage);
}
```

- `@AiService`：Spring Boot 启动时自动扫描并生成代理实现
- `@MemoryId`：按会话 ID 隔离对话记忆，支持多用户并发
- `@SystemMessage`：从资源文件加载系统提示词，便于维护

#### 5.1.2 System Prompt 设计

System Prompt 是控制 AI 行为的关键。需包含以下内容：

```
你是一个专业的销售数据分析助手。你的职责是帮助用户查询和分析销售数据。

## 你的能力
- 查询原始销售订单数据
- 进行销售统计汇总（销售额、数量、排名、占比等）
- 进行趋势分析（同比、环比、时间序列）
- 识别数据异常

## 行为准则
- 仅回答与销售数据分析相关的问题
- 对于超出能力范围的请求（如发邮件、修改订单、删除数据等），礼貌拒绝并解释原因
- 在调用工具前，先确认用户意图是否清晰，必要时追问
- 返回数据时，同时提供文字总结和图表建议
- 严格遵守数据权限，不得查询用户权限范围外的数据

## 当前用户上下文
- 用户ID：{{userId}}
- 角色：{{role}}
- 大区ID：{{regionId}}（若适用）

请基于以上上下文处理用户请求，所有数据查询工具已自动应用权限过滤。
```

> **注意**：`{{userId}}`、`{{role}}`、`{{regionId}}` 为运行时动态注入的变量，每次对话前由 Service 层根据当前登录用户填充。

#### 5.1.3 ChatMemory 配置

```java
@Bean
ChatMemoryProvider chatMemoryProvider() {
    return sessionId -> MessageWindowChatMemory.builder()
            .id(sessionId)
            .maxMessages(20)       // 保留最近20轮对话
            .chatMemoryStore(redisChatMemoryStore())  // Redis 持久化
            .build();
}
```

- 使用 Redis 持久化对话记忆，支持服务重启后恢复
- 每个 sessionId 独立维护对话窗口
- `maxMessages=20` 控制上下文长度，避免 Token 超限

### 5.2 Tool 工具集设计

所有 Tool 均为 Spring `@Component`，由 LangChain4J 自动发现并注册。每个 Tool 方法通过 `@Tool` 注解描述其能力，LLM 根据描述自动决策调用。

#### 5.2.1 工具清单

| 工具类 | 工具方法 | 功能描述 |
|--------|---------|---------|
| `OrderQueryTool` | `queryOrders` | 按条件查询原始订单列表（支持时间、客户、产品、状态等筛选） |
| `OrderQueryTool` | `getOrderDetail` | 查询单个订单详情 |
| `SalesStatsTool` | `calcSalesAmount` | 计算指定条件下的销售总额、订单数、平均客单价 |
| `SalesStatsTool` | `calcSalesRanking` | 按产品/客户/销售员/大区维度进行排名分析 |
| `SalesStatsTool` | `calcSalesProportion` | 计算各维度的销售占比 |
| `TrendAnalysisTool` | `calcTimeSeries` | 按天/周/月/季/年粒度生成时间序列数据 |
| `TrendAnalysisTool` | `calcYearOverYear` | 同比分析 |
| `TrendAnalysisTool` | `calcMonthOverMonth` | 环比分析 |
| `TrendAnalysisTool` | `calcGrowthRate` | 增长率计算 |
| `AnomalyDetectionTool` | `detectAnomalies` | 基于统计规则检测销售数据异常 |
| `ChartDataTool` | `generateChartConfig` | 根据数据和分析类型生成 ECharts 配置 |
| `DateTool` | `getCurrentDate` | 获取当前日期（供 LLM 计算"本月""近7天"等相对时间） |

#### 5.2.2 Tool 定义示例

```java
@Component
public class OrderQueryTool {

    private final OrderService orderService;
    private final UserContextHolder userContextHolder;

    @Tool("按条件查询销售订单列表。支持按时间范围、客户名称、产品名称、订单状态等条件筛选。" +
          "返回订单编号、下单时间、客户、产品、数量、金额等信息。最多返回100条记录。")
    public List<OrderVO> queryOrders(
            @P("开始日期，格式 yyyy-MM-dd，可选") String startDate,
            @P("结束日期，格式 yyyy-MM-dd，可选") String endDate,
            @P("客户名称关键字，可选") String customerName,
            @P("产品名称关键字，可选") String productName,
            @P("订单状态：PENDING/CONFIRMED/SHIPPED/COMPLETED/CANCELLED，可选") String status,
            @P("返回记录数上限，默认20，最大100") Integer limit) {

        // 从上下文获取当前用户权限信息，自动注入数据过滤条件
        UserContext ctx = userContextHolder.get();
        OrderQueryParam param = buildQueryParam(startDate, endDate,
            customerName, productName, status, limit, ctx);
        return orderService.queryOrders(param);
    }
}
```

```java
@Component
public class SalesStatsTool {

    @Tool("计算指定条件下的销售统计汇总，包括销售总额、订单总数、平均客单价。" +
          "支持按时间范围、产品类别、客户、大区等维度过滤。")
    public SalesStatsVO calcSalesAmount(
            @P("开始日期，格式 yyyy-MM-dd") String startDate,
            @P("结束日期，格式 yyyy-MM-dd") String endDate,
            @P("产品类别名称，可选") String category,
            @P("客户名称，可选") String customerName) {
        // ...
    }

    @Tool("按指定维度进行销售排名分析。可按产品、客户、销售员、大区排名。" +
          "返回排名列表，包含名称、销售额、订单数、排名位次。")
    public List<RankingVO> calcSalesRanking(
            @P("排名维度：PRODUCT/CUSTOMER/SALESPERSON/REGION") String dimension,
            @P("开始日期，格式 yyyy-MM-dd") String startDate,
            @P("结束日期，格式 yyyy-MM-dd") String endDate,
            @P("返回前N名，默认10") Integer topN) {
        // ...
    }
}
```

```java
@Component
public class TrendAnalysisTool {

    @Tool("按时间粒度生成销售趋势数据。用于观察销售额随时间的变化。" +
          "返回时间点列表及对应的销售额、订单数。")
    public TimeSeriesVO calcTimeSeries(
            @P("开始日期，格式 yyyy-MM-dd") String startDate,
            @P("结束日期，格式 yyyy-MM-dd") String endDate,
            @P("时间粒度：DAY/WEEK/MONTH/QUARTER/YEAR") String granularity,
            @P("产品类别筛选，可选") String category) {
        // ...
    }

    @Tool("计算同比数据。将当前周期数据与去年同期进行对比，返回变化量和变化率。")
    public ComparisonVO calcYearOverYear(
            @P("对比周期，格式 yyyy-MM，表示月份") String period,
            @P("统计维度：AMOUNT/ORDER_COUNT/AVG_PRICE") String metric) {
        // ...
    }
}
```

```java
@Component
public class ChartDataTool {

    @Tool("根据分析结果生成 ECharts 图表配置。前端可直接使用该配置渲染图表。" +
          "支持折线图、柱状图、饼图、组合图。")
    public ChartConfigVO generateChartConfig(
            @P("图表类型：LINE/BAR/PIE/MIXED") String chartType,
            @P("图表标题") String title,
            @P("JSON 格式的数据，包含 labels 和 datasets") String dataJson) {
        // ...
    }
}
```

#### 5.2.3 用户上下文传递机制

Tool 的数据权限控制依赖于 **用户上下文（UserContext）** 的正确传递：

```
HTTP 请求进入
    │
    ▼
Sa-Token 过滤器校验 Token，获取 userId
    │
    ▼
UserContextInterceptor 从数据库/缓存加载用户完整信息
（userId, role, regionId, managedSalesIds 等）
    │
    ▼
存入 ThreadLocal (UserContextHolder)
    │
    ▼
Tool 方法执行时从 UserContextHolder 读取上下文
    │
    ▼
数据访问层根据上下文自动附加权限 WHERE 条件
    │
    ▼
请求结束，清理 ThreadLocal
```

#### 5.2.4 Tool 安全边界

System Prompt 中明确限制 AI 只能进行数据查询和分析，配合以下机制确保安全：

1. **Tool 白名单**：系统中只注册查询类 Tool，不存在修改/删除类 Tool
2. **System Prompt 指令**：明确告知 LLM 拒绝写操作请求
3. **参数校验**：每个 Tool 方法内部对参数进行合法性校验
4. **SQL 注入防护**：所有数据查询通过 MyBatis-Plus 参数化查询，不拼接 SQL

### 5.3 LLM 模型配置

```yaml
# application.yaml 中 LangChain4J 配置示例
langchain4j:
  open-ai:
    chat-model:
      api-key: ${LLM_API_KEY}
      base-url: ${LLM_BASE_URL}     # 支持兼容 OpenAI 协议的国产模型
      model-name: ${LLM_MODEL_NAME}
      temperature: 0.1               # 低温度，确保查询准确性
      max-tokens: 4096
      timeout: 60s
```

> 采用 OpenAI 兼容协议配置，便于切换不同 LLM 提供商（如通义千问、DeepSeek、GLM 等）。

---

## 6. 数据库设计

### 6.1 ER 关系概览

```
sys_user ──┬── sys_user_role ──── sys_role
           │
           └── sys_region (通过 region_id 关联)
                   │
sales_order ───────┤ (关联 region)
    │              │
    ├── sales_order_item ── product ── product_category
    │
    └── customer

chat_session ── chat_message

alert_rule ── alert_record
```

### 6.2 表结构详细设计

#### 6.2.1 系统管理表

**sys_user（系统用户表）**

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK, AUTO_INCREMENT | 用户ID |
| username | VARCHAR(50) | UNIQUE, NOT NULL | 登录用户名 |
| password | VARCHAR(255) | NOT NULL | 加密密码（BCrypt） |
| real_name | VARCHAR(50) | NOT NULL | 真实姓名 |
| phone | VARCHAR(20) | | 手机号 |
| email | VARCHAR(100) | | 邮箱 |
| region_id | BIGINT | FK → sys_region.id, NULLABLE | 所属大区（销售员和主管） |
| status | TINYINT | NOT NULL, DEFAULT 1 | 状态：0-禁用 1-启用 |
| created_at | DATETIME | NOT NULL | 创建时间 |
| updated_at | DATETIME | NOT NULL | 更新时间 |

**sys_role（角色表）**

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK, AUTO_INCREMENT | 角色ID |
| role_code | VARCHAR(50) | UNIQUE, NOT NULL | 角色编码（SALESPERSON/MANAGER/DIRECTOR） |
| role_name | VARCHAR(50) | NOT NULL | 角色名称 |
| description | VARCHAR(255) | | 角色描述 |
| created_at | DATETIME | NOT NULL | 创建时间 |

**sys_user_role（用户角色关联表）**

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK, AUTO_INCREMENT | 主键ID |
| user_id | BIGINT | FK → sys_user.id, NOT NULL | 用户ID |
| role_id | BIGINT | FK → sys_role.id, NOT NULL | 角色ID |

索引：`UNIQUE INDEX uk_user_role (user_id, role_id)`

**sys_region（销售大区表）**

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK, AUTO_INCREMENT | 大区ID |
| region_name | VARCHAR(50) | UNIQUE, NOT NULL | 大区名称 |
| region_code | VARCHAR(20) | UNIQUE, NOT NULL | 大区编码 |
| manager_id | BIGINT | FK → sys_user.id, NULLABLE | 大区主管用户ID |
| status | TINYINT | NOT NULL, DEFAULT 1 | 状态 |
| created_at | DATETIME | NOT NULL | 创建时间 |
| updated_at | DATETIME | NOT NULL | 更新时间 |

#### 6.2.2 业务核心表

**customer（客户表）**

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK, AUTO_INCREMENT | 客户ID |
| customer_name | VARCHAR(100) | NOT NULL | 客户名称 |
| customer_code | VARCHAR(50) | UNIQUE, NOT NULL | 客户编码 |
| contact_person | VARCHAR(50) | | 联系人 |
| contact_phone | VARCHAR(20) | | 联系电话 |
| address | VARCHAR(255) | | 地址 |
| region_id | BIGINT | FK → sys_region.id | 所属大区 |
| status | TINYINT | NOT NULL, DEFAULT 1 | 状态 |
| created_at | DATETIME | NOT NULL | 创建时间 |
| updated_at | DATETIME | NOT NULL | 更新时间 |

**product_category（产品类别表）**

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK, AUTO_INCREMENT | 类别ID |
| category_name | VARCHAR(50) | NOT NULL | 类别名称 |
| category_code | VARCHAR(20) | UNIQUE, NOT NULL | 类别编码 |
| parent_id | BIGINT | NULLABLE | 父类别ID（支持多级分类） |
| sort_order | INT | DEFAULT 0 | 排序号 |
| created_at | DATETIME | NOT NULL | 创建时间 |

**product（产品表）**

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK, AUTO_INCREMENT | 产品ID |
| product_name | VARCHAR(100) | NOT NULL | 产品名称 |
| product_code | VARCHAR(50) | UNIQUE, NOT NULL | 产品编码 |
| category_id | BIGINT | FK → product_category.id | 所属类别 |
| unit | VARCHAR(20) | | 计量单位 |
| price | DECIMAL(12,2) | NOT NULL | 标准单价 |
| status | TINYINT | NOT NULL, DEFAULT 1 | 状态：0-下架 1-上架 |
| created_at | DATETIME | NOT NULL | 创建时间 |
| updated_at | DATETIME | NOT NULL | 更新时间 |

**sales_order（销售订单主表）**

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK, AUTO_INCREMENT | 订单ID |
| order_no | VARCHAR(32) | UNIQUE, NOT NULL | 订单编号 |
| customer_id | BIGINT | FK → customer.id, NOT NULL | 客户ID |
| salesperson_id | BIGINT | FK → sys_user.id, NOT NULL | 销售员ID |
| region_id | BIGINT | FK → sys_region.id, NOT NULL | 所属大区 |
| order_date | DATE | NOT NULL | 下单日期 |
| total_amount | DECIMAL(14,2) | NOT NULL | 订单总金额 |
| status | VARCHAR(20) | NOT NULL | 订单状态 |
| remark | VARCHAR(500) | | 备注 |
| created_at | DATETIME | NOT NULL | 创建时间 |
| updated_at | DATETIME | NOT NULL | 更新时间 |

订单状态枚举：`PENDING`（待确认）、`CONFIRMED`（已确认）、`SHIPPED`（已发货）、`COMPLETED`（已完成）、`CANCELLED`（已取消）

**sales_order_item（销售订单明细表）**

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK, AUTO_INCREMENT | 明细ID |
| order_id | BIGINT | FK → sales_order.id, NOT NULL | 订单ID |
| product_id | BIGINT | FK → product.id, NOT NULL | 产品ID |
| quantity | INT | NOT NULL | 数量 |
| unit_price | DECIMAL(12,2) | NOT NULL | 成交单价 |
| subtotal | DECIMAL(14,2) | NOT NULL | 小计金额 |

#### 6.2.3 AI 对话表

**chat_session（对话会话表）**

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK, AUTO_INCREMENT | 会话ID |
| session_id | VARCHAR(36) | UNIQUE, NOT NULL | 会话UUID |
| user_id | BIGINT | FK → sys_user.id, NOT NULL | 所属用户 |
| title | VARCHAR(100) | | 会话标题（自动生成或用户自定义） |
| status | TINYINT | NOT NULL, DEFAULT 1 | 状态：0-已归档 1-活跃 |
| created_at | DATETIME | NOT NULL | 创建时间 |
| updated_at | DATETIME | NOT NULL | 最后活跃时间 |

**chat_message（对话消息表）**

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK, AUTO_INCREMENT | 消息ID |
| session_id | VARCHAR(36) | NOT NULL | 所属会话 |
| role | VARCHAR(20) | NOT NULL | 消息角色：USER / ASSISTANT / TOOL |
| content | TEXT | NOT NULL | 消息内容 |
| tool_name | VARCHAR(50) | NULLABLE | Tool 调用名称（仅 TOOL 角色） |
| tool_input | TEXT | NULLABLE | Tool 调用输入参数（JSON） |
| chart_config | TEXT | NULLABLE | 图表配置（JSON，仅 ASSISTANT 角色可能携带） |
| tokens_used | INT | | 本次消耗的 Token 数 |
| created_at | DATETIME | NOT NULL | 创建时间 |

#### 6.2.4 预警表

**alert_rule（预警规则表）**

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK, AUTO_INCREMENT | 规则ID |
| rule_name | VARCHAR(100) | NOT NULL | 规则名称 |
| rule_type | VARCHAR(30) | NOT NULL | 规则类型 |
| metric | VARCHAR(50) | NOT NULL | 监控指标 |
| operator | VARCHAR(10) | NOT NULL | 比较运算符 |
| threshold | DECIMAL(14,2) | NOT NULL | 阈值 |
| time_window | VARCHAR(20) | NOT NULL | 时间窗口 |
| dimension | VARCHAR(50) | | 监控维度 |
| notify_roles | VARCHAR(255) | | 通知角色（逗号分隔） |
| status | TINYINT | NOT NULL, DEFAULT 1 | 状态 |
| created_at | DATETIME | NOT NULL | 创建时间 |
| updated_at | DATETIME | NOT NULL | 更新时间 |

规则类型枚举：
- `AMOUNT_DROP` - 销售额下降
- `AMOUNT_SPIKE` - 销售额异常飙升
- `ORDER_DROP` - 订单量下降
- `ZERO_SALES` - 零销售预警
- `CUSTOM` - 自定义规则

**alert_record（预警记录表）**

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK, AUTO_INCREMENT | 记录ID |
| rule_id | BIGINT | FK → alert_rule.id, NOT NULL | 触发的规则 |
| alert_level | VARCHAR(10) | NOT NULL | 预警级别：INFO/WARN/CRITICAL |
| title | VARCHAR(200) | NOT NULL | 预警标题 |
| content | TEXT | NOT NULL | 预警详情 |
| metric_value | DECIMAL(14,2) | | 触发时的指标值 |
| threshold_value | DECIMAL(14,2) | | 阈值 |
| status | TINYINT | NOT NULL, DEFAULT 0 | 处理状态：0-未处理 1-已处理 2-已忽略 |
| handled_by | BIGINT | NULLABLE | 处理人 |
| handled_at | DATETIME | NULLABLE | 处理时间 |
| created_at | DATETIME | NOT NULL | 预警时间 |

### 6.3 核心索引设计

```sql
-- sales_order 高频查询索引
CREATE INDEX idx_order_date ON sales_order(order_date);
CREATE INDEX idx_order_salesperson ON sales_order(salesperson_id, order_date);
CREATE INDEX idx_order_region ON sales_order(region_id, order_date);
CREATE INDEX idx_order_customer ON sales_order(customer_id, order_date);
CREATE INDEX idx_order_status ON sales_order(status, order_date);

-- sales_order_item 关联查询索引
CREATE INDEX idx_item_order ON sales_order_item(order_id);
CREATE INDEX idx_item_product ON sales_order_item(product_id);

-- chat_message 会话查询索引
CREATE INDEX idx_msg_session ON chat_message(session_id, created_at);

-- chat_session 用户查询索引
CREATE INDEX idx_session_user ON chat_session(user_id, updated_at DESC);

-- alert_record 查询索引
CREATE INDEX idx_alert_status ON alert_record(status, created_at DESC);
CREATE INDEX idx_alert_rule ON alert_record(rule_id, created_at DESC);

-- sys_user 大区查询索引
CREATE INDEX idx_user_region ON sys_user(region_id);
```

### 6.4 数据权限 SQL 示例

不同角色查询 `sales_order` 时，数据访问层自动追加的 WHERE 条件：

```sql
-- 销售员：仅查看个人数据
WHERE salesperson_id = #{currentUserId}

-- 销售主管：仅查看本大区数据
WHERE region_id = #{currentUserRegionId}

-- 销售总监：无额外限制（全局访问）
-- 不追加额外 WHERE 条件
```

---

## 7. API 接口设计

### 7.1 统一响应格式

```json
{
  "code": 200,
  "message": "success",
  "data": { },
  "timestamp": 1714300000000
}
```

错误响应：

```json
{
  "code": 401,
  "message": "未登录或登录已过期",
  "data": null,
  "timestamp": 1714300000000
}
```

### 7.2 接口清单

#### 7.2.1 认证模块 `/api/auth`

| 方法 | 路径 | 说明 | 认证 |
|------|------|------|------|
| POST | `/api/auth/login` | 用户登录 | 否 |
| POST | `/api/auth/logout` | 用户登出 | 是 |
| GET | `/api/auth/me` | 获取当前用户信息 | 是 |

**POST /api/auth/login**

请求：
```json
{
  "username": "string",
  "password": "string"
}
```

响应 data：
```json
{
  "token": "xxxx-xxxx-xxxx",
  "userInfo": {
    "id": 1,
    "username": "zhangsan",
    "realName": "张三",
    "role": "SALESPERSON",
    "regionId": 1,
    "regionName": "华东大区"
  }
}
```

#### 7.2.2 AI 对话模块 `/api/chat`

| 方法 | 路径 | 说明 | 认证 |
|------|------|------|------|
| POST | `/api/chat/send` | 发送对话消息 | 是 |
| GET | `/api/chat/send/stream` | SSE 流式对话（可选） | 是 |
| GET | `/api/chat/sessions` | 获取用户会话列表 | 是 |
| POST | `/api/chat/sessions` | 创建新会话 | 是 |
| GET | `/api/chat/sessions/{sessionId}/messages` | 获取会话历史消息 | 是 |
| DELETE | `/api/chat/sessions/{sessionId}` | 删除会话 | 是 |

**POST /api/chat/send**

请求：
```json
{
  "sessionId": "uuid-string",
  "message": "本月华东大区的销售额是多少？"
}
```

响应 data：
```json
{
  "sessionId": "uuid-string",
  "reply": "本月华东大区的销售总额为 ¥1,258,600.00，共计 326 笔订单，平均客单价 ¥3,860.74。",
  "charts": [
    {
      "chartType": "BAR",
      "title": "本月华东大区销售额Top10产品",
      "config": { }
    }
  ],
  "toolCalls": [
    {
      "toolName": "calcSalesAmount",
      "input": {"startDate":"2026-04-01","endDate":"2026-04-28","region":"华东大区"},
      "duration": 120
    }
  ]
}
```

> `charts` 为可选字段，AI 判断需要图表展示时才返回。`config` 为完整的 ECharts option 对象，前端直接渲染。
> `toolCalls` 为可选的调试/透明字段，记录 AI 调用了哪些工具，可在前端展示为"思考过程"。

**GET /api/chat/send/stream（SSE 流式响应）**

对于需要较长时间处理的请求，支持 Server-Sent Events 流式返回：

```
GET /api/chat/send/stream?sessionId=xxx&message=yyy

-- SSE 事件流 --
event: thinking
data: {"step": "正在分析您的问题..."}

event: tool_call
data: {"toolName": "calcSalesAmount", "status": "executing"}

event: tool_result
data: {"toolName": "calcSalesAmount", "status": "completed", "duration": 120}

event: message
data: {"content": "本月华东大区的销售", "finished": false}

event: message
data: {"content": "总额为...", "finished": false}

event: complete
data: {"reply": "完整回复...", "charts": [...]}
```

#### 7.2.3 预警模块 `/api/alerts`

| 方法 | 路径 | 说明 | 认证 |
|------|------|------|------|
| GET | `/api/alerts` | 获取预警记录列表 | 是 |
| GET | `/api/alerts/{id}` | 获取预警详情 | 是 |
| PUT | `/api/alerts/{id}/handle` | 处理预警 | 是 |
| GET | `/api/alerts/rules` | 获取预警规则列表 | 是（主管+） |
| POST | `/api/alerts/rules` | 创建预警规则 | 是（总监） |
| PUT | `/api/alerts/rules/{id}` | 更新预警规则 | 是（总监） |

#### 7.2.4 系统管理模块 `/api/system`

| 方法 | 路径 | 说明 | 认证 |
|------|------|------|------|
| GET | `/api/system/users` | 用户列表 | 是（总监） |
| POST | `/api/system/users` | 创建用户 | 是（总监） |
| PUT | `/api/system/users/{id}` | 更新用户 | 是（总监） |
| GET | `/api/system/regions` | 大区列表 | 是 |
| GET | `/api/system/products` | 产品列表 | 是 |
| GET | `/api/system/customers` | 客户列表 | 是 |

### 7.3 请求头规范

| Header | 说明 |
|--------|------|
| `Authorization` | Sa-Token 令牌，格式 `Bearer {token}` |
| `Content-Type` | `application/json` |
| `Accept` | `application/json` 或 `text/event-stream`（SSE） |

---

## 8. 安全与权限设计

### 8.1 认证方案（Sa-Token）

```
登录流程：
  用户名 + 密码 → BCrypt 验证 → StpUtil.login(userId) → 返回 Token

鉴权流程：
  请求携带 Token → Sa-Token 拦截器校验 → 注入 UserContext → 业务处理

Token 存储：
  Token 存储于 Redis，支持：
  - Token 有效期配置（默认 7 天）
  - 支持"记住我"延长有效期
  - 支持踢人下线
  - 支持同端互斥登录
```

### 8.2 RBAC 权限模型

```
                    ┌──────────────────────────────┐
                    │         权限控制层            │
                    └──────────────┬───────────────┘
                                   │
          ┌────────────────────────┼────────────────────────┐
          │                        │                        │
   ┌──────▼──────┐          ┌─────▼──────┐          ┌──────▼──────┐
   │  接口权限    │          │  数据权限   │          │  功能权限    │
   │ (URL级别)   │          │ (行级别)   │          │ (按钮级别)   │
   └──────┬──────┘          └─────┬──────┘          └──────┬──────┘
          │                       │                        │
   Sa-Token 注解          MyBatis-Plus         前端 v-permission
   @SaCheckRole          DataPermission             指令
   @SaCheckPermission     拦截器插件
```

#### 8.2.1 角色定义

| 角色编码 | 角色名称 | 接口权限 | 数据权限 |
|----------|---------|---------|---------|
| SALESPERSON | 销售员 | 对话、个人数据查看 | 仅个人数据 |
| MANAGER | 销售主管 | 对话、大区数据查看、预警查看 | 本大区数据 |
| DIRECTOR | 销售总监 | 全部功能 | 全局数据 |

#### 8.2.2 数据权限拦截器

采用 MyBatis-Plus 拦截器插件实现自动数据过滤：

```java
/**
 * 数据权限拦截器 - 自动为 SQL 追加数据过滤条件
 *
 * 原理：在 MyBatis 执行 SQL 前，根据当前用户角色动态修改 WHERE 条件
 */
@Component
public class DataPermissionInterceptor implements InnerInterceptor {

    @Override
    public void beforeQuery(Executor executor, MappedStatement ms,
                            Object parameter, ...) {
        UserContext ctx = UserContextHolder.get();
        if (ctx == null) return;

        switch (ctx.getRole()) {
            case SALESPERSON:
                // 追加 WHERE salesperson_id = #{userId}
                appendCondition("salesperson_id", ctx.getUserId());
                break;
            case MANAGER:
                // 追加 WHERE region_id = #{regionId}
                appendCondition("region_id", ctx.getRegionId());
                break;
            case DIRECTOR:
                // 不追加条件，全局访问
                break;
        }
    }
}
```

> 该拦截器对 Tool 层透明——Tool 只需正常查询，拦截器自动处理数据隔离。

### 8.3 AI 安全边界

#### 8.3.1 操作安全

| 威胁 | 防护措施 |
|------|---------|
| 用户要求执行写操作（改/删） | System Prompt 明确限制 + 系统内无写操作 Tool |
| 用户要求发送邮件/通知 | System Prompt 限制 + 无相关 Tool |
| Prompt 注入攻击 | System Prompt 加固 + 输入内容过滤 |
| 数据越权访问 | 数据权限拦截器在 DB 层强制过滤 |
| SQL 注入 | MyBatis-Plus 参数化查询，禁止 SQL 拼接 |

#### 8.3.2 输入过滤

```java
/**
 * 用户消息预处理 - 在发送给 LLM 前进行安全过滤
 */
public class MessageSanitizer {
    // 过滤明显的 Prompt 注入模式
    // 过滤包含系统命令的文本
    // 限制消息最大长度（如 2000 字符）
    // 检测并阻止尝试覆盖 System Prompt 的行为
}
```

#### 8.3.3 输出审核

```java
/**
 * AI 回复后处理 - 检查输出内容安全性
 */
public class ResponseAuditor {
    // 检查回复中是否泄露了系统内部信息
    // 过滤可能的敏感数据（如完整手机号、邮箱等）
    // 记录所有 Tool 调用日志用于审计
}
```

### 8.4 接口限流

通过 Redis + Sa-Token 实现接口限流：

| 接口 | 限流策略 |
|------|---------|
| `/api/auth/login` | 同一 IP 每分钟最多 10 次 |
| `/api/chat/send` | 同一用户每分钟最多 20 次 |
| `/api/chat/send/stream` | 同一用户并发最多 1 个 SSE 连接 |

---

## 9. 前端架构设计

### 9.1 页面结构

```
┌─────────────────────────────────────────────┐
│                   顶部导航栏                 │
│  Logo │ 导航菜单 │ 预警通知 │ 用户头像/登出  │
├────────┬────────────────────────────────────┤
│        │                                    │
│  侧边  │           主内容区                  │
│  会话  │                                    │
│  列表  │  ┌──────────────────────────────┐  │
│        │  │                              │  │
│  历史  │  │       对话消息区域            │  │
│  会话  │  │  (文本 + 图表混合渲染)       │  │
│  列表  │  │                              │  │
│        │  │                              │  │
│  新建  │  ├──────────────────────────────┤  │
│  会话  │  │       消息输入框             │  │
│  按钮  │  │  [输入框..................]   │  │
│        │  │  [发送按钮]                  │  │
│        │  └──────────────────────────────┘  │
└────────┴────────────────────────────────────┘
```

### 9.2 核心页面

| 页面 | 路由 | 说明 |
|------|------|------|
| 登录页 | `/login` | 用户名密码登录 |
| AI 对话主页 | `/chat` | 核心交互页面 |
| 预警中心 | `/alerts` | 预警列表和处理 |
| 系统管理 | `/system/*` | 用户/角色/大区管理（总监可见） |

### 9.3 消息渲染策略

对话区域需要支持混合内容渲染：

```
┌─────────────────────────────────────────┐
│ 👤 用户：本月各产品类别的销售占比是多少？   │
├─────────────────────────────────────────┤
│ 🤖 AI：                                 │
│                                         │
│ 本月各产品类别的销售占比分析如下：         │
│                                         │
│  ┌─────────────────────────┐            │
│  │     [ECharts 饼图]      │            │
│  │   电子产品 35.2%         │            │
│  │   办公用品 28.7%         │            │
│  │   原材料   22.1%         │            │
│  │   其他    14.0%          │            │
│  └─────────────────────────┘            │
│                                         │
│ 电子产品类别以35.2%的占比居首...           │
│                                         │
│ 💡 思考过程（可展开）                     │
│   ├─ 调用 calcSalesProportion (120ms)   │
│   └─ 调用 generateChartConfig (45ms)    │
└─────────────────────────────────────────┘
```

### 9.4 前端与后端交互

```
                 Axios 请求拦截器
                    │
                    ├─ 自动附加 Authorization Header
                    ├─ 统一错误处理（401 跳转登录、403 提示无权限）
                    └─ 请求/响应日志

                 对话模式选择
                    │
                    ├─ 普通模式：POST /api/chat/send → JSON 响应
                    │   适用于简单查询，等待完整结果后一次渲染
                    │
                    └─ 流式模式：GET /api/chat/send/stream → SSE
                        适用于复杂分析，实时展示思考过程和逐步输出
                        使用 EventSource API 或 fetch + ReadableStream
```

### 9.5 状态管理（Pinia）

```
stores/
├── user.js        # 用户登录状态、角色信息、Token 管理
├── chat.js        # 会话列表、当前会话、消息历史
└── alert.js       # 预警通知状态、未读数量
```

---

## 10. 缓存策略设计

### 10.1 Redis 缓存分层

| 缓存层 | Key 模式 | 过期策略 | 说明 |
|--------|---------|---------|------|
| 会话缓存 | `sa:token:{token}` | 7 天 | Sa-Token 会话信息 |
| 用户信息缓存 | `user:info:{userId}` | 30 分钟 | 用户基本信息 + 角色 |
| 对话记忆 | `chat:memory:{sessionId}` | 24 小时 | LangChain4J ChatMemory |
| 热点数据缓存 | `sales:stats:{hash}` | 5 分钟 | 高频统计查询结果 |
| 限流计数器 | `rate:limit:{userId}:{api}` | 1 分钟 | 接口限流 |
| 元数据缓存 | `meta:products` | 1 小时 | 产品列表等变化不频繁的数据 |
| 预警缓存 | `alert:unread:{userId}` | 实时 | 未读预警数量 |

### 10.2 缓存更新策略

- **统计结果缓存**：采用 TTL 自动过期策略，不做主动失效（5 分钟内数据可接受延迟）
- **用户信息缓存**：修改用户角色或大区时主动清除缓存
- **对话记忆缓存**：每次对话自动更新，会话归档时清除
- **元数据缓存**：产品/客户变更时通过事件通知清除

---

## 11. 异常预警设计

### 11.1 架构

```
┌──────────────────────────────────┐
│         定时调度器                │
│   @Scheduled(cron = "0 0 * * *") │  ← 每小时执行
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│         预警引擎                  │
│  1. 加载所有启用的 alert_rule    │
│  2. 针对每条规则查询实时指标     │
│  3. 比对阈值，判断是否触发       │
│  4. 触发则写入 alert_record      │
│  5. 推送通知（WebSocket/站内信） │
└──────────────────────────────────┘
```

### 11.2 预警规则示例

| 规则名称 | 类型 | 指标 | 条件 | 时间窗口 |
|----------|------|------|------|---------|
| 日销售额骤降预警 | AMOUNT_DROP | 日销售额 | 环比下降 > 30% | 1天 |
| 零销售预警 | ZERO_SALES | 订单数 | = 0 | 1天 |
| 大客户流失预警 | AMOUNT_DROP | 客户月销售额 | 环比下降 > 50% | 1月 |
| 销售额异常飙升 | AMOUNT_SPIKE | 日销售额 | 超过近30天均值3倍 | 1天 |

### 11.3 通知渠道

- **站内通知**：通过 WebSocket 推送至前端预警中心
- **可扩展**：预留邮件、企业微信等通知接口（后续按需接入）

---

## 12. 部署方案

### 12.1 部署架构图

```
┌───────────────────────────────────────────────────────────┐
│                    Nginx (反向代理)                         │
│                   端口: 80 / 443                           │
│                                                           │
│   /           → 前端静态资源 (Vue 3 Build 产物)            │
│   /api/       → 后端 Spring Boot 应用                      │
│   /ws/        → WebSocket 连接（预警推送）                  │
└────────────────────────┬──────────────────────────────────┘
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
  ┌──────────────┐ ┌──────────┐ ┌──────────────┐
  │ Spring Boot  │ │  MySQL   │ │    Redis     │
  │ (Docker)     │ │ (Docker) │ │  (Docker)    │
  │ 端口: 8080   │ │ 端口:3306│ │  端口: 6379  │
  └──────────────┘ └──────────┘ └──────────────┘
```

### 12.2 Docker Compose 编排

```yaml
# docker-compose.yml 结构设计
services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./frontend/dist:/usr/share/nginx/html
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - backend

  backend:
    build: ./backend
    ports:
      - "8080:8080"
    environment:
      - SPRING_PROFILES_ACTIVE=prod
      - DB_HOST=mysql
      - DB_PORT=3306
      - REDIS_HOST=redis
      - LLM_API_KEY=${LLM_API_KEY}
      - LLM_BASE_URL=${LLM_BASE_URL}
      - LLM_MODEL_NAME=${LLM_MODEL_NAME}
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_started

  mysql:
    image: mysql:8.0
    ports:
      - "3306:3306"
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
      - MYSQL_DATABASE=sales_agent
    volumes:
      - mysql_data:/var/lib/mysql
      - ./sql/init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

volumes:
  mysql_data:
  redis_data:
```

### 12.3 环境配置

| 环境 | 用途 | 特殊配置 |
|------|------|---------|
| dev | 本地开发 | H2 内存数据库可选、LLM Mock 模式 |
| test | 测试环境 | 独立 MySQL 实例、测试用 LLM API Key |
| prod | 生产环境 | 高可用 MySQL、Redis Sentinel、正式 LLM API Key |

### 12.4 配置文件分离

```
application.yaml          → 公共配置
application-dev.yaml      → 开发环境（本地数据库连接、调试日志）
application-test.yaml     → 测试环境
application-prod.yaml     → 生产环境（敏感配置通过环境变量注入）
```

敏感配置项（**必须通过环境变量注入，不得写入配置文件**）：
- `DB_PASSWORD` - 数据库密码
- `LLM_API_KEY` - LLM API 密钥
- `SA_TOKEN_SECRET` - Token 加密密钥
- `REDIS_PASSWORD` - Redis 密码（如有）

---

## 13. 后端包结构规划

```
com.zhuku.backend
├── SalesAgentApplication.java              # 启动类
│
├── config/                                 # 配置类
│   ├── SaTokenConfig.java                  #   Sa-Token 配置
│   ├── RedisConfig.java                    #   Redis 配置
│   ├── MyBatisPlusConfig.java              #   MyBatis-Plus 配置（含数据权限插件）
│   ├── WebMvcConfig.java                   #   跨域、拦截器配置
│   ├── LangChain4jConfig.java              #   LangChain4J 额外配置（ChatMemoryProvider等）
│   └── WebSocketConfig.java                #   WebSocket 配置（预警推送）
│
├── common/                                 # 公共模块
│   ├── result/
│   │   ├── R.java                          #     统一响应体
│   │   └── ResultCode.java                 #     响应码枚举
│   ├── exception/
│   │   ├── BusinessException.java          #     业务异常
│   │   └── GlobalExceptionHandler.java     #     全局异常处理器
│   ├── context/
│   │   ├── UserContext.java                #     用户上下文（userId, role, regionId）
│   │   └── UserContextHolder.java          #     ThreadLocal 持有者
│   └── enums/
│       ├── RoleEnum.java                   #     角色枚举
│       ├── OrderStatusEnum.java            #     订单状态枚举
│       └── AlertLevelEnum.java             #     预警级别枚举
│
├── controller/                             # 控制器层
│   ├── AuthController.java                 #   认证接口
│   ├── ChatController.java                 #   AI 对话接口
│   ├── AlertController.java                #   预警接口
│   └── SystemController.java               #   系统管理接口
│
├── service/                                # 业务逻辑层
│   ├── AuthService.java
│   ├── ChatService.java                    #   对话编排（调用 AI Agent）
│   ├── OrderService.java                   #   订单查询服务
│   ├── StatsService.java                   #   统计分析服务
│   ├── TrendService.java                   #   趋势分析服务
│   ├── AlertService.java                   #   预警服务
│   └── UserService.java
│
├── agent/                                  # AI Agent 层
│   ├── SalesAssistant.java                 #   AI Service 接口定义
│   ├── tool/                               #   Tool 工具集
│   │   ├── OrderQueryTool.java             #     订单查询工具
│   │   ├── SalesStatsTool.java             #     统计汇总工具
│   │   ├── TrendAnalysisTool.java          #     趋势分析工具
│   │   ├── AnomalyDetectionTool.java       #     异常检测工具
│   │   ├── ChartDataTool.java              #     图表生成工具
│   │   └── DateTool.java                   #     日期工具
│   ├── prompt/                             #   提示词管理
│   │   └── PromptBuilder.java              #     动态 Prompt 构建器
│   ├── sanitizer/
│   │   ├── MessageSanitizer.java           #     输入安全过滤
│   │   └── ResponseAuditor.java            #     输出审核
│   └── memory/
│       └── RedisChatMemoryStore.java       #     Redis 对话记忆存储
│
├── repository/                             # 数据访问层
│   ├── mapper/
│   │   ├── UserMapper.java
│   │   ├── OrderMapper.java
│   │   ├── OrderItemMapper.java
│   │   ├── ProductMapper.java
│   │   ├── CustomerMapper.java
│   │   ├── RegionMapper.java
│   │   ├── ChatSessionMapper.java
│   │   ├── ChatMessageMapper.java
│   │   ├── AlertRuleMapper.java
│   │   └── AlertRecordMapper.java
│   └── interceptor/
│       └── DataPermissionInterceptor.java  #     数据权限拦截器
│
├── entity/                                 # 数据库实体
│   ├── SysUser.java
│   ├── SysRole.java
│   ├── SysUserRole.java
│   ├── SysRegion.java
│   ├── Customer.java
│   ├── Product.java
│   ├── ProductCategory.java
│   ├── SalesOrder.java
│   ├── SalesOrderItem.java
│   ├── ChatSession.java
│   ├── ChatMessage.java
│   ├── AlertRule.java
│   └── AlertRecord.java
│
├── dto/                                    # 请求/响应对象
│   ├── request/
│   │   ├── LoginRequest.java
│   │   ├── ChatRequest.java
│   │   └── AlertRuleRequest.java
│   └── response/
│       ├── LoginResponse.java
│       ├── ChatResponse.java
│       ├── ChartConfigVO.java
│       └── AlertVO.java
│
└── vo/                                     # Tool 返回值对象
    ├── OrderVO.java
    ├── SalesStatsVO.java
    ├── RankingVO.java
    ├── TimeSeriesVO.java
    ├── ComparisonVO.java
    └── AnomalyVO.java
```

---

## 14. 前端目录结构规划

```
frontend/
├── public/
│   └── favicon.ico
├── src/
│   ├── main.js                         # 入口文件
│   ├── App.vue                         # 根组件
│   │
│   ├── api/                            # 接口层
│   │   ├── request.js                  #   Axios 实例（拦截器、统一错误处理）
│   │   ├── auth.js                     #   认证相关接口
│   │   ├── chat.js                     #   对话相关接口
│   │   ├── alert.js                    #   预警相关接口
│   │   └── system.js                   #   系统管理接口
│   │
│   ├── router/                         # 路由配置
│   │   └── index.js                    #   路由定义 + 导航守卫
│   │
│   ├── stores/                         # Pinia 状态管理
│   │   ├── user.js                     #   用户状态
│   │   ├── chat.js                     #   对话状态
│   │   └── alert.js                    #   预警状态
│   │
│   ├── views/                          # 页面组件
│   │   ├── login/
│   │   │   └── LoginView.vue
│   │   ├── chat/
│   │   │   └── ChatView.vue            #   AI 对话主页
│   │   ├── alert/
│   │   │   └── AlertView.vue           #   预警中心
│   │   └── system/
│   │       ├── UserManage.vue
│   │       └── RegionManage.vue
│   │
│   ├── components/                     # 可复用组件
│   │   ├── chat/
│   │   │   ├── MessageList.vue         #   消息列表
│   │   │   ├── MessageBubble.vue       #   单条消息气泡
│   │   │   ├── ChartRenderer.vue       #   ECharts 图表渲染器
│   │   │   ├── ThinkingProcess.vue     #   AI 思考过程展示
│   │   │   ├── ChatInput.vue           #   消息输入框
│   │   │   └── SessionList.vue         #   会话列表侧栏
│   │   ├── alert/
│   │   │   └── AlertCard.vue           #   预警卡片
│   │   └── common/
│   │       ├── AppHeader.vue           #   顶部导航
│   │       └── LoadingIndicator.vue    #   加载状态
│   │
│   ├── composables/                    # 组合式函数
│   │   ├── useSSE.js                   #   SSE 连接管理
│   │   ├── useChart.js                 #   ECharts 初始化与更新
│   │   └── usePermission.js            #   权限判断
│   │
│   ├── utils/                          # 工具函数
│   │   ├── format.js                   #   格式化（日期、金额）
│   │   └── storage.js                  #   LocalStorage 封装
│   │
│   └── styles/                         # 全局样式
│       └── global.css
│
├── index.html
├── vite.config.js
└── package.json
```

---

## 15. 非功能性需求

### 15.1 性能指标

| 指标 | 目标值 |
|------|-------|
| 普通对话响应时间（非流式） | < 5 秒 |
| 流式首字响应时间 | < 1 秒 |
| 页面首屏加载 | < 2 秒 |
| 数据查询（普通条件） | < 500ms |
| 统计聚合查询 | < 2 秒 |
| 并发用户支持 | ≥ 50 |

### 15.2 可用性

- 系统整体可用性目标 ≥ 99.5%
- LLM 服务不可用时降级：提示用户稍后重试，不影响其他系统功能
- 数据库连接池异常时返回友好错误提示

### 15.3 可观测性

| 维度 | 方案 |
|------|------|
| 日志 | SLF4J + Logback，按级别分文件，JSON 格式便于采集 |
| Tool 调用追踪 | 记录每次 Tool 调用的名称、参数、耗时、结果摘要 |
| Token 消耗统计 | 记录每次 LLM 调用的 Token 使用量，支持按用户/会话统计 |
| 接口监控 | Spring Boot Actuator 暴露健康检查和指标端点 |

### 15.4 可扩展性

- **新增 Tool**：只需创建新的 `@Component` 类并添加 `@Tool` 方法，Spring Boot 自动发现注册
- **切换 LLM**：修改配置文件中的 `base-url` 和 `model-name` 即可，无需改代码
- **新增预警规则类型**：扩展 `rule_type` 枚举和对应检测逻辑
- **新增通知渠道**：实现 `NotificationChannel` 接口即可

---

## 附录 A：Maven 依赖清单（后端）

```xml
<!-- Spring Boot 核心 -->
spring-boot-starter-web
spring-boot-starter-validation
spring-boot-starter-websocket
spring-boot-starter-actuator

<!-- LangChain4J -->
langchain4j-spring-boot-starter            (1.12.1)
langchain4j-open-ai-spring-boot-starter    (1.12.1)

<!-- 数据层 -->
mysql-connector-j
mybatis-plus-spring-boot3-starter          (3.5.x)

<!-- Redis -->
spring-boot-starter-data-redis

<!-- 认证授权 -->
sa-token-spring-boot3-starter              (1.39.x)
sa-token-redis-jackson                     (与 Sa-Token 同版本)

<!-- 工具类 -->
hutool-all                                 (5.8.x)
mapstruct                                  (1.5.x)
lombok

<!-- API 文档 -->
knife4j-openapi3-jakarta-spring-boot-starter (4.x)

<!-- 测试 -->
spring-boot-starter-test
```

## 附录 B：NPM 依赖清单（前端）

```json
{
  "dependencies": {
    "vue": "^3.5.x",
    "vue-router": "^5.x",
    "pinia": "^3.x",
    "axios": "^1.x",
    "echarts": "^5.x",
    "element-plus": "^2.x",
    "marked": "^x.x"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^6.x",
    "vite": "^8.x",
    "unplugin-auto-import": "^x.x",
    "unplugin-vue-components": "^x.x"
  }
}
```

## 附录 C：关键技术决策记录

| 决策项 | 选择 | 理由 |
|--------|------|------|
| ORM 框架 | MyBatis-Plus | 支持数据权限拦截器插件，灵活的 SQL 控制能力 |
| 认证框架 | Sa-Token | 轻量级，Spring Boot 3 原生支持，API 简洁 |
| AI 框架 | LangChain4J | Java 原生 AI 框架，Spring Boot 深度集成，Tool Calling 成熟 |
| 前端 UI 库 | Element Plus | Vue 3 生态主流，组件丰富，文档完善 |
| 图表库 | ECharts | 国产友好，图表类型丰富，支持后端生成配置 |
| 缓存 | Redis | 多用途（会话/缓存/限流/对话记忆），成熟稳定 |
| 流式响应 | SSE | 比 WebSocket 更简单，适合单向推送场景，HTTP 兼容性好 |
| 预警推送 | WebSocket | 需要服务端主动推送，SSE 无法满足双向通信需求 |
