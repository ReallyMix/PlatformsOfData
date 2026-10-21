CREATE DATABASE IF NOT EXISTS shop;
USE shop;

CREATE EXTERNAL TABLE IF NOT EXISTS orders_raw (
    order_id INT,
    order_date STRING,
    customer STRING,
    product STRING,
    price DOUBLE,
    quantity INT
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/user/hive/raw/orders'
TBLPROPERTIES ('skip.header.line.count' = '1');

CREATE TABLE IF NOT EXISTS orders (
    order_id INT,
    customer STRING,
    product STRING,
    price DOUBLE,
    quantity INT
)
PARTITIONED BY (order_date STRING)
STORED AS PARQUET
LOCATION '/user/hive/warehouse/shop.db/orders';

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;

INSERT OVERWRITE TABLE orders PARTITION (order_date)
SELECT order_id, customer, product, price, quantity, order_date
FROM orders_raw;

SHOW PARTITIONS orders;
SELECT order_date, COUNT(*) AS orders_cnt FROM orders GROUP BY order_date;
