# NOTE: This is the latest PGN scraper script and is the main one I used
import requests
import yaml
import logging
import json
import time
import glob
import ntpath
import sys
import boto3
import os
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
s3_bucket = 'erops-chess'
s3_key = 'chesscom-db/by-country'
pgn_path = './chess-data/chesscom-db'
users_json_path = './ChessComCrawl/user_lists'


def get_usernames_from_json(json_file):
    """Returns list of all the usernames contained in the input json file"""
    with open(json_file) as f:
        data = json.load(f)
        users = data['players']
    return users


def get_user_archives(username):
    """Returns a list of HTTP request strings for all the games of the given user"""
    # Note: you need to specify the user agent str via the command line (ex: python3 pgn.py "USER_AGNT_STR")
    user_agent = {'user-agent': sys.argv[2]}
    url = f"https://api.chess.com/pub/player/{username}/games/archives"
    counter = 1
    logging.info("Performing GET request: {}".format(url))
    while True:
        try:
            archives_dict = requests.get(url, headers=user_agent).json()

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
    # Note: you need to specify the user agent str via the command line (ex: python3 pgn.py "USER_AGNT_STR")
    user_agent = {'user-agent': sys.argv[2]}
    url = http
    counter = 1
    while True:
        try:
            pgn = requests.get(f"{url}/pgn", headers=user_agent)
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


def append_pgn_file(pgn_data, filename):
    """Creates a PGN file and appends new games to the file"""
    file_to_write = f"{pgn_path}/{filename}"
    with open(file_to_write, 'a+') as f:
        f.write('\n')
        f.write(pgn_data)
        f.write('\n')


def divide_chunks(data, size):
    """This function is used to divide our PGN files into "chunks" (ex: at 10,000 users, then start new file)"""
    for i in range(0, len(data), size):
        yield data[i:i + size]


def copy_pgn_to_s3(filename, bucket, key):
    """Upload a given text file into S3"""
    # NOTE: AWS Access and Secret keys must be included as inputs when calling this script in the terminal
    file_to_load = f"{pgn_path}/{filename}"
    s3_file_path = f"{key}/{filename}"
    logging.info(f"Writing to S3: s3://{bucket}/{s3_file_path} ...............")
    s3 = boto3.resource(
        's3',
        region_name='us-west-2',
        aws_access_key_id=sys.argv[3],
        aws_secret_access_key=sys.argv[4]
    )
    s3.Bucket(bucket).upload_file(file_to_load, s3_file_path)


def execute():
    """
    - Loop through each user list file specified by the terminal (sys.argv[1])
    - Extract list of users from that file
    - Split into chunks of 10,000 users if the users file is large enough
    - Get the HTTP request strings for all available games for each user
    - Download the PGN games data using ThreadPoolExecutor and Requests
    - Append data to our newly created PGN file
    - Upload the PGN file to S3
    """
    # "Partition" the PGN files by country. Ex: "US-games-1.pgn" has ALL games played by the first 10000 users from USA
    # Note: you must specify which countries to process via the command line (ex: python3 pgn.py "countryies/A*.json"
    countries_select = sys.argv[1]
    users_filelist = glob.glob(f"{users_json_path}/{countries_select}")

    # Loop through each country
    for country_file in users_filelist[0:]:
        logging.info(f"Processing users from {country_file}")
        country_code = ntpath.basename(country_file)
        country_code = country_code.split(".")[0]
        # Create file directory if it does not already exist
        Path(f"{pgn_path}").mkdir(parents=True, exist_ok=True)
        # Get user list from country
        users = get_usernames_from_json(json_file=country_file)

        # TEMP - iterate over partial users list only
        # start_index = users.index("sanjit17")
        # users = users[1:]

        # Split into chunks of 10000 users
        chunks = divide_chunks(users, 10000)

        # Loop through each user in the country (in groups/chunks of 10000)
        for index, chunk in enumerate(chunks):
            logging.info(f"Processing users from country {country_code}, chunk {index}")
            filename = f"{country_code}-games-{index}.pgn"

            # Delete any old files so we don't accidently append to them
            if os.path.exists(f"{pgn_path}/{filename}"):
                os.remove(f"{pgn_path}/{filename}")

            # Loop though each user in this chunk
            for user in chunk:
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
                            results.append('')

                # Convert results to string for PGN-friendly format
                results = ''.join(results)
                # print(results)
                # Write data to PGN file as soon as the thread futures are ready
                append_pgn_file(pgn_data=results, filename=filename)

            # Write file to S3
            copy_pgn_to_s3(filename=filename, bucket=s3_bucket, key=s3_key)


if __name__ == '__main__':
    execute()
