terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = var.cloud_sa_key
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  zone                     = var.zone_name
}

resource "archive_file" "face-detection-zip" {
  output_path = var.face_detection_func_zip
  type        = "zip"
  source_dir  = var.face_detection_func_path
}

resource "archive_file" "face-cut-zip" {
  output_path = var.face_cut_func_zip
  type        = "zip"
  source_dir  = var.face_cut_func_path
}

resource "archive_file" "boot-zip" {
  output_path = var.bot_func_zip
  type        = "zip"
  source_dir  = var.bot_func_path
}

output "bot_id" {
  value = yandex_function.bot.id
}

data "http" "webhook" {
  url = "https://api.telegram.org/bot${var.tgkey}/setWebhook?url=https://functions.yandexcloud.net/${yandex_function.bot.id}"
}

resource "yandex_iam_service_account" "sa-storage" {
  name = var.sa_storage
}

resource "yandex_resourcemanager_folder_iam_member" "sa-editor" {
  folder_id = var.folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa-storage.id}"
}

resource "yandex_iam_service_account_static_access_key" "sa-storage-static-key" {
  service_account_id = yandex_iam_service_account.sa-storage.id
  description        = "static access key for object storage"
}

resource "yandex_storage_bucket" "photos-storage-bucket" {
  access_key = yandex_iam_service_account_static_access_key.sa-storage-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-storage-static-key.secret_key
  bucket     = var.photos_storage_bucket_name

  depends_on = [
    yandex_iam_service_account.sa-storage
  ]
}

resource "yandex_storage_bucket" "faces-storage-bucket" {
  access_key = yandex_iam_service_account_static_access_key.sa-storage-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-storage-static-key.secret_key
  bucket     = var.faces_storage_bucket_name

  depends_on = [
    yandex_iam_service_account.sa-storage
  ]
}

resource "yandex_iam_service_account" "sa-face-detection" {
  name = var.sa_face_detection
}

resource "yandex_resourcemanager_folder_iam_member" "sa-face-detection-invoker" {
  folder_id = var.folder_id
  role      = "serverless.functions.admin"
  member    = "serviceAccount:${yandex_iam_service_account.sa-face-detection.id}"
}

resource "yandex_iam_service_account" "sa-vision" {
  name = var.sa_vision
}

resource "yandex_resourcemanager_folder_iam_member" "sa-vision" {
  folder_id = var.folder_id
  role      = "ai.vision.user"
  member    = "serviceAccount:${yandex_iam_service_account.sa-vision.id}"
}

resource "yandex_iam_service_account_api_key" "sa-vision-api-key" {
  service_account_id = yandex_iam_service_account.sa-vision.id
  description        = "Yandex Vision Service account's API key"
}

resource "yandex_function" "face_detection" {
  name               = var.face_detection_func_name
  description        = "Face detection function"
  user_hash          = var.func_user_hash
  runtime            = "python311"
  entrypoint         = var.face_detection_func_entrypoint
  memory             = var.mem
  execution_timeout  = "10"
  service_account_id = yandex_iam_service_account.sa-face-detection.id
  tags               = var.tags
  content {
    zip_filename = archive_file.face-detection-zip.output_path
  }
  environment = {
    TGKEY                    = var.tgkey
    AWS_ACCESS_KEY_ID        = yandex_iam_service_account_static_access_key.sa-storage-static-key.access_key
    AWS_SECRET_ACCESS_KEY_ID = yandex_iam_service_account_static_access_key.sa-storage-static-key.secret_key
    VISION_API_KEY           = yandex_iam_service_account_api_key.sa-vision-api-key.secret_key
    QUEUE_NAME               = var.queue_name
  }

  depends_on = [
    yandex_iam_service_account.sa-face-detection,
    yandex_iam_service_account.sa-storage,
    yandex_iam_service_account.sa-vision,
    archive_file.face-detection-zip,
    yandex_message_queue.task_queue
  ]
}

resource "yandex_function_trigger" "photo-trigger" {
  name        = var.photo_trigger_name
  description = "Launches a handler with face recognition"
  object_storage {
    bucket_id    = yandex_storage_bucket.photos-storage-bucket.id
    create       = true
    update       = true
    suffix       = "jpg"
    batch_cutoff = 30
  }
  function {
    id                 = yandex_function.face_detection.id
    service_account_id = yandex_iam_service_account.sa-face-detection.id
  }

  depends_on = [
    yandex_storage_bucket.photos-storage-bucket,
    yandex_function.face_detection,
    yandex_iam_service_account.sa-face-detection
  ]
}

resource "yandex_iam_service_account" "sa-task" {
  name = var.sa_task
}

resource "yandex_resourcemanager_folder_iam_member" "sa-task-editor" {
  folder_id = var.folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa-task.id}"
}

resource "yandex_iam_service_account_static_access_key" "sa-task-static-key" {
  service_account_id = yandex_iam_service_account.sa-task.id
  description        = "Static access key for task Service account"
}

resource "yandex_message_queue" "task_queue" {
  name       = var.queue_name
  access_key = yandex_iam_service_account_static_access_key.sa-task-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-task-static-key.secret_key

  depends_on = [
    yandex_iam_service_account.sa-task
  ]
}

resource "yandex_function" "face_cut" {
  name               = var.face_cut_func_name
  description        = "Face cut function"
  user_hash          = var.func_user_hash
  runtime            = "python311"
  entrypoint         = var.face_cut_func_entrypoint
  memory             = var.mem
  execution_timeout  = "10"
  service_account_id = yandex_iam_service_account.sa-ydb.id
  tags               = var.tags
  content {
    zip_filename = archive_file.face-cut-zip.output_path
  }
  environment = {
    PHOTOS_STORAGE_BUCKET        = var.photos_storage_bucket_name
    FACES_STORAGE_BUCKET         = var.faces_storage_bucket_name
    AWS_ACCESS_KEY_ID            = yandex_iam_service_account_static_access_key.sa-storage-static-key.access_key
    AWS_SECRET_ACCESS_KEY_ID     = yandex_iam_service_account_static_access_key.sa-storage-static-key.secret_key
    ACCESS_TOKEN_FOR_YDB         = yandex_iam_service_account_static_access_key.sa-ydb-static-key.access_key
    SECRET_TOKEN_FOR_YDB         = yandex_iam_service_account_static_access_key.sa-ydb-static-key.secret_key
    DATABASE_NAME                = var.db_name
    DATABASE_ENDPOINT            = yandex_ydb_database_serverless.my-database.ydb_full_endpoint
    DATABASE_API_ENDPOINT        = yandex_ydb_database_serverless.my-database.ydb_api_endpoint
    DATABASE_PATH                = yandex_ydb_database_serverless.my-database.database_path
    FACE_TABLE_NAME              = var.face_table_path
    FACE_PK_COLUMN_NAME          = var.face_pk_column_name
    FACE_FACE_ID_COLUMN_NAME     = var.face_id_column_name
    FACE_ORIGINAL_ID_COLUMN_NAME = var.face_original_id_column_name
    CONTAINER_PORT               = var.container_port
  }

  depends_on = [
    yandex_iam_service_account.sa-ydb,
    yandex_iam_service_account.sa-storage,
    yandex_ydb_database_serverless.my-database,
    archive_file.face-cut-zip,
  ]
}

resource "yandex_iam_service_account" "sa-functions" {
  name = var.sa_functions
}

resource "yandex_resourcemanager_folder_iam_member" "sa-functions-admin" {
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.sa-functions.id}"
  role      = "serverless.functions.admin"
}

resource "yandex_iam_service_account" "sa-terraform-admin" {
  name = var.sa_terraform_admin
}

resource "yandex_resourcemanager_folder_iam_member" "sa-terraform-functions-admin" {
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.sa-terraform-admin.id}"
  role      = "serverless.functions.admin"
}

resource "yandex_resourcemanager_folder_iam_member" "sa-terraform-ydb-editor" {
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.sa-terraform-admin.id}"
  role      = "ydb.editor"
}

resource "yandex_function_trigger" "my_trigger" {
  name        = var.task_trigger_name
  description = "Receives messages from the queue and pass them to the handler"
  message_queue {
    queue_id           = yandex_message_queue.task_queue.arn
    service_account_id = yandex_iam_service_account.sa-storage.id
    batch_size         = "1"
    batch_cutoff       = "1"
  }
  function {
    id                 = yandex_function.face_cut.id
    service_account_id = yandex_iam_service_account.sa-functions.id
  }

  depends_on = [
    yandex_message_queue.task_queue,
    yandex_iam_service_account.sa-storage,
    yandex_iam_service_account.sa-functions,
    yandex_function.face_cut
  ]
}

resource "yandex_iam_service_account" "sa-gateway" {
  name = var.sa_gateway
}

resource "yandex_resourcemanager_folder_iam_member" "sa-gateway-viewer" {
  member    = "serviceAccount:${yandex_iam_service_account.sa-gateway.id}"
  role      = "storage.viewer"
  folder_id = var.folder_id
}

resource "yandex_api_gateway" "my-api-gateway" {
  name        = var.api_gateway_name
  description = "Used to get photos of faces"
  spec        = <<-EOT
openapi: 3.0.0
info:
  title: HW 1. API
  version: 1.0.0
paths:
  /face/{key}:
   get:
      parameters:
       - name: key
         in: path
         description: Face key in object storage
         required: true
         schema:
           type: string
      x-yc-apigateway-integration:
       type: object_storage
       object: '{key}'
       bucket: ${yandex_storage_bucket.faces-storage-bucket.id}
       service_account_id: ${yandex_iam_service_account.sa-gateway.id}
  /photo/{key}:
   get:
      parameters:
       - name: key
         in: path
         description: Photo key in object storage
         required: true
         schema:
           type: string
      x-yc-apigateway-integration:
       type: object_storage
       object: '{key}'
       bucket: ${yandex_storage_bucket.photos-storage-bucket.id}
       service_account_id: ${yandex_iam_service_account.sa-gateway.id}
EOT
  depends_on = [
    yandex_storage_bucket.faces-storage-bucket,
    yandex_storage_bucket.photos-storage-bucket
  ]
}

resource "yandex_iam_service_account" "sa-ydb" {
  name = var.sa_ydb
}

resource "yandex_resourcemanager_folder_iam_binding" "ydb_editor" {
  folder_id = var.folder_id
  role      = "ydb.editor"
  members   = [
    "serviceAccount:${yandex_iam_service_account.sa-ydb.id}"
  ]
}

resource "yandex_iam_service_account_static_access_key" "sa-ydb-static-key" {
  service_account_id = yandex_iam_service_account.sa-ydb.id
  description        = "static access key for ydb"
}

resource "yandex_ydb_database_serverless" "my-database" {
  name                = var.db_name
  deletion_protection = false

  serverless_database {
    storage_size_limit = var.db_storage_size_limit
  }
}

resource "yandex_ydb_table" "test_table" {
  path              = var.face_table_path
  connection_string = yandex_ydb_database_serverless.my-database.ydb_full_endpoint

  column {
    name     = var.face_pk_column_name
    type     = "String"
    not_null = true
  }
  column {
    name     = var.face_id_column_name
    type     = "String"
    not_null = true
  }
  column {
    name     = var.face_original_id_column_name
    type     = "String"
    not_null = true
  }
  column {
    name     = var.face_person_name_column_name
    type     = "String"
    not_null = false
  }

  primary_key = [var.face_pk_column_name]
}

resource "yandex_function" "bot" {
  name               = var.bot_func_name
  description        = "Handler for the bot"
  user_hash          = var.func_user_hash
  runtime            = "python311"
  entrypoint         = var.bot_func_entrypoint
  memory             = var.mem
  execution_timeout  = "10"
  service_account_id = yandex_iam_service_account.sa-terraform-admin.id
  tags               = var.tags
  content {
    zip_filename = archive_file.boot-zip.output_path
  }
  environment = {
    TGKEY                        = var.tgkey
    BOT_NAME                     = var.bot_name
    DATABASE_API_ENDPOINT        = yandex_ydb_database_serverless.my-database.ydb_api_endpoint
    DATABASE_PATH                = yandex_ydb_database_serverless.my-database.database_path
    FACE_TABLE_NAME              = var.face_table_path
    FACE_PK_COLUMN_NAME          = var.face_pk_column_name
    FACE_FACE_ID_COLUMN_NAME     = var.face_id_column_name
    FACE_ORIGINAL_ID_COLUMN_NAME = var.face_original_id_column_name
    FACE_PERSON_NAME_COLUMN_NAME = var.face_person_name_column_name
    API_GATEWAY_ID               = yandex_api_gateway.my-api-gateway.id
  }

  depends_on = [
    yandex_iam_service_account.sa-terraform-admin,
    yandex_ydb_database_serverless.my-database,
    yandex_api_gateway.my-api-gateway
  ]
}

resource "yandex_function_iam_binding" "bot-iam" {
  function_id = yandex_function.bot.id
  role        = "serverless.functions.invoker"

  members = [
    "system:allUsers",
  ]
}
