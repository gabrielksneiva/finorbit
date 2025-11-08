# Etapa 1 - build da aplicação Go
FROM golang:1.25 as builder

# Cria diretório de trabalho
WORKDIR /app

# Copia os arquivos
COPY go.mod ./
COPY go.sum ./
RUN go mod download

COPY . .

# Compila o binário para Linux (Lambda)
RUN GOOS=linux GOARCH=amd64 go build -o bootstrap main.go


# Etapa 2 - imagem final mínima (Amazon Linux 2023)
FROM public.ecr.aws/lambda/provided:al2023

# Copia o binário para dentro da imagem final
COPY --from=builder /app/bootstrap /var/runtime/bootstrap

# Define o comando padrão
CMD [ "bootstrap" ]
