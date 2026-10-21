USE shop;
SHOW TABLES;
DESCRIBE sales_daily;
SHOW PARTITIONS sales_daily;
SELECT sale_date, SUM(orders) AS orders, ROUND(SUM(revenue), 2) AS revenue
FROM sales_daily
GROUP BY sale_date
ORDER BY sale_date;
SELECT * FROM sales_daily WHERE sale_date = '2026-10-07' ORDER BY revenue DESC LIMIT 5;
