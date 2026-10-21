from pyspark.sql import SparkSession
from pyspark.sql import functions as F

HDFS_URL = "hdfs://team-24-nn:9000"
INPUT = HDFS_URL + "/user/spark/input/sales.csv"
OUTPUT = HDFS_URL + "/user/hive/warehouse/shop.db/sales_daily"

spark = (
    SparkSession.builder
    .appName("hw4-sales-daily")
    .master("yarn")
    .enableHiveSupport()
    .getOrCreate()
)
print("master:", spark.sparkContext.master)
print("application id:", spark.sparkContext.applicationId)

raw = spark.read.option("header", "true").csv(INPUT)
print("прочитано строк из", INPUT, ":", raw.count())
raw.printSchema()

clean = (
    raw
    .withColumn("event_time", F.to_timestamp("event_time", "yyyy-MM-dd HH:mm:ss"))
    .withColumn("price", F.col("price").cast("double"))
    .withColumn("quantity", F.col("quantity").cast("int"))
    .filter(F.col("event_time").isNotNull() & F.col("price").isNotNull() & F.col("quantity").isNotNull())
    .withColumn("city", F.initcap(F.trim(F.col("city"))))
    .withColumn("sale_date", F.date_format("event_time", "yyyy-MM-dd"))
    .withColumn("revenue", F.col("price") * F.col("quantity"))
)
print("строк после очистки:", clean.count())
clean.printSchema()

daily = (
    clean.groupBy("sale_date", "city", "category")
    .agg(
        F.count("*").alias("orders"),
        F.sum("quantity").alias("items"),
        F.round(F.sum("revenue"), 2).alias("revenue"),
        F.round(F.avg("price"), 2).alias("avg_price"),
    )
)

spark.sql("CREATE DATABASE IF NOT EXISTS shop")
(
    daily.write
    .mode("overwrite")
    .format("parquet")
    .partitionBy("sale_date")
    .option("path", OUTPUT)
    .saveAsTable("shop.sales_daily")
)

spark.sql("SHOW PARTITIONS shop.sales_daily").show(truncate=False)
spark.table("shop.sales_daily").orderBy("sale_date", F.desc("revenue")).show(10, truncate=False)

spark.stop()
