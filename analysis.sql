CREATE DATABASE user_behavior_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS user_behavior (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    item_id INT,
    category_id INT,
    behavior_type VARCHAR(10),
    timestamp INT
);

-- 1. 总行数（应该是 100000）
SELECT COUNT(*) FROM user_behavior;

-- 2. 看前 5 行
SELECT * FROM user_behavior LIMIT 5;

-- 3. 看各行为类型的分布（确认数据正常）
SELECT behavior_type, COUNT(*) 
FROM user_behavior 
GROUP BY behavior_type;

-- 1.添加三个新列
alter table user_behavior
add column behavior_datetime datetime,
add column behavior_date date,
add column behavior_hour tinyint;

-- 2.转换时间戳格式
update user_behavior
set
    behavior_datetime = from_unixtime(timestamp),
    behavior_date = date(from_unixtime(timestamp)),
    behavior_hour = hour(from_unixtime(timestamp));
    
-- 检查异常时间
select
    min(behavior_date) as 最早日期,
    max(behavior_date) as 最晚日期,
    count(*) as 总行数
from user_behavior;

-- 删除异常时间数据
delete from user_behavior
where behavior_date < '2017-11-25'
   or behavior_date > '2017-12-03';
   
select count(*) as 清洗后剩余行数 from user_behavior;

select distinct behavior_type from user_behavior;

-- 检查重复数据 
select
	user_id, item_id, category_id, behavior_type, timestamp,
    count(*) as 重复次数
from user_behavior
group by user_id, item_id, category_id, behavior_type, timestamp
having count(*) > 1;

SELECT 
    MIN(behavior_date) AS 最早日期,
    MAX(behavior_date) AS 最晚日期,
    COUNT(*) AS 总行数 
FROM user_behavior;

-- 分析1：总体概览指标 
select
    count(distinct user_id) as 独立用户数,
    count(distinct item_id) as 商品总数,
    count(distinct category_id) as 商品类目数,
    count(*) as 总行为记录数,
    count(distinct behavior_date) as 分析天数
from user_behavior;

-- 分析2：各行为类型分布
select
    behavior_type,
    count(*) as 行为次数,
    round(count(*) * 100.0 / (select count(*) from user_behavior), 2) as 占比百分比
from user_behavior
group by behavior_type
order by 行为次数 desc;

-- 分析3：每日活跃度趋势
select
    behavior_date as 日期,
    count(distinct user_id) as 日活跃用户数_UV,
    sum(case when behavior_type = 'pv' then 1 else 0 end) as 日浏览量_PV,
    sum(case when behavior_type = 'buy' then 1 else 0 end) as 日购买量
from user_behavior
group by behavior_date
order by behavior_date;

-- 分析4：每小时活跃度
select behavior_hour as 时间段,
count(distinct user_id) as 活跃用户数,
count(*) as 行为总数
from user_behavior
group by behavior_hour
order by behavior_hour;

-- 分析5：用户行为漏斗
with user_behavior_flag as (
    select
        user_id,
        max(case when behavior_type = 'pv' then 1 else 0 end) as has_view,
        max(case when behavior_type = 'cart' then 1 else 0 end) as has_cart,
        max(case when behavior_type = 'fav' then 1 else 0 end) as has_fav,
        max(case when behavior_type = 'buy' then 1 else 0 end) as has_buy
	from user_behavior
    group by user_id
)
select
    count(*) as 总用户数,
    sum(has_view) as 浏览用户数,
    sum(has_cart) as 加购用户数,
    sum(has_fav) as 收藏用户数,
    sum(has_buy) as 购买用户数,
    round(sum(has_cart) * 100.0 / sum(has_view), 2) as 浏览到加购转化率,
    round(sum(has_buy) * 100.0 / sum(has_view), 2) as 浏览到购买转化率,
    round(sum(has_buy) * 100.0 / sum(has_cart), 2) as 加购到购买转化率
from user_behavior_flag;

-- 分析6：用户复购行为分布
with user_purchase_count as (
    select
        user_id,
        count(*) as purchase_times
	from user_behavior
    where behavior_type = 'buy'
    group by user_id
)
select
    case
        when purchase_times =  0 then '未购买'
        when purchase_times =  1 then '购买1次'
        when purchase_times =  2 then '购买2次'
        when purchase_times >=  3 then '购买3次及以上'
	end as 购买次数分组,
    count(*) as 用户数,
    round(count(*) * 100.0 / (select count(distinct user_id) from user_behavior), 4) as 占比
from user_purchase_count 
group by 购买次数分组
order by 购买次数分组;

-- 分析7：用户价值分层
with user_metrics as (
    select
        user_id,
        count(distinct behavior_date) as 活跃天数,
        sum(case when behavior_type = 'pv' then 1 else 0 end) as 浏览次数,
        sum(case when behavior_type = 'cart' then 1 else 0 end) as 加购次数,
        sum(case when behavior_type = 'buy' then 1 else 0 end) as 购买次数,
        datediff('2017-12-03', max(behavior_date)) as 最近购买距今天数
	from user_behavior
    group by user_id
)
select
    case
        when 购买次数 >= 3 and 最近购买距今天数 <= 1 then '高价值活跃用户'
        when 购买次数 >= 1 and 最近购买距今天数 <= 3 then '一般活跃用户'
        when 购买次数 >= 1 and 最近购买距今天数 > 3 then '沉睡购买用户'
        when 购买次数 = 0 and 浏览次数 > 10 then '高潜浏览用户'
	    else '普通浏览用户'
	end as 用户分层,
    count(*)as 用户数,
    round(avg(浏览次数), 1) as 平均浏览次数,
    round(avg(购买次数), 2) as 平均购买次数
from user_metrics
group by 用户分层
order by 用户数 desc;

-- 分析8：热门商品类目 TOP10
select
    category_id,
    count(*) as 购买次数
from user_behavior
where behavior_type = 'buy'
group by category_id
order by 购买次数 desc
limit 10;