import json
import os
import re

import requests as req

import ydb
import ydb.iam

TGKEY = os.getenv("TGKEY")
BOT_NAME = os.getenv("BOT_NAME")
JPG_EXTENSION = ".jpg"

ydb_driver: ydb.Driver


def get_driver():
    endpoint = f'grpcs://{os.environ["DATABASE_API_ENDPOINT"]}'
    path = os.environ['DATABASE_PATH']
    creds = ydb.iam.MetadataUrlCredentials()
    driver_config = ydb.DriverConfig(
        endpoint, path, credentials=creds
    )
    return ydb.Driver(driver_config)


def init_resources():
    global ydb_driver
    ydb_driver = get_driver()
    ydb_driver.wait(fail_fast=True, timeout=5)


def send_message(chat_id, text):
    url = 'https://api.telegram.org/bot' + TGKEY + '/' + 'sendMessage'
    data = {'chat_id': chat_id, 'text': text}
    r = req.post(url, data=data)


def send_photo(chat_id, photo, caption):
    url = 'https://api.telegram.org/bot' + TGKEY + '/' + 'sendPhoto'
    data = {'chat_id': chat_id, 'photo': photo, 'caption': caption}
    r = req.post(url, data=data)
    print(f"Request data: {data}")
    print("Try to send photo:")
    print(r.text)


def build_photo_url(source, face_id):
    url = f"https://{os.environ['API_GATEWAY_ID']}.apigw.yandexcloud.net/{source}/{face_id}"
    print(f"Photo's url: {url}")
    return url


def get_faces_without_names(chat_id):
    query = f"""
    SELECT * FROM {os.environ['FACE_TABLE_NAME']} WHERE {os.environ['FACE_PERSON_NAME_COLUMN_NAME']} is NULL LIMIT 1;
    """
    session = ydb_driver.table_client.session().create()
    result_sets = session.transaction().execute(query, commit_tx=True)
    session.closing()

    if len(result_sets[0].rows) == 0:
        send_message(chat_id, f"На данный момент все фотографии идентифицированы :)")
        return

    for row in result_sets[0].rows:
        face_id = row.face_id.decode("utf-8")
        print(f"Face without person name: {face_id}")
        send_photo(chat_id, build_photo_url("face", face_id), f'[{face_id}]\n\nКто изображен на данной фотографии?')


def is_face_recognition_answer(body):
    return ('reply_to_message' in body['message']) and \
           (body['message']['reply_to_message']['from']['username']) == BOT_NAME and \
           ('photo' in body['message']['reply_to_message']) and \
           ('caption' in body['message']['reply_to_message'])


def process_face_recognition_answer(chat_id, request):
    photo_caption = request['message']['reply_to_message']['caption']

    match = re.search(r'\[(.*?)\]', photo_caption)
    if match:
        face_id = match.group(1)
    else:
        send_message(chat_id, "Возникла ошибка в процессе записи данных")
        return

    person_name = request['message']['text']

    print(f"face_id: {face_id}")
    print(f"person_name: {person_name}")

    query = f"""
        SELECT * FROM {os.environ['FACE_TABLE_NAME']} WHERE {os.environ['FACE_FACE_ID_COLUMN_NAME']} = '{face_id}';
    """
    session = ydb_driver.table_client.session().create()
    result_sets = session.transaction().execute(query, commit_tx=True)
    session.closing()

    original_photo_id = ''
    for row in result_sets[0].rows:
        original_photo_id = row.original_photo_id.decode("utf-8")
    if original_photo_id == '':
        return

    query = f"""
        UPDATE {os.environ['FACE_TABLE_NAME']} SET 
        {os.environ['FACE_PERSON_NAME_COLUMN_NAME']} = '{person_name}',
        {os.environ['FACE_FACE_ID_COLUMN_NAME']} = '{face_id}',
        {os.environ['FACE_ORIGINAL_ID_COLUMN_NAME']} = '{original_photo_id}'
        WHERE {os.environ['FACE_FACE_ID_COLUMN_NAME']} = '{face_id}';
        """
    print(f"Attempt to execute query: {query}")
    session.transaction().execute(query, commit_tx=True)
    session.closing()

    send_message(chat_id, "Спасибо! Данные успешно обновлены")


def find_person_photos_by_name(chat_id, person_name):
    query = f"""
        SELECT DISTINCT {os.environ['FACE_ORIGINAL_ID_COLUMN_NAME']}, {os.environ['FACE_PERSON_NAME_COLUMN_NAME']}
         FROM {os.environ['FACE_TABLE_NAME']} WHERE {os.environ['FACE_PERSON_NAME_COLUMN_NAME']} = '{person_name}';
    """
    session = ydb_driver.table_client.session().create()
    result_sets = session.transaction().execute(query, commit_tx=True)
    session.closing()

    if len(result_sets[0].rows) == 0:
        send_message(chat_id, f"Фотографии с {person_name} не найдены")
        return

    for row in result_sets[0].rows:
        original_photo_id = row.original_photo_id.decode("utf-8")
        photo_url = build_photo_url("photo", original_photo_id)
        send_photo(chat_id=chat_id, photo=photo_url, caption="")


def handler(event, context):
    init_resources()

    request = json.loads(event['body'])

    print(f"Received request: {request}")
    chat_id = request['message']['from']['id']

    message = request["message"]

    if "text" in message:
        command = request['message']['text']

        print(f"Chat id: {chat_id}\n")
        print(f"Received command: {command}\n")

        if command == '/getface':
            get_faces_without_names(chat_id)
        elif command.startswith('/find'):
            args = command.split(' ')
            if len(args) < 2:
                send_message(chat_id, 'Неверная команда. Формат команды find: /find {имя}')
            else:
                find_person_photos_by_name(chat_id, args[1])
        elif is_face_recognition_answer(request):
            process_face_recognition_answer(chat_id, request)
        else:
            send_message(chat_id, 'Ошибка')
    else:
        send_message(chat_id, 'Ошибка')

    return {
        'statusCode': 200,
    }
