### These are the files used to scrape data from the Chess.com API

- **pgn-scraper-thread-chunks.py** is the most recent script I used. It used multithreading to optimize speed, 
    and splits (or chunks) the output PGN files if they get too large.