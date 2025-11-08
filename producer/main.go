package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"github.com/pborman/uuid"
	"github.com/shopspring/decimal"
)

// ===============================
// Interface SNS para mock nos testes
// ===============================
type SNSClient interface {
	Publish(ctx context.Context, input *sns.PublishInput, optFns ...func(*sns.Options)) (*sns.PublishOutput, error)
}

var snsClient SNSClient

// ===============================
// Estruturas
// ===============================
type TransactionRequest struct {
	Amount string `json:"amount"`
	Type   string `json:"type"`
}

type TransactionEvent struct {
	UserID    string          `json:"user_id"`
	Amount    decimal.Decimal `json:"amount"`
	Type      string          `json:"type"`
	Timestamp string          `json:"timestamp"`
}

// ===============================
// Handler da Lambda
// ===============================
func handler(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	log.Println("🚀 FinOrbit Producer invocado!")

	// Verifica método HTTP
	if req.RequestContext.HTTP.Method != http.MethodPost {
		return events.APIGatewayV2HTTPResponse{
			StatusCode: http.StatusMethodNotAllowed,
			Body:       "Método não permitido",
		}, nil
	}

	// Decodifica corpo JSON
	var txReq TransactionRequest
	if err := json.Unmarshal([]byte(req.Body), &txReq); err != nil {
		log.Printf("❌ Erro ao decodificar corpo da requisição: %v", err)
		return events.APIGatewayV2HTTPResponse{StatusCode: 400, Body: "JSON inválido"}, nil
	}

	// Converte valor
	convertedAmount, err := decimal.NewFromString(txReq.Amount)
	if err != nil {
		log.Printf("❌ Erro ao converter valor: %v", err)
		return events.APIGatewayV2HTTPResponse{StatusCode: 400, Body: "Valor inválido"}, nil
	}

	// Valida campos
	if convertedAmount.LessThanOrEqual(decimal.Zero) || (txReq.Type != "deposit" && txReq.Type != "withdraw") {
		return events.APIGatewayV2HTTPResponse{StatusCode: 400, Body: "Campos inválidos"}, nil
	}

	// Cria evento
	event := TransactionEvent{
		UserID:    uuid.NewUUID().String(),
		Amount:    convertedAmount,
		Type:      txReq.Type,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}

	// Publica no SNS
	topicARN := os.Getenv("SNS_TOPIC_ARN")
	if topicARN == "" {
		return events.APIGatewayV2HTTPResponse{StatusCode: 500, Body: "Variável SNS_TOPIC_ARN não configurada"}, nil
	}

	data, _ := json.Marshal(event)
	_, err = snsClient.Publish(ctx, &sns.PublishInput{
		TopicArn: aws.String(topicARN),
		Message:  aws.String(string(data)),
	})
	if err != nil {
		log.Printf("❌ Erro ao publicar no SNS: %v", err)
		return events.APIGatewayV2HTTPResponse{StatusCode: 500, Body: "Erro ao publicar mensagem"}, nil
	}

	log.Printf("✅ Evento publicado no SNS: %v", string(data))
	return events.APIGatewayV2HTTPResponse{
		StatusCode: 200,
		Body:       fmt.Sprintf("Transação enviada para processamento: %s", txReq.Type),
	}, nil
}

// ===============================
// Função main
// ===============================
func main() {
	// Carrega configuração AWS
	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		log.Fatalf("❌ Erro ao carregar configuração AWS: %v", err)
	}

	// Inicializa client SNS real
	snsClient = sns.NewFromConfig(cfg)

	// Inicia Lambda
	lambda.Start(handler)
}
