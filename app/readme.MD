### NOTE: I did not build this Flask app for chess.
It was taken from this repo: https://github.com/brokenloop/FlaskChess. Many thanks to *brokenloop,* otherwise my user interface 
would not have been possible given the timeline.

All I did was make some additions to **flask_app.py** to connect to Cassandra.


### Below is brokenloop's original README:

This is a simple chess engine/interface created using flask.
It uses chessboard.js and chess.js for the logic of the frontend chessboard, and python chess for the
logic of the backend chessboard. All calculation is done on the backend using python.

In order to run this application on your own machine, please install flask and python chess.

Install flask by running:
    pip install flask

Install python chess by running:
    pip install python-chess[uci,gaviota]