# FinOrbit 🚀

[![Go](https://img.shields.io/badge/go-1.25-blue)]() [![Terraform](https://img.shields.io/badge/terraform-1.9.7-623CE4)]() [![CI/CD](https://img.shields.io/badge/GitHub_Actions-enabled-2088FF)]()

FinOrbit é uma aplicação serverless para processamento de transações financeiras em tempo real. O objetivo deste repositório é fornecer uma referência prática com infraestrutura como código (Terraform), pipelines CI/CD (GitHub Actions) e Lambdas empacotadas como imagens no ECR.

## Sumário
- [Visão Geral](#visão-geral)
- [Arquitetura](#arquitetura)
- [Recursos](#recursos)
- [Pré‑requisitos](#pré-requisitos)
- [Como rodar localmente](#como-rodar-localmente)
- [Build e push (ECR)](#build-e-push-ecr)
- [Provisionamento (Terraform)](#provisionamento-terraform)
- [Exemplo de requisição](#exemplo-de-requisição)
- [CI/CD](#cicd)
- [Segurança e recomendações para produção](#segurança-e-recomendações-para-produção)
- [Resolução de problemas comuns](#resolução-de-problemas-comuns)
- [Contribuição](#contribuição)
- [Licença](#licença)

## Visão Geral
Componentes principais:
- Producer — Lambda que expõe a API HTTP (POST /transaction), valida o payload e publica eventos no SNS.
- Consumer — Lambda que consome mensagens da fila SQS (assinada pelo SNS) e persiste transações em um RDS PostgreSQL.

O fluxo de dados é: API Gateway → Lambda (producer) → SNS → SQS → Lambda (consumer) → RDS (Postgres).

## Arquitetura
- API Gateway (HTTP) para entrada de requests.
- Producer empacotado como imagem Docker no ECR.
- SNS topic para broadcast de eventos.
- SQS queue assinada ao SNS para entrega confiável.
- Consumer (Lambda) processa cada mensagem e grava no RDS.
- RDS PostgreSQL para persistência.

## Recursos
- Endpoint: POST /transaction
- Validação de payload: amount (numérico), type (string — ex: `deposit`, `withdrawal`)
- Mensageria: SNS → SQS
- Persistência: PostgreSQL (RDS)
- Infraestrutura: Terraform
- CI/CD: GitHub Actions (build, test, push para ECR, terraform apply)

## Pré‑requisitos
- Go 1.25
- Docker
- Terraform 1.9.x
- AWS CLI configurado
- (Opcional) jq para scripts

Secrets esperados no GitHub Actions:
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ACCOUNT_ID`

## Como rodar localmente
Os serviços AWS (SNS/SQS/RDS) não são emulados por padrão. Rode unit/integration tests localmente e, quando necessário, use uma conta de dev na AWS.

Consumer
```bash
cd consumer
go mod tidy
go test ./...
go run main.go
```

Producer
```bash
cd producer
go mod tidy
go test ./...
go run main.go
```

## Build e push (ECR)
Use este fluxo para criar, taggear e pushar a imagem para o ECR. Substitua `REGION` e `REPO` conforme necessário.

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REPO=finorbit-producer

# login no ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# build + tag
docker build -t $REPO:latest ./producer
docker tag $REPO:latest $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:latest

# push
docker push $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:latest
```

Dica: o erro `invalid reference format` geralmente indica que `$AWS_ACCOUNT_ID` está vazio — valide antes de taggear/pushar.

## Provisionamento (Terraform)
```bash
cd terraform
terraform init
terraform plan -out plan.tfplan
terraform apply plan.tfplan
```

Após o `apply`, obtenha a URL da API:
```bash
terraform output -raw api_url
```

Recomendações de produção:
- Não deixe o RDS publicamente acessível. Coloque-o em subnets privadas.
- Armazene credenciais em Secrets Manager ou Parameter Store.

## Exemplo de requisição
Exemplo seguro usando a saída do Terraform:

```bash
API_URL=$(terraform output -raw api_url)
curl -sS -X POST "$API_URL" \
	-H "Content-Type: application/json" \
	-d '{"amount":150.50,"type":"deposit"}'
```

JSON de exemplo
```json
{
	"amount": 150.50,
	"type": "deposit"
}
```

Validações esperadas:
- `amount` — número positivo
- `type` — string permitida (por exemplo, `deposit` ou `withdrawal`)

## CI/CD
O pipeline previsto (ex.: `.github/workflows/ci-cd.yaml`) realiza:
1. Setup do ambiente Go
2. Formatação/lint (go fmt)
3. Testes com relatório de coverage (mínimo 70%)
4. Build e push das imagens para ECR
5. Terraform (plan/apply) — normalmente controlado por ambientes (staging/prod)

## Segurança e recomendações para produção
- Use IAM roles com princípio de privilégio mínimo.
- Não versionar segredos no repositório.
- Habilitar backups automáticos do RDS e lifecycle de snapshots.
- Restrinja Security Groups e não use `0.0.0.0/0` em produção.

## Resolução de problemas comuns
- invalid reference format (Docker/ECR): verifique `$AWS_ACCOUNT_ID` antes da tag/push.
- Permissões ECR/Lambda: verifique se a role Lambda tem `AmazonEC2ContainerRegistryReadOnly`.
- SNS→SQS: confira a política da fila e a condição `aws:SourceArn`.

## Contribuição
- Abra issues para bugs/feature requests.
- Envie PRs com testes e mantenha o padrão de formatação (go fmt).

## Licença
Licenciado sob MIT — veja o arquivo `LICENSE`.

---

> Documentação gerada para facilitar desenvolvimento, CI/CD e deployment. Atualize conforme o projeto evolui.
