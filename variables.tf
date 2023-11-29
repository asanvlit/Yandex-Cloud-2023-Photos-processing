variable "tgkey" {
  type        = string
  description = "Telegram Bot API Key"
}

variable "bot_name" {
  type        = string
  description = "Telegram bot name"
}

variable "cloud_id" {
  type        = string
  description = "Yandex cloud ID"
}

variable "cloud_sa_key" {
  type        = string
  description = "File with SA Yandex Cloud key"
}

variable "zone_name" {
  type        = string
  description = "Zone name"
}

variable "tags" {
  type        = list(string)
  description = "Tags"
  default     = ["my_tag"]
}

variable "mem" {
  type        = number
  description = "Function memory"
}

variable "sa_storage" {
  type        = string
  description = "Name of the service account for the storage"
}

variable "folder_id" {
  type        = string
  description = "Folder ID"
}

variable "photos_storage_bucket_name" {
  type        = string
  description = "Photos storage bucket name"
}

variable "faces_storage_bucket_name" {
  type        = string
  description = "Faces storage bucket name"
}

variable "photo_trigger_name" {
  type        = string
  description = "Photo trigger name"
}

variable "face_detection_func_name" {
  type        = string
  description = "Face detection function name"
}

variable "func_user_hash" {
  type        = string
  description = "User hash value"
}

variable "sa_face_detection" {
  type        = string
  description = "Name of the service account for the face detection"
}

variable "face_detection_func_zip" {
  type        = string
  description = "The name of the zip archive with the code of the face recognition function"
}

variable "face_detection_func_entrypoint" {
  type        = string
  description = "The entry point of the detection function code"
}

variable "face_cut_func_entrypoint" {
  type        = string
  description = "The entry point of the face cut function"
}

variable "face_detection_func_path" {
  type        = string
  description = "The path to the function code file"
}

variable "face_cut_func_zip" {
  type        = string
  description = "The name of the zip archive with the code of the face cut function"
}

variable "face_cut_func_path" {
  type        = string
  description = "The path to the face cut function code file"
}

variable "bot_func_path" {
  type        = string
  description = "The path to the bot function code file"
}

variable "bot_func_zip" {
  type        = string
  description = "The name of the zip archive with the code of the bot function"
}

variable "sa_vision" {
  type        = string
  description = "Name of the service account for the Yandex Vision"
}

variable "sa_task" {
  type        = string
  description = "Name of the service account for the tasks"
}

variable "queue_name" {
  type        = string
  description = "Name of the queue for the tasks"
}

variable "sa_container_runner" {
  type        = string
  description = "Name of the service account for running containers"
}

variable "face_cut_func_name" {
  type        = string
  description = "Name of the FaceCut container"
}

variable "face_cut_image_name" {
  type        = string
  description = "Name of the FaceCut image"
}

variable "task_trigger_name" {
  type        = string
  description = "Task trigger name"
}

variable "container_port" {
  type        = number
  description = "FaceCut container's port"
}

variable "api_gateway_name" {
  type = string
  description = "API Gateway name"
}

variable "sa_gateway" {
  type = string
  description = "Name of the service account for the API Gateway"
}

variable "db_name" {
  type = string
  description = "Name of the face photos Database"
}

variable "db_storage_size_limit" {
  type = number
  description = "Storage size limit (GB)"
}

variable "face_table_path" {
  type = string
  description = "Path of the Face table in Database"
}

variable "face_pk_column_name" {
  type = string
  description = "Name of the pk column in face table"
}

variable "face_id_column_name" {
  type = string
  description = "Name of the face id column in face table"
}

variable "face_original_id_column_name" {
  type = string
  description = "Name of the original photo id column in face table"
}

variable "face_person_name_column_name" {
  type = string
  description = "Name of the person's name column in face table"
}

variable "sa_ydb" {
  type = string
  description = "Name of the Service Account for YDB"
}

variable "sa_functions" {
  type        = string
  description = "Name of the service account for the functions"
}

variable "bot_func_name" {
  type        = string
  description = "Name of the bot function"
}

variable "bot_func_entrypoint" {
  type        = string
  description = "The entry point of the bot function"
}

variable "sa_terraform_admin" {
  type        = string
  description = "Name of the service account for the terraform admin"
}