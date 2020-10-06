import cassandra
import os
import glob
import logging
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider

# Configure the logger settings
logger = logging.getLogger()
logger.setLevel(logging.INFO)
formatter = logging.Formatter('%(levelname)s: %(asctime)s: %(message)s')
ch = logging.StreamHandler()
ch.setFormatter(formatter)  # add formatter to ch
logger.addHandler(ch)  # add ch to logger


def connect(cassandra_seeds, keyspace_name, rep_factor):
    """Connect to a cassandra cluster, and create a keyspace if it does not exist"""
    cluster = Cluster(contact_points=cassandra_seeds, protocol_version=4,
                      auth_provider=PlainTextAuthProvider(username='ubuntu', password='test123'))
    session = cluster.connect()
    # Create keyspace if it does not exist
    query = """
        CREATE KEYSPACE IF NOT EXISTS {} 
        WITH REPLICATION = 
        {{ 'class' : 'SimpleStrategy', 'replication_factor' : {} }};
        """.format(keyspace_name, rep_factor)
    session.execute(query)

    session = cluster.connect(keyspace_name)
    logger.info(f"Connected to {keyspace_name} keyspace ................")
    return session


def create_tables(session):
    # Drop tables if they exist first
    session.execute("DROP TABLE IF EXISTS games")
    session.execute("DROP TABLE IF EXISTS moves")

    query = "CREATE TABLE IF NOT EXISTS games "
    # Partition by eco (opening sequence), sort by timestamp
    query = query + "(event varchar, gameid text, white varchar, black varchar, result text, \
                      datetime text, timestamp int, whiteelo int, blackelo int, eco text, \
                      opening varchar, timecontrol varchar, termination varchar, moves varchar, \
                      PRIMARY KEY (eco, timestamp))"
    session.execute(query)
    logger.info("Creating games table ................")

    query = "CREATE TABLE IF NOT EXISTS moves "
    # Partition by board_state, sort by moves and blackelo
    query = query + "(gameid text, result text, whiteelo int, blackelo int, eco text, timecontrol varchar, \
                      termination varchar, moves varchar, board_state varchar, move_no int, \
                      PRIMARY KEY (board_state, blackelo, moves))"
    session.execute(query)
    logger.info("Creating moves table ................")


def main():
    """
    """
    seeds = ["10.0.0.7"]
    keyspace = "chessdb"
    rep_factor = 2
    session = connect(cassandra_seeds=seeds, keyspace_name=keyspace, rep_factor=rep_factor)
    create_tables(session)


if __name__ == "__main__":
    main()
