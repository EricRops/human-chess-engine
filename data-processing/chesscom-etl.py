from pyspark import SparkContext
from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
from pyspark.sql import Window
import logging
import chess

# Setup the logging output print settings (logging to a file)
logger = logging.getLogger(__name__)
formatter = logging.Formatter('%(levelname)s: %(asctime)s: %(message)s')
logger.setLevel(logging.INFO)
fh = logging.FileHandler('logfile.log', mode='w')
fh.setLevel(logging.INFO)
fh.setFormatter(formatter)
logger.addHandler(fh)


def create_spark_session(region, cassandra_seeds):
    """
    - Create a Spark session to perform the ETL tasks
    :param region: AWS region our S3 bucket is in
    :param cassandra_seeds: IP addresses for the Cassandra seed nodes
    """
    sc = SparkContext()
    sc._jsc.hadoopConfiguration().set('fs.s3a.endpoint', f's3-{region}.amazonaws.com')
    spark = SparkSession(sc) \
        .builder \
        .appName("SparkCassandraETL") \
        .config('spark.cassandra.connection.host', ','.join(cassandra_seeds)) \
        .config('spark.cassandra.output.batch.grouping.key', 'none') \
        .config('spark.cassandra.output.concurrent.writes', 5) \
        .config('spark.cassandra.output.batch.grouping.buffer.size', 1000) \
        .getOrCreate()
    return spark


def process_games(spark, input_files):
    """
    - Load the chess PGN files from s3 to a spark DF
    - Process the data and return a DF with one row for each game
    :param spark: SparkSession object
    :param input_files: S3 bucket and directory containing the PGN files
    :return: a DF with the data from each game (one row per game)
    """
    chess_files = input_files

    # read pgn text data
    logger.info(f"Reading pgn data from {chess_files} ..........")

    # Split the data by each game rather than by each line
    df = spark.read.text(chess_files, lineSep="[Event")
    logger.info(f"{df.count()} total games loaded .............. ")

    # Remove empty rows
    df = df.filter("value != ''")

    # Remove all NON-STANDARD chess games (ex: Chess 960)
    df = df.filter(~col("value").contains("Variant"))
    df = df.filter(~col("value").contains("SetUp"))

    # Only keep games that actually started (an opening is recorded, and a first move)
    df = df.filter(col("value").contains("ECOUrl"))
    df = df.filter(col("value").contains("1... "))

    # Split each game into separate columns (separated by new line \n in PGN files)
    df = df.withColumn("splitStr", split(df["value"], "\n"))

    # Define UDF to filter out array elements containing fields we do not want.
    # Necessary because array filtering NOT available in Spark 2.4.7
    def drop_from_array(arr):
        arr = [x for x in arr if "WhiteTitle" not in x]
        arr = [x for x in arr if "BlackTitle" not in x]
        arr = [x for x in arr if "[Site" not in x]
        arr = [x for x in arr if "[Date" not in x]
        arr = [x for x in arr if "[EndDate" not in x]
        arr = [x for x in arr if "[StartTime" not in x]
        arr = [x for x in arr if "[EndTime" not in x]
        arr = [x for x in arr if "[Round" not in x]
        arr = [x for x in arr if "CurrentPosition" not in x]
        arr = [x for x in arr if "[FEN" not in x]
        arr = [x for x in arr if "[PGN" not in x]
        arr = [x for x in arr if "[SetUp" not in x]
        arr = [x for x in arr if "[Tournament" not in x]
        arr = [x for x in arr if "[Match" not in x]
        arr = [x for x in arr if "Timezone" not in x]
        arr = [x for x in arr if "WhiteRatingDiff" not in x]
        arr = [x for x in arr if "BlackRatingDiff" not in x]
        return arr
    drop_from_array_udf = udf(drop_from_array, ArrayType(StringType()))
    df = df.withColumn("splitStr", drop_from_array_udf(df.splitStr))

    firstrow = df.first()

    # The first game headers will be used to decide the column labels
    splitStrLength = len(firstrow.splitStr)

    # Troubleshooting log prints (only uncomment when needed)
    # logger.info(splitStrLength)
    # logger.info(firstrow.splitStr)
    # logger.info(df.drop("value").limit(3).collect())

    # Loop through all columns. Populate data and assign labels based on the first row
    # The last 2 fields are empty for each game (weird PGN reasons), so skip them
    for index in range(0, splitStrLength-2):
        # The fourth-last item is also empty, skip it
        if index == splitStrLength-4:
            continue
        data = df.splitStr.getItem(index)
        # The [0] gets the first word for the column label (ex: [Result from [Result "1-0"]
        # The [1:] trims off the "[" from the column label
        label = firstrow.splitStr[index].split(' ', 1)[0][1:]
        # The Event label was truncated earlier when we split the data by game instead of by row
        if index == 0:
            label = "Event"
        # The 3rd last item is the game moves data. Label it "Moves"
        if index == splitStrLength-3:
            label = "Moves"
        df = df.withColumn(label, data)
        # Remove all noise from the METADATA info columns (Last item is the moves, or empty)
        if index in range(splitStrLength-4):
            df = df.withColumn(label, regexp_replace(label, label, ''))       # Remove the header string
            df = df.withColumn(label, regexp_replace(label, "[\\[\\]]", ''))  # Remove square brackets
            df = df.withColumn(label, regexp_replace(label, '"', ''))         # Remove quotes
            df = df.withColumn(label, regexp_replace(label, "^\\s+", ""))     # Leading whitespace

    # Combine date and time columns to create timestamp
    df = df.withColumn('datetime', concat_ws(' ', 'UTCDate', 'UTCTime'))
    df = df.withColumn('timestamp', unix_timestamp(col("datetime"), 'yyyy.MM.dd HH:mm:ss'))

    df.drop("value").drop("splitStr").show(3)  # Test
    # Replace any null timestamps with zeros (so we can load to Cassandra)
    df = df.na.fill({'timestamp': 0})

    # Change player ratings to integers
    df = df.withColumn("whiteelo", regexp_replace('whiteelo', ' ', '').cast(IntegerType()))
    df = df.withColumn("blackelo", regexp_replace('blackelo', ' ', '').cast(IntegerType()))

    # Drop unneccesary columns and change some column names
    columns_to_drop = ['value', 'splitStr', 'UTCDate', 'UTCTime']
    df = df.drop(*columns_to_drop).withColumnRenamed("Link", "gameid").withColumnRenamed("ECOUrl", "opening")

    # Trim the URL address off the opening
    df = df.withColumn('opening', regexp_replace('opening', 'https://www.chess.com/openings/', ''))

    # Trim the URL address off the gameid, and remove any duplicates
    df = df.withColumn('gameid', regexp_replace('gameid', 'https://www.chess.com', 'chesscom'))
    df = df.dropDuplicates(['gameid'])

    # Change column names to lowercase
    df = df.toDF(*[c.lower() for c in df.columns])

    logger.info(f"{df.count()} Games processed")
    logger.info(f"Games DF Schema:")
    schema_str = df._jdf.schema().treeString()
    logger.info(schema_str)
    logger.info(f"Top few rows of the games DF:")
    logger.info(df.limit(3).collect())

    df.show(3)  # Test

    return df


def game_moves(df_games):
    """
    - Process the games DF into a moves DF (one row for each move ever made in history)
    :param df_games: the games DF from the previous function
    :return: game_moves DF
    """
    # Drop unnecessary columns
    columns_to_drop = ['event', 'white', 'black', 'datetime', 'timestamp', 'opening', 'eco', 'termination']
    df = df_games.drop(*columns_to_drop)

    # Filter out all the noise from the moves column so we are left with only spaces between each move
    df = df.withColumn("moves", regexp_replace("moves", "[0-9]+\\.|\\.", ""))    # Any numbers followed by a dot
    df = df.withColumn("moves", regexp_replace("moves", "\\{.*?\\}", ""))        # Everything inside curly braces
    df = df.withColumn("moves", regexp_replace("moves", "   |  ", " "))          # All triple or double spaces
    df = df.withColumn("moves", regexp_replace("moves", "1-0|0-1|1/2-1/2|!|\\?", ""))  # Game results, ?s and !s
    df = df.withColumn("moves", regexp_replace("moves", "^\\s+|\\s+$", ""))      # Leading and trailing whitespace

    # Convert the moves string column to an array, to feed into the UDF
    df = df.withColumn("moves", split(df.moves, " "))
    # df = df.limit(10000)  # limit to 10000 games for testing only

    # Drop games with less than three moves
    df = df.filter(size('moves') > 2)

    # Testing: print where [Termination appears in moves
    df.filter(array_contains(df.moves, "BlackTitle")).show()

    def board_state(moves):
        """Return a list of board state FEN strings from a list of moves"""
        board = chess.Board()
        start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq"
        # Append to list of board states (starting with the initial board configuration)
        states = [start]
        for move in moves:
            board.push_san(move)
            fen = board.fen()
            # Remove the en passant and pawn timer parameters (too specific, would eliminate most searches)
            fen = " ".join(fen.split(" ")[:3])
            states.append(fen)
        return states

    board_state_udf = udf(board_state, ArrayType(StringType()))
    df = df.withColumn("board_state", board_state_udf(df.moves))

    # Now explode into one row for each move (need to explode by both moves and board_state columns):
	# 1. arrays_zip function merges the moves and board_state columns (which are arrays)
	# 2. explode function then explodes each (moves, board_state) pair into a separate row
    df = df.withColumn("tmp", arrays_zip("moves", "board_state")) \
        .withColumn("tmp", explode("tmp")) \
        .select("gameid", "result", "whiteelo", "blackelo",
                "timecontrol", col("tmp.moves"), col("tmp.board_state"))

    # Replace the null last move values with empty strings (so we can load to Cassandra)
    df = df.na.fill({'moves': ''})

    # Finally, create a move order column
    window = Window.partitionBy(df["gameid"]).orderBy(monotonically_increasing_id())
    df = df.withColumn('move_no', rank().over(window))

    logger.info(f"{df.count()} Moves processed")
    logger.info(f"Moves DF Schema:")
    schema_str = df._jdf.schema().treeString()
    logger.info(schema_str)

    # Test
    logger.info(df.limit(3).collect())

    df.show(100)  # Test

    return df


def write_to_cassandra(df, keyspace, table, partition_key):
    """
    - Tried sorting DF by partition key before writing, but no noticeable performance difference
    - Write DF to a Cassandra table
    """
    logger.info(f"Writing df to Cassandra table: {keyspace}.{table} .............")
    df.write.format("org.apache.spark.sql.cassandra") \
        .mode('append').options(table=table, keyspace=keyspace).save()
    logger.info(f"Writing complete .............")


def main():
    """
    - Create Spark Session
    - Load games data from S3
    - Process games data into games DF
    - Process games DF into a moves DF
    - Write to Cassandra using Datastax Spark-Cassandra connector
    """
    cassandra_seeds = ['10.0.0.11', '10.0.0.10']
    region = 'us-west-2'
    bucket = 'erops-chess'
    key = 'chesscom-db/titled-games'
    spark = create_spark_session(region=region, cassandra_seeds=cassandra_seeds)
    input_data = f"s3a://{bucket}/{key}/IM-games*"
    df_games = process_games(spark=spark, input_files=input_data)
    df_moves = game_moves(df_games=df_games)
    write_to_cassandra(df=df_games, keyspace="chessdb", table="games", partition_key="eco")
    write_to_cassandra(df=df_moves, keyspace="chessdb", table="moves", partition_key="board_state")

    spark.stop()


if __name__ == "__main__":
    main()
