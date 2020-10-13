import cassandra
import os
import glob
import logging
import sys
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
    """Function to allow a pandas DF be returned from a Cassandra query"""
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
    - Connect to Cassandra keyspace
    - Run query to return the most common next move to make, given a board state
    """
    seeds = ['10.0.0.11', '10.0.0.10']
    keyspace = "chessdb"
    session = connect(cassandra_seeds=seeds, keyspace_name=keyspace)
    session.row_factory = pandas_factory
    # Needed for large queries, else driver will do pagination. Default is 5000.
    session.default_fetch_size = 10000000
    session.default_timeout = 60

    # board_state to search for comes via the command line
    board_state = sys.argv[1]
    query = """
        SELECT moves, blackelo
        FROM chessdb.moves
        WHERE board_state = '{}'
        AND blackelo > 500
        """.format(board_state)
    rows = session.execute(query)
    df = rows._current_rows
    logger.info(query)
    logger.info(df)
    logger.info("Most common next move:")
    logger.info(df.moves.mode())


if __name__ == "__main__":
    main()
