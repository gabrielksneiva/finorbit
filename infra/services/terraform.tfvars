##############################################
# /services/terraform.tfvars
# Valores padrão para ambiente de desenvolvimento
##############################################

env                = "dev"
region             = "us-east-1"

# Tags das imagens (substituídas no CI/CD)
producer_image_tag = "latest"
consumer_image_tag = "latest"

# Configurações padrão
lambda_memory  = 256
lambda_timeout = 10
