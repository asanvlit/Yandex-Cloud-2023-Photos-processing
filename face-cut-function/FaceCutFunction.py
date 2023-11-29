import io
import json
import os
import uuid

import boto3
from PIL import Image

import ydb
import ydb.iam

JPG_EXTENSION = ".jpg"

ydb_driver: ydb.Driver


def download_bucket_file(file_id, bucket_id):
    access_key = os.environ['AWS_ACCESS_KEY_ID']
    secret_key = os.environ['AWS_SECRET_ACCESS_KEY_ID']

    session = boto3.session.Session()
    s3 = session.client(
        service_name='s3',
        endpoint_url='https://storage.yandexcloud.net',
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
    )

    print(f"Attempt to download a file {file_id} from {bucket_id} bucket")
    file_response = s3.get_object(
        Bucket=bucket_id,
        Key=file_id
    )
    print(f"File {file_id} downloaded successfully")

    return file_response['Body'].read()


def upload_file_to_bucket(file_name, bucket_id, content):
    access_key = os.environ['AWS_ACCESS_KEY_ID']
    secret_key = os.environ['AWS_SECRET_ACCESS_KEY_ID']

    session = boto3.session.Session()
    s3 = session.client(
        service_name='s3',
        endpoint_url='https://storage.yandexcloud.net',
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
    )
    s3.put_object(
        Body=content,
        Bucket=bucket_id,
        Key=file_name,
        ContentType='application/octet-stream'
    )


def add_image_info_to_db(face_id, original_photo_id):
    q = f"""
    INSERT INTO {os.environ['FACE_TABLE_NAME']} ({os.environ['FACE_PK_COLUMN_NAME']}, 
    {os.environ['FACE_FACE_ID_COLUMN_NAME']}, {os.environ['FACE_ORIGINAL_ID_COLUMN_NAME']})
    VALUES ("{str(uuid.uuid4())}", "{str(face_id)}", "{str(original_photo_id)}");
    """
    print(f"Attempt to execute query: {q}")

    session = ydb_driver.table_client.session().create()
    session.transaction().execute(q, commit_tx=True)
    session.closing()


def generate_face_id():
    face_idx = str(uuid.uuid4())
    return f"{face_idx}{JPG_EXTENSION}"


def extract_coordinates(coordinates):
    x = set()
    y = set()
    for c in coordinates:
        x.add(int(c['x']))
        y.add(int(c['y']))
    return x, y


def calculate_face_boundaries(x, y):
    x_sorted = sorted(x)
    y_sorted = sorted(y)

    left = x_sorted[0]
    right = x_sorted[1]
    top = y_sorted[0]
    bottom = y_sorted[1]

    return left, right, top, bottom


def process_message(message):
    body = json.loads(message['details']['message']['body'])

    image = Image.open(io.BytesIO(download_bucket_file(body['object_id'], os.environ['PHOTOS_STORAGE_BUCKET'])))

    face_coordinates = body['face']

    x, y = extract_coordinates(face_coordinates)
    left, right, top, bottom = calculate_face_boundaries(x, y)

    face_id = generate_face_id()

    cut_face = image.crop((left, top, right, bottom))
    img_data = io.BytesIO()
    cut_face.save(img_data, format='JPEG')

    upload_file_to_bucket(face_id, os.environ['FACES_STORAGE_BUCKET'], img_data.getvalue())

    add_image_info_to_db(face_id, body['object_id'])


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


def handler(event, context):
    init_resources()

    messages = event['messages']
    print(f"Received request: {messages}")

    for message in messages:
        try:
            process_message(message)
        except Exception as e:
            print(f'Error occurred during message processing: {e}\n')
    print(f"Messages processed: {len(messages)}")
