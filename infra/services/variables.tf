##############################################
# /services/variables.tf
# Define variáveis de ambiente, tags de imagem e região
##############################################

variable "env" {
  description = "Ambiente de deploy (ex: dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Região AWS onde os serviços estão sendo implantados"
  type        = string
  default     = "us-east-1"
}

variable "producer_image_tag" {
  description = "Tag da imagem do Producer no ECR (ex: latest, v1.0.0)"
  type        = string
}

variable "consumer_image_tag" {
  description = "Tag da imagem do Consumer no ECR (ex: latest, v1.0.0)"
  type        = string
}

##############################################
# Extras opcionais
##############################################

variable "lambda_memory" {
  description = "Memória em MB atribuída às Lambdas"
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Timeout (segundos) das Lambdas"
  type        = number
  default     = 10
}
