variable "env" {
  type    = string
  default = "dev"
}

variable "create_rds" {
  type    = bool
  default = true
}

# 🔹 Essas variáveis permitem CI/CD atualizar imagem sem recriar Lambda
variable "consumer_image_tag" {
  type    = string
  default = "latest"
}

variable "producer_image_tag" {
  type    = string
  default = "latest"
}

variable "region" {
  type    = string
  default = "us-east-1"
}