import requests
import yaml
import logging
import json
import time
import pandas as pd
from pathlib import Path

logging.getLogger().setLevel(logging.INFO)

json_path = './ChessComCrawl/user_lists'

with open('./ChessComCrawl/config.yml') as config_file:
    config = yaml.safe_load(config_file)


def get_users(country_code):
    """Return JSON metadata containing all active users from the specified country"""
    url = f"https://api.chess.com/pub/country/{country_code}/players"
    counter = 0
    logging.info("Performing GET request: {}".format(url))
    while True:
        try:
            json_data = requests.get(url, headers=config['headers']).json()
            break
        except json.decoder.JSONDecodeError:
            if counter > 10:
                raise ValueError('Errors persist after retrying GET request 10 times')
            else:
                logging.info('ERROR FOUND: retrying request')
                time.sleep(5)
                counter += 1
    return json_data


def write_json(json_data, country_code):
    """Write the JSON metadata from get_users() to a JSON file"""
    # Create file directory if it does not already exist
    Path(f"{json_path}/{search_term}/country-{country_code}").mkdir(parents=True, exist_ok=True)
    with open(f"{json_path}/countries/{country_code}.json", 'w') as json_file:
        # for result in json_data:
        json_file.write(json.dumps(json_data, ensure_ascii=False))
    logging.info(f"file {country_code} written")


def execute():
    """
    - Loop through each country code in config.yml
    - Extract JSON data of all active users from that country, and save to JSON file
    """
    # Write JSON files for each country. Ex: US.json lists ALL recently active users from the USA
    for country_code in config['countries']:
        json_data = get_users(country_code=country_code)
        write_json(json_data=json_data, country_code=country_code)


if __name__ == '__main__':
    execute()
