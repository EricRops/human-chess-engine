from pyspark import SparkContext
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql import types as T
import logging

# Setup the logging output print settings (logging to a file)
logger = logging.getLogger(__name__)
formatter = logging.Formatter('%(levelname)s: %(asctime)s: %(message)s')
logger.setLevel(logging.INFO)
fh = logging.FileHandler('logfile.log', mode='w')
fh.setLevel(logging.INFO)
fh.setFormatter(formatter)
logger.addHandler(fh)


def create_spark_session(region):
    """
    - Create a Spark session to perform the ETL tasks
    """
    sc = SparkContext()
    sc._jsc.hadoopConfiguration().set('fs.s3a.endpoint', f's3-{region}.amazonaws.com')
    spark = SparkSession(sc) \
        .builder \
        .appName("SparkETL") \
        .getOrCreate()
    return spark


def process_lichess_data(spark, input_files):
    """
    """
    chess_files = f"{input_files}/lichess_db_standard_rated_2013-01.pgn"
    label0 = "Event"

    # read pgn text data
    logger.info(f"Reading pgn data from {chess_files} ..........")
    # Split the data by each game rather than by each line
    df = spark.read.text(chess_files, lineSep="[Event")
    logger.info(f"{df.count()} total games loaded .............. ")
    # df = pgn_data.limit(5)

    # Remove empty rows
    df = df.filter("value != ''")

    df = df.withColumn("splitStr", F.split(df["value"], "\n"))
    firstrow = df.first()
    df = df.withColumn(label0, df.splitStr.getItem(0))

    # Extract column labels and text data for each column
    splitStrLength = len(firstrow.splitStr)
    # Omitting the "0" index, because we dealt with the 1st column separately above.
    # The last 2 fields are empty for each game (PGN formatted rows), so skip them
    for index in range(1, splitStrLength-2):
        # The fourth-last item is also empty, skip it
        if index == splitStrLength-4:
            continue
        data = df.splitStr.getItem(index)
        # The [0] gets the first word for the column label (ex: [Result from [Result "1-0"]
        # The [1:] trims off the "[" from the column label
        label = firstrow.splitStr[index].split(' ', 1)[0][1:]
        # The third last item is the game moves data. Label it "Moves"
        if index == splitStrLength-3:
            label = "Moves"
        df = df.withColumn(label, data)
        # Remove the header string and square brackets from the column data
        # (METADATA ONLY: Excluding the last 4 string fields. The last 2 fields are empty for each game)
        if index in range(splitStrLength-4):
            df = df.withColumn(label, F.regexp_replace(label, label, ''))
            df = df.withColumn(label, F.regexp_replace(label, "[\\[\\]]", ''))

    logger.info(f"{df.count()} Games processed")
    logger.info(f"DF Schema:")
    schema_str = df._jdf.schema().treeString()
    logger.info(schema_str)
    logger.info(f"Top few rows of the processed DF:")
    logger.info(df.limit(3).collect())

    df.limit(100).show()

    return df


def main():
    """
    """
    region = 'us-west-2'
    bucket = 'erops-chess'
    key = 'lichess-db'
    spark = create_spark_session(region=region)
    input_files = f"s3a://{bucket}/{key}"
    process_lichess_data(spark=spark, input_files=input_files)

    spark.stop()


if __name__ == "__main__":
    main()
