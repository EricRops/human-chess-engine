import cassandra
import os
import glob
import logging
import pandas as pd  # ONLY used for pretty printing queries :)
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider

# Configure the logger settings
logger = logging.getLogger()
logger.setLevel(logging.INFO)
formatter = logging.Formatter('%(levelname)s: %(asctime)s: %(message)s')
ch = logging.StreamHandler()
ch.setFormatter(formatter)  # add formatter to ch
logger.addHandler(ch)  # add ch to logger


def pandas_factory(colnames, rows):
    """Function to allow a pandas DF be returned from a cassandra query"""
    return pd.DataFrame(rows, columns=colnames)


def connect(cassandra_seeds, keyspace_name):
    """Connect to a cassandra cluster"""
    cluster = Cluster(contact_points=cassandra_seeds, protocol_version=4,
                      auth_provider=PlainTextAuthProvider(username='ubuntu', password='test123'))
    session = cluster.connect(keyspace_name)
    logger.info(f"Connected to {keyspace_name} keyspace ................")
    return session


def main():
    """
    """
    seeds = ["10.0.0.7"]
    keyspace = "chessdb"
    session = connect(cassandra_seeds=seeds, keyspace_name=keyspace)
    session.row_factory = pandas_factory
    # needed for large queries, else driver will do pagination. Default is 50000.
    session.default_fetch_size = 10000000

    board_state = "rnbqkbnr/ppp1pppp/3p4/8/2P5/3P4/PP2PPPP/RNBQKBNR b KQkq"
    query = """
        SELECT moves, blackelo
        FROM chessdb.moves
        WHERE board_state = '{}'
        AND blackelo >= 1500
        """.format(board_state)
    rows = session.execute(query)
    df = rows._current_rows
    logger.info(query)
    logger.info(df)
    logger.info("Most common next move:")
    logger.info(df.moves.mode())


if __name__ == "__main__":
    main()
