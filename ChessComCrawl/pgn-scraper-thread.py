import requests
import yaml
import logging
import json
import time
import glob
import ntpath
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, wait, as_completed

# Configure the logger settings
logger = logging.getLogger()
logger.setLevel(logging.INFO)
formatter = logging.Formatter("%(asctime)s : %(levelname)s : %(message)s", "%Y-%m-%d %H:%M:%S")
ch = logging.StreamHandler()
ch.setFormatter(formatter)  # add formatter to ch
logger.addHandler(ch)  # add ch to logger

# IMPORTANT: We are running this script from an AWS EC2 machine
pgn_path = '/mnt/c/Users/ericr/Downloads/Local_Data/insight_data/chess-data/chesscom-db'
users_json_path = './ChessComCrawl/user_lists'

with open('./ChessComCrawl/config.yml') as config_file:
    config = yaml.safe_load(config_file)


def get_usernames_from_json(json_file):
    """Returns list of all the usernames contained in the input json file"""
    with open(json_file) as f:
        data = json.load(f)
        users = data['players']
    return users


def get_user_archives(username):
    """Returns a list of HTTP request strings for all the games of the given user"""
    url = f"https://api.chess.com/pub/player/{username}/games/archives"
    counter = 1
    logging.info("Performing GET request: {}".format(url))
    while True:
        try:
            archives_dict = requests.get(url, headers=config['headers']).json()

            # Process only if there are valid archives for this user
            if "archives" in archives_dict:
                archives = archives_dict["archives"]  # convert dict to list
                break
            else:
                archives = "Null for this user"
                break
        except json.decoder.JSONDecodeError:
            if counter > 10:
                raise ValueError('Errors persist after retrying GET request 10 times')
            else:
                logging.info('ERROR FOUND: retrying request')
                time.sleep(5)
                counter += 1
    return archives


def get_user_monthly_pgns(http):
    """
    :param http: (str): HTTP get request to download the data for a users monthly games
        Example: "https://api.chess.com/pub/player/USERNAME/games/2007/07/pgn"
    :return: Text data of the users monthly games in PGN format
    """
    url = http
    counter = 1
    while True:
        try:
            pgn = requests.get(f"{url}/pgn", headers=config['headers'])
            pgn = pgn.text
            break
        except json.decoder.JSONDecodeError:
            if counter > 10:
                raise ValueError('Errors persist after retrying GET request 10 times')
            else:
                print('ERROR FOUND: retrying request')
                time.sleep(5)
                counter += 1
    return pgn


def append_pgn_file(pgn_data, country_code):
    suffix = "TEST"
    with open(f"{pgn_path}/country-{country_code}/{country_code}_games-{suffix}.pgn", 'a+') as f:
        f.write(pgn_data)
        f.write('\n')


def execute():
    """
    - Loop through each user list file specified by the terminal (sys.argv[1])
    - Extract list of users from that file
    - Get the HTTP request strings for all available games for each user
    - Download the PGN games data using ThreadPoolExecutor and Requests
    - Append data to our newly created PGN file
    - Upload the PGN file to S3
    """
    # "Partition" the PGN files by country. Ex: US.pgn has ALL historic games played by users from the USA
    users_filelist = glob.glob(f"{users_json_path}/countries/AD.json")

    # Loop through each country
    for country_file in users_filelist[0:]:
        logging.info(f"Processing users from {country_file}")
        country_code = ntpath.basename(country_file)
        country_code = country_code.split(".")[0]
        # Create file directory if it does not already exist
        Path(f"{pgn_path}/country-{country_code}").mkdir(parents=True, exist_ok=True)
        # Get user list from country
        users = get_usernames_from_json(json_file=country_file)

        # TEMP - iterate over partial users list only
        # start_index = users.index("sanjit17")
        # users = users[start_index:]

        # Loop through each user in the country
        for user in users:
            archives = get_user_archives(user)

            if archives == "Null for this user":
                continue

            # Loop through the users monthly archives (so many loops!)
            # Use Threads to perform multiple requests concurrently
            futures_list = []
            with ThreadPoolExecutor(max_workers=30) as executor:
                for http_request in archives:
                    futures = executor.submit(get_user_monthly_pgns, http_request)
                    futures_list.append(futures)

                results = []
                for pgn in futures_list:
                    try:
                        result = pgn.result()
                        results.append(result)
                    except Exception:
                        results.append("")

            # Convert results to string for PGN-friendly format
            results = ''.join(results)
            # print(results)
            # Write data to PGN file as soon as the thread futures are ready
            append_pgn_file(pgn_data=results, country_code=country_code)


if __name__ == '__main__':
    execute()
