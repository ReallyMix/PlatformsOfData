from prefect import flow, task
from prefect.cache_policies import NO_CACHE
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

HDFS_URL = "hdfs://team-24-nn:9000"
INPUT = HDFS_URL + "/user/prefect/input/trips.csv"
OUTPUT = HDFS_URL + "/user/hive/warehouse/taxi.db/trips_daily"
TABLE = "taxi.trips_daily"


@task(cache_policy=NO_CACHE)
def start_spark():
    spark = (
        SparkSession.builder
        .appName("hw5-prefect-trips")
        .master("yarn")
        .enableHiveSupport()
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")
    print("master:", spark.sparkContext.master)
    print("application id:", spark.sparkContext.applicationId)
    return spark


@task(cache_policy=NO_CACHE)
def connect_hdfs(spark):
    jvm = spark.sparkContext._jvm
    conf = spark.sparkContext._jsc.hadoopConfiguration()
    fs = jvm.org.apache.hadoop.fs.FileSystem.get(jvm.java.net.URI(HDFS_URL), conf)
    print("подключено к HDFS:", fs.getUri().toString())
    path = jvm.org.apache.hadoop.fs.Path(INPUT)
    if not fs.exists(path):
        raise FileNotFoundError(INPUT + " не найден, сначала выполните scripts/02_upload.sh")
    print("размер входного файла:", fs.getFileStatus(path).getLen(), "байт")


@task(cache_policy=NO_CACHE)
def read_data(spark):
    raw = spark.read.option("header", "true").csv(INPUT)
    print("прочитано строк:", raw.count())
    raw.printSchema()
    return raw


@task(cache_policy=NO_CACHE)
def transform(raw):
    trips = (
        raw
        .withColumn("pickup_time", F.to_timestamp("pickup_time", "yyyy-MM-dd HH:mm:ss"))
        .withColumn("distance_km", F.regexp_replace("distance_km", ",", ".").cast("double"))
        .withColumn("fare", F.col("fare").cast("double"))
        .withColumn("rating", F.col("rating").cast("int"))
        .withColumn("district", F.initcap(F.trim(F.col("district"))))
        .withColumn("payment_type", F.lower(F.trim(F.col("payment_type"))))
        .filter(F.col("pickup_time").isNotNull() & F.col("fare").isNotNull() & (F.col("distance_km") > 0))
        .withColumn("trip_date", F.date_format("pickup_time", "yyyy-MM-dd"))
        .withColumn("price_per_km", F.col("fare") / F.col("distance_km"))
    )
    print("строк после очистки:", trips.count())
    trips.printSchema()

    daily = (
        trips.groupBy("trip_date", "district")
        .agg(
            F.count("*").alias("trips"),
            F.round(F.sum("fare"), 2).alias("total_fare"),
            F.round(F.avg("distance_km"), 2).alias("avg_distance_km"),
            F.round(F.avg("price_per_km"), 2).alias("avg_price_per_km"),
            F.round(F.avg("rating"), 2).alias("avg_rating"),
            F.round(F.avg(F.when(F.col("payment_type") == "card", 1).otherwise(0)) * 100, 1).alias("card_share_pct"),
        )
    )
    return daily


@task(cache_policy=NO_CACHE)
def save_table(spark, daily):
    spark.sql("CREATE DATABASE IF NOT EXISTS taxi")
    (
        daily.write
        .mode("overwrite")
        .format("parquet")
        .option("path", OUTPUT)
        .saveAsTable(TABLE)
    )
    print("таблица сохранена:", TABLE, "->", OUTPUT)


@task(cache_policy=NO_CACHE)
def check_table(spark):
    result = spark.table(TABLE)
    print("строк в таблице:", result.count())
    result.orderBy("trip_date", "district").show(30, truncate=False)


@flow(name="hw5-spark-yarn-flow", log_prints=True)
def trips_flow():
    spark = start_spark()
    try:
        connect_hdfs(spark)
        raw = read_data(spark)
        daily = transform(raw)
        save_table(spark, daily)
        check_table(spark)
    finally:
        spark.stop()


if __name__ == "__main__":
    trips_flow()
