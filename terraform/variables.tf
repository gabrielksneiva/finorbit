# =======================
# 🌎 Variável da Região
# =======================
variable "region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-1"
}

# =======================
# 🧠 Variáveis do Projeto
# =======================
variable "project_name" {
  description = "Nome base do projeto, usado em nomes de recursos"
  type        = string
  default     = "finorbit"
}

# =======================
# 🔐 Variáveis de Identificação
# =======================
variable "environment" {
  description = "Ambiente (ex: dev, staging, prod)"
  type        = string
  default     = "dev"
}

# =======================
# 🪣 ECR (opcional, caso queira personalizar nomes)
# =======================
variable "ecr_consumer_repo" {
  description = "Nome do repositório ECR para a Lambda consumer"
  type        = string
  default     = "finorbit-consumer"
}

variable "ecr_producer_repo" {
  description = "Nome do repositório ECR para a Lambda producer"
  type        = string
  default     = "finorbit-producer"
}
