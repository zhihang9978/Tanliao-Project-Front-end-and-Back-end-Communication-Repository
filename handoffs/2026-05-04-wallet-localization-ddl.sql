-- 钱包本地化改造 — 完整 DDL 脚本
-- 更新时间：2026-05-04 17:45 +08:00
-- 对应 PRD: 2026-05-04-wallet-localization-prd.md
-- 适用环境: 开发库 / 生产库(开发期无用户数据)
-- 执行前: mysqldump tio_site_main > backup_before_wallet_v2_$(date +%Y%m%d).sql

USE tio_site_main;

SET FOREIGN_KEY_CHECKS = 0;
SET NAMES utf8mb4;

-- ============================================================
-- Step 1: TRUNCATE 12 张钱包相关表(开发期清空数据)
-- 生产部署前确认数据量为 0,执行此步骤
-- ============================================================
TRUNCATE TABLE wx_wallet;
TRUNCATE TABLE wx_wallet_info;
TRUNCATE TABLE wx_wallet_coin;
TRUNCATE TABLE wx_wallet_coin_item;
TRUNCATE TABLE wx_user_recharge_item;
TRUNCATE TABLE wx_wallet_recharge_item;
TRUNCATE TABLE wx_user_withhold_item;
TRUNCATE TABLE wx_wallet_withhold_items;
TRUNCATE TABLE wx_wallet_back_red_packet_items;
TRUNCATE TABLE wx_wallet_send_red_packet;
TRUNCATE TABLE wx_wallet_grab_red_item;
TRUNCATE TABLE wx_wallet_red_packet_random;

-- ============================================================
-- Step 2: ALTER 现有表(加字段 + CHECK 约束)
-- ============================================================

-- 2.1 wx_wallet_coin 加冻结字段 + CHECK 约束(并发安全第 3 层防御)
ALTER TABLE wx_wallet_coin
  ADD COLUMN frozen_cny BIGINT DEFAULT 0 COMMENT '冻结金额(分,审核中提现等占用)' AFTER cny;

-- MySQL 8 CHECK 约束(MariaDB 10.3 也支持)
ALTER TABLE wx_wallet_coin
  ADD CONSTRAINT chk_cny_nonneg CHECK (cny >= 0),
  ADD CONSTRAINT chk_frozen_nonneg CHECK (frozen_cny >= 0),
  ADD CONSTRAINT chk_frozen_lte_cny CHECK (frozen_cny <= cny);

-- 2.2 wx_user_recharge_item 加审核流字段
ALTER TABLE wx_user_recharge_item
  ADD COLUMN method_id INT NULL COMMENT '充值方式 wx_pay_method.id',
  ADD COLUMN marker_amount DECIMAL(12,2) NULL COMMENT '实际应付(带 0.01-0.99 尾数)',
  ADD COLUMN serial_no VARCHAR(32) NULL COMMENT 'R 前缀订单号',
  ADD COLUMN audit_status TINYINT DEFAULT 1 COMMENT '1待审 2处理中 3通过 4拒绝 5取消 6超时',
  ADD COLUMN audit_uid INT NULL COMMENT '审核管理员 mg_admin.id',
  ADD COLUMN audit_remark VARCHAR(500) NULL,
  ADD COLUMN audit_lock_time DATETIME NULL COMMENT '锁定时间(audit_status=2 时)',
  ADD COLUMN audit_time DATETIME NULL,
  ADD COLUMN expire_time DATETIME NULL COMMENT '订单超时时间(默认 createtime + 60 分钟)';

ALTER TABLE wx_user_recharge_item
  ADD UNIQUE KEY uk_serial_no (serial_no);

CREATE INDEX idx_recharge_audit_status ON wx_user_recharge_item(audit_status, createtime);
CREATE INDEX idx_recharge_marker_segment ON wx_user_recharge_item(method_id, marker_amount, audit_status);

-- 2.3 wx_user_withhold_item 加审核流字段
ALTER TABLE wx_user_withhold_item
  ADD COLUMN method_id INT NULL COMMENT '提现方式 wx_pay_method.id',
  ADD COLUMN account_id INT NULL COMMENT '绑定账号 wx_user_payout_account.id',
  ADD COLUMN account_snapshot TEXT NULL COMMENT '下单时账号快照(防用户修改)',
  ADD COLUMN serial_no VARCHAR(32) NULL COMMENT 'W 前缀订单号',
  ADD COLUMN audit_status TINYINT DEFAULT 1 COMMENT '1待审 2处理中 3通过 4拒绝 5取消',
  ADD COLUMN audit_uid INT NULL,
  ADD COLUMN audit_remark VARCHAR(500) NULL,
  ADD COLUMN audit_lock_time DATETIME NULL,
  ADD COLUMN audit_time DATETIME NULL,
  ADD COLUMN payout_evidence VARCHAR(255) NULL COMMENT '可选打款凭证图 URL';

ALTER TABLE wx_user_withhold_item
  ADD UNIQUE KEY uk_serial_no (serial_no);

CREATE INDEX idx_withhold_audit_status ON wx_user_withhold_item(audit_status, createtime);
CREATE INDEX idx_withhold_uid_status ON wx_user_withhold_item(uid, audit_status);

-- 2.4 mg_op_log 加钱包操作字段
ALTER TABLE mg_op_log
  ADD COLUMN target_uid INT NULL COMMENT '操作目标用户 uid',
  ADD COLUMN amount BIGINT NULL COMMENT '涉及金额(分)',
  ADD COLUMN extra_json TEXT NULL COMMENT '额外结构化日志(订单号 / 原余额 / 新余额等)';

CREATE INDEX idx_op_log_target_uid ON mg_op_log(target_uid, createtime);

-- 2.5 wx_user 加支付密码锁字段
ALTER TABLE wx_user
  ADD COLUMN paypwd_lock_until DATETIME NULL COMMENT '支付密码锁定到何时(连错 5 次锁 30 分钟)';

-- ============================================================
-- Step 3: 新建 5 张表
-- ============================================================

-- 3.1 支付方式配置(充值/提现统一)
DROP TABLE IF EXISTS wx_pay_method;
CREATE TABLE wx_pay_method (
  id INT NOT NULL AUTO_INCREMENT,
  type TINYINT NOT NULL COMMENT '1充值 2提现',
  method_type VARCHAR(20) NOT NULL COMMENT 'alipay/wechat/bank/usdt/custom',
  name VARCHAR(50) NOT NULL COMMENT '展示名,如"支付宝-财务A"',
  account VARCHAR(255) NULL COMMENT '账号/地址(USDT 时存链地址)',
  payee_name VARCHAR(50) NULL COMMENT '户名(银行卡用)',
  qrcode_url VARCHAR(255) NULL COMMENT '收款码图(最大 5MB)',
  bank_name VARCHAR(100) NULL COMMENT '银行名(method_type=bank 用)',
  bank_branch VARCHAR(100) NULL COMMENT '开户行支行',
  chain_type VARCHAR(20) NULL COMMENT 'TRC20/ERC20/BEP20/Polygon(method_type=usdt 时必填)',
  cny_per_unit DECIMAL(10,4) NULL COMMENT 'USDT 折人民币率(1 USDT = X 元)',
  min_amount BIGINT NULL COMMENT '最小金额(分),NULL 不限',
  max_amount BIGINT NULL COMMENT '最大金额(分)',
  fee_rate DECIMAL(5,4) DEFAULT 0 COMMENT '手续费率(0.005=0.5%)',
  fee_fixed BIGINT DEFAULT 0 COMMENT '固定手续费(分)',
  daily_limit BIGINT NULL COMMENT '单日总额上限(分)',
  status TINYINT DEFAULT 1 COMMENT '1启用 2停用',
  sort INT DEFAULT 0,
  remark VARCHAR(500) NULL COMMENT '后台备注',
  createtime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updatetime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_type_status (type, status, sort)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='支付方式配置(充值/提现)';

-- 3.2 用户提现账号绑定
DROP TABLE IF EXISTS wx_user_payout_account;
CREATE TABLE wx_user_payout_account (
  id INT NOT NULL AUTO_INCREMENT,
  uid INT NOT NULL,
  method_type VARCHAR(20) NOT NULL COMMENT 'alipay/wechat/bank/usdt/custom',
  payee_name VARCHAR(50) NULL COMMENT '户名(银行卡必填)',
  account VARCHAR(255) NOT NULL COMMENT '账号/地址',
  chain_type VARCHAR(20) NULL COMMENT 'USDT 时存链类型',
  bank_name VARCHAR(100) NULL,
  bank_branch VARCHAR(100) NULL,
  extra TEXT NULL COMMENT 'JSON 扩展字段',
  qrcode_url VARCHAR(255) NULL COMMENT '可选用户上传收款码图',
  is_default TINYINT DEFAULT 0,
  verified TINYINT DEFAULT 0 COMMENT '0未验证 1已成功提现过(账号"老化")',
  usable_after DATETIME NOT NULL COMMENT '冷静期截止(默认 createtime + 24h)',
  status TINYINT DEFAULT 1 COMMENT '1正常 2已删除(软删)',
  createtime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updatetime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_uid_status (uid, status),
  UNIQUE KEY uk_uid_type_account (uid, method_type, account, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户提现账号绑定(本地化)';

-- 3.3 钱包密保问答(每用户 3 行)
DROP TABLE IF EXISTS wx_wallet_security_qa;
CREATE TABLE wx_wallet_security_qa (
  id INT NOT NULL AUTO_INCREMENT,
  uid INT NOT NULL,
  question_id INT NOT NULL COMMENT '指向 wx_security_question.id',
  answer_hash VARCHAR(64) NOT NULL COMMENT 'MD5(uid + 答案 trim+lowercase)',
  order_no TINYINT NOT NULL COMMENT '1/2/3 第几题',
  createtime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updatetime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_uid_order (uid, order_no),
  KEY idx_uid (uid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='钱包密保问答';

-- 3.4 密保问题预设池(后台可增减)
DROP TABLE IF EXISTS wx_security_question;
CREATE TABLE wx_security_question (
  id INT NOT NULL AUTO_INCREMENT,
  question VARCHAR(100) NOT NULL,
  status TINYINT DEFAULT 1 COMMENT '1启用 2停用',
  sort INT DEFAULT 0,
  createtime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updatetime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_status_sort (status, sort)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='密保问题预设池';

-- 3.5 无主资金池(未匹配订单)
DROP TABLE IF EXISTS wx_unmatched_payment;
CREATE TABLE wx_unmatched_payment (
  id INT NOT NULL AUTO_INCREMENT,
  serial_no VARCHAR(32) NULL COMMENT 'U 前缀编号',
  method_id INT NOT NULL COMMENT '哪个收款方式',
  amount BIGINT NOT NULL COMMENT '进账金额(分)',
  raw_remark VARCHAR(500) NULL COMMENT '管理员录入备注/对方账号信息',
  evidence_url VARCHAR(255) NULL COMMENT '银行/支付宝截图(可选)',
  status TINYINT DEFAULT 1 COMMENT '1待处理 2已退回 3已加余额 4已忽略',
  resolved_uid INT NULL COMMENT '加余额的用户 uid(若选 status=3)',
  resolved_amount BIGINT NULL COMMENT '实际加余额(可能扣手续费)',
  resolved_remark VARCHAR(500) NULL,
  resolved_admin INT NULL COMMENT '处理的管理员 mg_admin.id',
  resolved_time DATETIME NULL,
  createtime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_serial_no (serial_no),
  KEY idx_status_createtime (status, createtime)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='无主资金池(收到了但未匹配订单)';

-- ============================================================
-- Step 4: 初始化数据
-- ============================================================

-- 4.1 8 个预设密保问题
INSERT INTO wx_security_question (question, sort) VALUES
('您的小学校名是?', 10),
('您母亲的姓名是?', 20),
('您出生的城市是?', 30),
('您父亲的姓名是?', 40),
('您最难忘的老师姓名是?', 50),
('您最喜欢的食物是?', 60),
('您养过的第一只宠物名字是?', 70),
('您高中校名是?', 80);

-- 4.2 38 个权限点(写入 mg_auth)
-- 注意: 实际 pid 需根据现有 mg_auth 顶级菜单 id 调整
-- 假设现有顶级菜单 ID 都 < 1000,新增大类 id 从 2000 开始

-- 财务管理大类
INSERT INTO mg_auth (id, pid, name, type, deep, authurl, routekey, icon, status, sort) VALUES
(2000, 0,    '财务管理',    1, 1, '',                                       '/finance',                  'el-icon-coin',          1, 50),
(2001, 2000, '充值审核',    1, 2, '',                                       '/finance/recharge',         'el-icon-money',         1, 10),
(2002, 2001, '查看',       3, 3, '/tioadmin/recharge/pending',              '',                          '',                      1, 10),
(2003, 2001, '通过',       3, 3, '/tioadmin/recharge/approve',              '',                          '',                      1, 20),
(2004, 2001, '拒绝',       3, 3, '/tioadmin/recharge/reject',               '',                          '',                      1, 30),
(2005, 2001, '锁定/解锁',   3, 3, '/tioadmin/recharge/lock',                 '',                          '',                      1, 40),

(2010, 2000, '提现审核',    1, 2, '',                                       '/finance/withhold',         'el-icon-bank-card',     1, 20),
(2011, 2010, '查看',       3, 3, '/tioadmin/withhold/pending',              '',                          '',                      1, 10),
(2012, 2010, '通过',       3, 3, '/tioadmin/withhold/approve',              '',                          '',                      1, 20),
(2013, 2010, '拒绝',       3, 3, '/tioadmin/withhold/reject',               '',                          '',                      1, 30),
(2014, 2010, '锁定/解锁',   3, 3, '/tioadmin/withhold/lock',                 '',                          '',                      1, 40),

(2020, 2000, '无主资金',    1, 2, '',                                       '/finance/unmatched',        'el-icon-warning',       1, 30),
(2021, 2020, '查看',       3, 3, '/tioadmin/unmatched/list',                '',                          '',                      1, 10),
(2022, 2020, '录入',       3, 3, '/tioadmin/unmatched/record',              '',                          '',                      1, 20),
(2023, 2020, '匹配用户',    3, 3, '/tioadmin/unmatched/match-user',          '',                          '',                      1, 30),
(2024, 2020, '退回/忽略',   3, 3, '/tioadmin/unmatched/refund',              '',                          '',                      1, 40),

(2030, 2000, '用户钱包',    1, 2, '',                                       '/finance/wallet',           'el-icon-wallet',        1, 40),
(2031, 2030, '查看',       3, 3, '/tioadmin/wallet/list',                   '',                          '',                      1, 10),
(2032, 2030, '手动加余额',  3, 3, '/tioadmin/wallet/credit',                 '',                          '',                      1, 20),
(2033, 2030, '手动扣余额',  3, 3, '/tioadmin/wallet/debit',                  '',                          '',                      1, 30),
(2034, 2030, '冻结',       3, 3, '/tioadmin/wallet/freeze',                 '',                          '',                      1, 40),
(2035, 2030, '解冻',       3, 3, '/tioadmin/wallet/unfreeze',               '',                          '',                      1, 50),
(2036, 2030, '代重置支付密码', 3, 3, '/tioadmin/wallet/reset-paypwd',         '',                          '',                      1, 60);

-- 支付配置大类
INSERT INTO mg_auth (id, pid, name, type, deep, authurl, routekey, icon, status, sort) VALUES
(2100, 0,    '支付配置',    1, 1, '',                                       '/paycfg',                   'el-icon-setting',       1, 51),
(2101, 2100, '充值方式',    1, 2, '',                                       '/paycfg/recharge-method',   '',                      1, 10),
(2102, 2101, '增删改',     3, 3, '/tioadmin/paymethod/save',                '',                          '',                      1, 10),
(2103, 2101, '启用/停用',   3, 3, '/tioadmin/paymethod/toggle',              '',                          '',                      1, 20),

(2110, 2100, '提现方式',    1, 2, '',                                       '/paycfg/withhold-method',   '',                      1, 20),
(2111, 2110, '增删改',     3, 3, '/tioadmin/paymethod/save?type=2',         '',                          '',                      1, 10),
(2112, 2110, '启用/停用',   3, 3, '/tioadmin/paymethod/toggle?type=2',       '',                          '',                      1, 20),

(2120, 2100, '限额配置',    1, 2, '',                                       '/paycfg/limits',            '',                      1, 30),
(2121, 2120, '修改',       3, 3, '/tioadmin/limits/save',                   '',                          '',                      1, 10),

(2130, 2100, '密保问题池',  1, 2, '',                                       '/paycfg/security-question', '',                      1, 40),
(2131, 2130, '增删改',     3, 3, '/tioadmin/secquestion/save',              '',                          '',                      1, 10);

-- 审计大类(仅超管可见)
INSERT INTO mg_auth (id, pid, name, type, deep, authurl, routekey, icon, status, sort) VALUES
(2200, 0,    '审计',       1, 1, '',                                       '/audit',                    'el-icon-document',      1, 90),
(2201, 2200, '钱包操作日志', 1, 2, '',                                      '/audit/wallet-log',         '',                      1, 10),
(2202, 2201, '查看',       3, 3, '/tioadmin/auditlog/list',                 '',                          '',                      1, 10),
(2203, 2201, '导出 Excel', 3, 3, '/tioadmin/auditlog/export',               '',                          '',                      1, 20);

-- 4.3 4 个新角色(注意:1 = 现有超管,假设已存在;新增 10/11/12)
INSERT INTO mg_role (id, name, rindex, status) VALUES
(10, '财务管理员', 10, 1),
(11, '客服',     11, 1),
(12, '运营',     12, 1);

-- 4.4 角色绑权限(mg_role_auth)
-- 超管(id=1)— 全部权限,通常已经默认有,这里补上钱包相关
INSERT INTO mg_role_auth (rid, aid, status) VALUES
-- 超管: 全部 38 项
(1, 2000, 1), (1, 2001, 1), (1, 2002, 1), (1, 2003, 1), (1, 2004, 1), (1, 2005, 1),
(1, 2010, 1), (1, 2011, 1), (1, 2012, 1), (1, 2013, 1), (1, 2014, 1),
(1, 2020, 1), (1, 2021, 1), (1, 2022, 1), (1, 2023, 1), (1, 2024, 1),
(1, 2030, 1), (1, 2031, 1), (1, 2032, 1), (1, 2033, 1), (1, 2034, 1), (1, 2035, 1), (1, 2036, 1),
(1, 2100, 1), (1, 2101, 1), (1, 2102, 1), (1, 2103, 1),
(1, 2110, 1), (1, 2111, 1), (1, 2112, 1),
(1, 2120, 1), (1, 2121, 1),
(1, 2130, 1), (1, 2131, 1),
(1, 2200, 1), (1, 2201, 1), (1, 2202, 1), (1, 2203, 1),

-- 财务管理员(id=10): 财务管理大类全部(含加扣/冻结)+ 无主资金 + 用户钱包,但不含支付配置 + 审计
(10, 2000, 1), (10, 2001, 1), (10, 2002, 1), (10, 2003, 1), (10, 2004, 1), (10, 2005, 1),
(10, 2010, 1), (10, 2011, 1), (10, 2012, 1), (10, 2013, 1), (10, 2014, 1),
(10, 2020, 1), (10, 2021, 1), (10, 2022, 1), (10, 2023, 1), (10, 2024, 1),
(10, 2030, 1), (10, 2031, 1), (10, 2032, 1), (10, 2033, 1), (10, 2034, 1), (10, 2035, 1),

-- 客服(id=11): 无主资金查 + 用户钱包查(只读)+ 代重置支付密码
(11, 2000, 1),
(11, 2020, 1), (11, 2021, 1), (11, 2023, 1),
(11, 2030, 1), (11, 2031, 1), (11, 2036, 1),

-- 运营(id=12): 仅用户钱包查(只读)
(12, 2000, 1),
(12, 2030, 1), (12, 2031, 1);

-- 4.5 5 个 conf 配置项
INSERT INTO conf (`key`, `value`, `desc`) VALUES
('WX_WALLET_BALANCE_CAP_CNY',         '100000000', '单账户余额上限(分,默认 100 万元)'),
('WX_WITHHOLD_DAILY_COUNT_MAX',       '5',         '单日提现次数上限'),
('WX_WITHHOLD_DAILY_AMOUNT_MAX_CNY',  '5000000',   '单日提现总额上限(分,默认 5 万元)'),
('WX_RECHARGE_AMOUNT_MIN_CNY',        '100',       '单笔充值最低(分,默认 1 元)'),
('WX_AUDIT_LOCK_TIMEOUT_MINUTES',     '30',        '审核锁定超时分钟');

-- 4.6 (可选)给一个示例支付方式,管理员后台可改
-- 不强制初始化,管理员第一次登录后台时手动创建

-- ============================================================
-- Step 5: 校验
-- ============================================================
-- 执行完后 grep 是否有遗漏:
-- SHOW TABLES LIKE 'wx_pay_method';
-- SHOW TABLES LIKE 'wx_user_payout_account';
-- SHOW TABLES LIKE 'wx_wallet_security_qa';
-- SHOW TABLES LIKE 'wx_security_question';
-- SHOW TABLES LIKE 'wx_unmatched_payment';
-- DESC wx_wallet_coin;  -- 应有 frozen_cny 字段
-- DESC wx_user_recharge_item;  -- 应有 audit_status 等
-- SELECT COUNT(*) FROM wx_security_question;  -- 应 = 8
-- SELECT COUNT(*) FROM mg_auth WHERE id BETWEEN 2000 AND 2299;  -- 应 = 38

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- 回滚预案(若 Step 2 出错)
-- ============================================================
-- 仅在执行前 mysqldump 完整备份,出错时:
-- mysql tio_site_main < backup_before_wallet_v2_<DATE>.sql
-- 并删除新建的 5 张表:
-- DROP TABLE IF EXISTS wx_pay_method;
-- DROP TABLE IF EXISTS wx_user_payout_account;
-- DROP TABLE IF EXISTS wx_wallet_security_qa;
-- DROP TABLE IF EXISTS wx_security_question;
-- DROP TABLE IF EXISTS wx_unmatched_payment;
