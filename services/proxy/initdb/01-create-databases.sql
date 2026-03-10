-- HamR 数据库初始化
-- 创建各服务所需的数据库

\c postgres

CREATE DATABASE hamr_account;
CREATE DATABASE hamr_app;

GRANT ALL PRIVILEGES ON DATABASE hamr_account TO hamr;
GRANT ALL PRIVILEGES ON DATABASE hamr_app TO hamr;
