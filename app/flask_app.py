from flask import Flask, render_template, session, request, redirect, url_for, flash
from chess_engine import *
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider
import pandas as pd
import sys

cassandra_seeds = ['10.0.0.11', '10.0.0.10']
cluster = Cluster(contact_points=cassandra_seeds, protocol_version=4,
                  auth_provider=PlainTextAuthProvider(username='ubuntu', password='test123'))
cassandra = cluster.connect('chessdb')

app = Flask(__name__)
app.secret_key = 'let-me-use-session'


@app.route('/')
def index():
    return render_template("index.html")


@app.route('/move/<int:depth>/<path:fen>/')
def get_move(depth, fen):
    engine = Engine(fen)
    # Between 1 and 5. Hardest is 5. Used for moves when no matches in the database.
    engine_depth = 3
    move_engine = engine.iterative_deepening(engine_depth - 1)

    # ERIC's ADDITIONS (aka, messing with the original masterpiece)
    # Get next move by querying the Cassandra DB
    # In cases with no match, use "brokenloop" (FlaskChess creator's) engine above to generate the move

    def pandas_factory(colnames, rows):
        """Function to allow a pandas DF be returned from a Cassandra query"""
        return pd.DataFrame(rows, columns=colnames)
    cassandra.row_factory = pandas_factory

    fen_trim = " ".join(fen.split(" ")[:3])
    print("Input FEN:")
    print(fen_trim)

    # Because I'm building this off a black-box, using the creators pre-defined depth variable to
    # capture the rating variable I need for the Cassandra query.
    rating = depth
    ratingmax = rating + 500
    ratingmin = rating - 500
    cassandra.default_fetch_size = 2000000
    cassandra.default_timeout = 60
    query = """
        SELECT moves, blackelo FROM chessdb.moves
        WHERE board_state = '{}' 
        AND blackelo > {} AND blackelo < {}
        """.format(fen_trim, ratingmin, ratingmax)
    rows = cassandra.execute(query)
    df = rows._current_rows
    print(query)
    print("Query Returned:")
    print(df)

    if len(df) > 0:
        move = df.moves.mode()[0]
        print("Most Common Next Move:", file=sys.stderr)
        print(move)
        return move
    else:
        move = move_engine
        print("No matches in database!! Using engine to generate move:")
        print(move)
        return move


@app.route('/test/<string:tester>')
def test_get(tester):
    return tester


if __name__ == '__main__':
    app.run(debug=True)
