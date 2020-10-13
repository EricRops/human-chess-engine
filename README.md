<p align="center">
    <img src="images/chess-cover.PNG" width="800" height="250"/>
</p>

# Human Chess Engine: Play Chess Against a Database!
## Insight Data Engineering

## Motivation
About 20 million users are active on the top three online chess platforms. The main ways that people play are:
- Human vs human
- Human vs chess engine (ex: Stockfish)
- Human vs Artificial Intelligence (if you want to lose real bad. Ex: Google DeepMind's AlphaZero)

However, I wanted a way to play against all the humans that have ever played before.

## Solution
Play chess against a historic database! The user makes their move. The database returns the **most common next move.**  
A demo of the final product is here: ADD YOUTUBE LINK  
The website of the Flask app is here: [chess.clouddata.club](chess.clouddata.club)

## Dataset
- 1.5 billion games from [lichess.org](https://database.lichess.org/)
- [Chess.com API](https://www.chess.com/news/view/published-data-api) (Over 1 billion games stored) 
- **NOTE:** Due to the three week timeframe, I was able to get 100 million games processed.
- This works out to **4 billion historic board configurations** (about 1 TB of data)

## PGN Files
Chess games are stored in Portable Game Notation (PGN) files. Below is a sample file from 1 game:
<img src="images/pgn-file.png">

## Data Pipeline
<img src="images/pipeline.PNG">

## Cassandra Data Model
Two tables were stored in Cassandra:
- **games:** one row for each game (100 million rows)
    + *event, white, black, result, eco, opening, whiteelo, blackelo, timecontrol, termination, gameid, moves, datetime, timestamp*
- **moves:** one row for each move (4 billion rows)
    + *gameid, result, whiteelo, blackelo, timecontrol, move, board_state, move_no*

## Cassandra Query
Cassandra gives excellent query speed if the type of query is *always the same and has no aggregations.*
To accomplish the query, the **moves** table needed the following **Primary Key:**
- **Partition Column:** board_state
- **Clustering Columns:** blackelo, gameid 

After processing in Spark, the Cassandra query used to generate the moves was actually quite simple:
```
SELECT moves, blackelo FROM chessdb.moves
WHERE board_state = 'BOARD_STATE_FEN' 
AND blackelo > {ratingmin} AND blackelo < {ratingmax}
```

## Flask App
[chess.clouddata.club](chess.clouddata.club)

## Youtube Demo Link

## Future Production Improvements
- Attach Airflow to continuously expand the database. Will improve the experience and minimize query “no results”
- Create another Cassandra table to allow the option of playing as the black pieces