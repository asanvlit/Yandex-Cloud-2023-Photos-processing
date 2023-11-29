import json
import requests as req
import base64
import os
import boto3


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


def build_face_detection_body(content):
    return {
        "analyze_specs": [{
            "content": content,
            "features": [{
                "type": "FACE_DETECTION"
            }]
        }]
    }


def get_detected_faces(source_img):
    encoded = base64.b64encode(source_img).decode('UTF-8')
    api_key = os.environ['VISION_API_KEY']
    auth_header = {'Authorization': f'Api-Key {api_key}'}
    body = build_face_detection_body(encoded)

    resp = req.post("https://vision.api.cloud.yandex.net/vision/v1/batchAnalyze", json=body, headers=auth_header)

    coordinates = []
    try:
        faces = resp.json()['results'][0]['results'][0]['faceDetection']['faces']
        for face in faces:
            coordinates.append(face['boundingBox']['vertices'])
    except KeyError:
        print(f'Failed to detect faces: {resp.json()}')
        return []
    print(f'Number of faces detected in photo: {len(coordinates)}')

    return coordinates


def build_queue_message(object_id, face):
    return {
        'object_id': object_id,
        'face': face
    }


def create_queue_tasks(object_id, faces):
    access_key = os.environ['AWS_ACCESS_KEY_ID']
    secret_key = os.environ['AWS_SECRET_ACCESS_KEY_ID']

    sqs = boto3.resource(
        service_name='sqs',
        endpoint_url='https://message-queue.api.cloud.yandex.net',
        region_name='ru-central1',
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
    )

    messages = [build_queue_message(object_id, face) for face in faces]
    for message in messages:
        body = json.dumps(message)
        queue_name = os.environ['QUEUE_NAME']
        print(f'Queue: {queue_name}\n')
        print(f'Try to send: {body}\n')
        sqs.get_queue_by_name(QueueName=queue_name).send_message(MessageBody=body)


def handler(event, context):
    data = event['messages'][0]
    bucket_id = data['details']['bucket_id']
    object_id = data['details']['object_id']

    file = download_bucket_file(object_id, bucket_id)
    if len(file) > 1048576:  # 1 MB in bytes
        print("Размер объекта с фотоизображением не должен превышать одного мегабайта")
        return

    detected_faces = get_detected_faces(file)

    create_queue_tasks(object_id, detected_faces)
