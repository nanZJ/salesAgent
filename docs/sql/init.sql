-- ============================================================
-- 销售数据分析 AI Agent - 数据库初始化脚本
-- 数据库: sales_agent
-- 字符集: utf8mb4
-- ============================================================

CREATE DATABASE IF NOT EXISTS sales_agent
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_general_ci;

USE sales_agent;

-- ============================================================
-- 1. 系统管理表
-- ============================================================

-- 角色表
CREATE TABLE sys_role (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    role_code   VARCHAR(50)  NOT NULL COMMENT '角色编码',
    role_name   VARCHAR(50)  NOT NULL COMMENT '角色名称',
    description VARCHAR(255)          COMMENT '角色描述',
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_role_code (role_code)
) ENGINE=InnoDB COMMENT='角色表';

-- 销售大区表
CREATE TABLE sys_region (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    region_name VARCHAR(50)  NOT NULL COMMENT '大区名称',
    region_code VARCHAR(20)  NOT NULL COMMENT '大区编码',
    manager_id  BIGINT                COMMENT '大区主管用户ID',
    status      TINYINT      NOT NULL DEFAULT 1 COMMENT '状态: 0-禁用 1-启用',
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_region_name (region_name),
    UNIQUE KEY uk_region_code (region_code)
) ENGINE=InnoDB COMMENT='销售大区表';

-- 系统用户表
CREATE TABLE sys_user (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    username    VARCHAR(50)  NOT NULL COMMENT '登录用户名',
    password    VARCHAR(255) NOT NULL COMMENT '加密密码(BCrypt)',
    real_name   VARCHAR(50)  NOT NULL COMMENT '真实姓名',
    phone       VARCHAR(20)           COMMENT '手机号',
    email       VARCHAR(100)          COMMENT '邮箱',
    region_id   BIGINT                COMMENT '所属大区ID',
    status      TINYINT      NOT NULL DEFAULT 1 COMMENT '状态: 0-禁用 1-启用',
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_username (username),
    INDEX idx_user_region (region_id),
    CONSTRAINT fk_user_region FOREIGN KEY (region_id) REFERENCES sys_region(id)
) ENGINE=InnoDB COMMENT='系统用户表';

-- 补充 sys_region 的外键 (manager_id -> sys_user.id)
ALTER TABLE sys_region
    ADD CONSTRAINT fk_region_manager FOREIGN KEY (manager_id) REFERENCES sys_user(id);

-- 用户角色关联表
CREATE TABLE sys_user_role (
    id       BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id  BIGINT NOT NULL COMMENT '用户ID',
    role_id  BIGINT NOT NULL COMMENT '角色ID',
    UNIQUE KEY uk_user_role (user_id, role_id),
    CONSTRAINT fk_ur_user FOREIGN KEY (user_id) REFERENCES sys_user(id),
    CONSTRAINT fk_ur_role FOREIGN KEY (role_id) REFERENCES sys_role(id)
) ENGINE=InnoDB COMMENT='用户角色关联表';

-- ============================================================
-- 2. 业务核心表
-- ============================================================

-- 客户表
CREATE TABLE customer (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    customer_name   VARCHAR(100) NOT NULL COMMENT '客户名称',
    customer_code   VARCHAR(50)  NOT NULL COMMENT '客户编码',
    contact_person  VARCHAR(50)           COMMENT '联系人',
    contact_phone   VARCHAR(20)           COMMENT '联系电话',
    address         VARCHAR(255)          COMMENT '地址',
    region_id       BIGINT                COMMENT '所属大区',
    status          TINYINT      NOT NULL DEFAULT 1 COMMENT '状态: 0-禁用 1-启用',
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_customer_code (customer_code),
    INDEX idx_customer_region (region_id),
    CONSTRAINT fk_customer_region FOREIGN KEY (region_id) REFERENCES sys_region(id)
) ENGINE=InnoDB COMMENT='客户表';

-- 产品类别表
CREATE TABLE product_category (
    id            BIGINT AUTO_INCREMENT PRIMARY KEY,
    category_name VARCHAR(50) NOT NULL COMMENT '类别名称',
    category_code VARCHAR(20) NOT NULL COMMENT '类别编码',
    parent_id     BIGINT               COMMENT '父类别ID',
    sort_order    INT         NOT NULL DEFAULT 0 COMMENT '排序号',
    created_at    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_category_code (category_code),
    CONSTRAINT fk_category_parent FOREIGN KEY (parent_id) REFERENCES product_category(id)
) ENGINE=InnoDB COMMENT='产品类别表';

-- 产品表
CREATE TABLE product (
    id           BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_name VARCHAR(100)   NOT NULL COMMENT '产品名称',
    product_code VARCHAR(50)    NOT NULL COMMENT '产品编码',
    category_id  BIGINT                  COMMENT '所属类别',
    unit         VARCHAR(20)             COMMENT '计量单位',
    price        DECIMAL(12,2)  NOT NULL COMMENT '标准单价',
    status       TINYINT        NOT NULL DEFAULT 1 COMMENT '状态: 0-下架 1-上架',
    created_at   DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_product_code (product_code),
    INDEX idx_product_category (category_id),
    CONSTRAINT fk_product_category FOREIGN KEY (category_id) REFERENCES product_category(id)
) ENGINE=InnoDB COMMENT='产品表';

-- 销售订单主表
CREATE TABLE sales_order (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_no        VARCHAR(32)    NOT NULL COMMENT '订单编号',
    customer_id     BIGINT         NOT NULL COMMENT '客户ID',
    salesperson_id  BIGINT         NOT NULL COMMENT '销售员ID',
    region_id       BIGINT         NOT NULL COMMENT '所属大区',
    order_date      DATE           NOT NULL COMMENT '下单日期',
    total_amount    DECIMAL(14,2)  NOT NULL COMMENT '订单总金额',
    status          VARCHAR(20)    NOT NULL COMMENT '订单状态: PENDING/CONFIRMED/SHIPPED/COMPLETED/CANCELLED',
    remark          VARCHAR(500)            COMMENT '备注',
    created_at      DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_order_no (order_no),
    INDEX idx_order_date (order_date),
    INDEX idx_order_salesperson (salesperson_id, order_date),
    INDEX idx_order_region (region_id, order_date),
    INDEX idx_order_customer (customer_id, order_date),
    INDEX idx_order_status (status, order_date),
    CONSTRAINT fk_order_customer FOREIGN KEY (customer_id) REFERENCES customer(id),
    CONSTRAINT fk_order_salesperson FOREIGN KEY (salesperson_id) REFERENCES sys_user(id),
    CONSTRAINT fk_order_region FOREIGN KEY (region_id) REFERENCES sys_region(id)
) ENGINE=InnoDB COMMENT='销售订单主表';

-- 销售订单明细表
CREATE TABLE sales_order_item (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id    BIGINT         NOT NULL COMMENT '订单ID',
    product_id  BIGINT         NOT NULL COMMENT '产品ID',
    quantity    INT            NOT NULL COMMENT '数量',
    unit_price  DECIMAL(12,2)  NOT NULL COMMENT '成交单价',
    subtotal    DECIMAL(14,2)  NOT NULL COMMENT '小计金额',
    INDEX idx_item_order (order_id),
    INDEX idx_item_product (product_id),
    CONSTRAINT fk_item_order FOREIGN KEY (order_id) REFERENCES sales_order(id),
    CONSTRAINT fk_item_product FOREIGN KEY (product_id) REFERENCES product(id)
) ENGINE=InnoDB COMMENT='销售订单明细表';

-- ============================================================
-- 3. AI 对话表
-- ============================================================

-- 对话会话表
CREATE TABLE chat_session (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    session_id  VARCHAR(36)  NOT NULL COMMENT '会话UUID',
    user_id     BIGINT       NOT NULL COMMENT '所属用户',
    title       VARCHAR(100)          COMMENT '会话标题',
    status      TINYINT      NOT NULL DEFAULT 1 COMMENT '状态: 0-已归档 1-活跃',
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_session_id (session_id),
    INDEX idx_session_user (user_id, updated_at DESC),
    CONSTRAINT fk_session_user FOREIGN KEY (user_id) REFERENCES sys_user(id)
) ENGINE=InnoDB COMMENT='对话会话表';

-- 对话消息表
CREATE TABLE chat_message (
    id           BIGINT AUTO_INCREMENT PRIMARY KEY,
    session_id   VARCHAR(36)  NOT NULL COMMENT '所属会话',
    role         VARCHAR(20)  NOT NULL COMMENT '消息角色: USER/ASSISTANT/TOOL',
    content      TEXT         NOT NULL COMMENT '消息内容',
    tool_name    VARCHAR(50)           COMMENT 'Tool调用名称',
    tool_input   TEXT                  COMMENT 'Tool调用输入参数(JSON)',
    chart_config TEXT                  COMMENT '图表配置(JSON)',
    tokens_used  INT                   COMMENT '本次消耗的Token数',
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_msg_session (session_id, created_at)
) ENGINE=InnoDB COMMENT='对话消息表';

-- ============================================================
-- 4. 预警表
-- ============================================================

-- 预警规则表
CREATE TABLE alert_rule (
    id           BIGINT AUTO_INCREMENT PRIMARY KEY,
    rule_name    VARCHAR(100)   NOT NULL COMMENT '规则名称',
    rule_type    VARCHAR(30)    NOT NULL COMMENT '规则类型: AMOUNT_DROP/AMOUNT_SPIKE/ORDER_DROP/ZERO_SALES/CUSTOM',
    metric       VARCHAR(50)    NOT NULL COMMENT '监控指标',
    operator     VARCHAR(10)    NOT NULL COMMENT '比较运算符: >/</>=/<=/=',
    threshold    DECIMAL(14,2)  NOT NULL COMMENT '阈值',
    time_window  VARCHAR(20)    NOT NULL COMMENT '时间窗口: 1d/7d/1m等',
    dimension    VARCHAR(50)             COMMENT '监控维度',
    notify_roles VARCHAR(255)            COMMENT '通知角色(逗号分隔)',
    status       TINYINT        NOT NULL DEFAULT 1 COMMENT '状态: 0-禁用 1-启用',
    created_at   DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB COMMENT='预警规则表';

-- 预警记录表
CREATE TABLE alert_record (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    rule_id         BIGINT         NOT NULL COMMENT '触发的规则ID',
    alert_level     VARCHAR(10)    NOT NULL COMMENT '预警级别: INFO/WARN/CRITICAL',
    title           VARCHAR(200)   NOT NULL COMMENT '预警标题',
    content         TEXT           NOT NULL COMMENT '预警详情',
    metric_value    DECIMAL(14,2)           COMMENT '触发时的指标值',
    threshold_value DECIMAL(14,2)           COMMENT '阈值',
    status          TINYINT        NOT NULL DEFAULT 0 COMMENT '处理状态: 0-未处理 1-已处理 2-已忽略',
    handled_by      BIGINT                  COMMENT '处理人ID',
    handled_at      DATETIME                COMMENT '处理时间',
    created_at      DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_alert_status (status, created_at DESC),
    INDEX idx_alert_rule (rule_id, created_at DESC),
    CONSTRAINT fk_alert_rule FOREIGN KEY (rule_id) REFERENCES alert_rule(id),
    CONSTRAINT fk_alert_handler FOREIGN KEY (handled_by) REFERENCES sys_user(id)
) ENGINE=InnoDB COMMENT='预警记录表';

-- ============================================================
-- 5. 初始数据
-- ============================================================

-- 初始化角色
INSERT INTO sys_role (role_code, role_name, description) VALUES
('SALESPERSON', '销售员', '普通销售人员，仅可访问个人销售数据'),
('MANAGER', '销售主管', '大区销售主管，可访问所属大区销售数据'),
('DIRECTOR', '销售总监', '销售总监，可访问全局销售数据');

-- 初始化大区 (manager_id 暂为NULL，待创建主管用户后更新)
INSERT INTO sys_region (region_name, region_code) VALUES
('华东大区', 'EAST'),
('华南大区', 'SOUTH'),
('华北大区', 'NORTH'),
('华西大区', 'WEST'),
('华中大区', 'CENTRAL');

-- 初始化产品类别
INSERT INTO product_category (category_name, category_code, sort_order) VALUES
('电子产品', 'ELECTRONICS', 1),
('办公用品', 'OFFICE', 2),
('原材料', 'MATERIALS', 3),
('生活用品', 'DAILY', 4);

-- 初始化默认预警规则
INSERT INTO alert_rule (rule_name, rule_type, metric, operator, threshold, time_window, notify_roles) VALUES
('日销售额骤降预警', 'AMOUNT_DROP', 'daily_sales_amount', '>', 30.00, '1d', 'MANAGER,DIRECTOR'),
('零销售预警', 'ZERO_SALES', 'daily_order_count', '=', 0.00, '1d', 'MANAGER,DIRECTOR'),
('销售额异常飙升', 'AMOUNT_SPIKE', 'daily_sales_amount', '>', 300.00, '1d', 'DIRECTOR');
