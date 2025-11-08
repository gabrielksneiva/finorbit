package main

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/service/sns"
)

// ------------------------
// 1️⃣ Método inválido
// ------------------------
func TestInvalidMethod(t *testing.T) {
	req := events.APIGatewayV2HTTPRequest{
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "GET",
			},
		},
	}

	resp, _ := handler(context.Background(), req)
	if resp.StatusCode != 405 {
		t.Errorf("Esperava 405, obteve %d", resp.StatusCode)
	}
}

// ------------------------
// 2️⃣ JSON válido
// ------------------------
func TestValidTransactionParsing(t *testing.T) {
	reqBody := map[string]string{"amount": "150.25", "type": "deposit"}
	body, _ := json.Marshal(reqBody)

	req := events.APIGatewayV2HTTPRequest{
		Body: string(body),
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	resp, _ := handler(context.Background(), req)
	if resp.StatusCode != 500 && resp.StatusCode != 200 {
		t.Errorf("Esperava 200 ou 500 (SNS não configurado), obteve %d", resp.StatusCode)
	}
}

// ------------------------
// 3️⃣ JSON inválido
// ------------------------
func TestInvalidJSON(t *testing.T) {
	req := events.APIGatewayV2HTTPRequest{
		Body: "{invalid-json",
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	resp, _ := handler(context.Background(), req)
	if resp.StatusCode != 400 {
		t.Errorf("Esperava 400 para JSON inválido, obteve %d", resp.StatusCode)
	}
}

// ------------------------
// 4️⃣ Valor inválido ou negativo
// ------------------------
func TestInvalidAmount(t *testing.T) {
	reqBody := map[string]string{"amount": "-10", "type": "deposit"}
	body, _ := json.Marshal(reqBody)

	req := events.APIGatewayV2HTTPRequest{
		Body: string(body),
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	resp, _ := handler(context.Background(), req)
	if resp.StatusCode != 400 {
		t.Errorf("Esperava 400 para valor inválido, obteve %d", resp.StatusCode)
	}
}

// ------------------------
// 5️⃣ Tipo inválido
// ------------------------
func TestInvalidType(t *testing.T) {
	reqBody := map[string]string{"amount": "100", "type": "invalid"}
	body, _ := json.Marshal(reqBody)

	req := events.APIGatewayV2HTTPRequest{
		Body: string(body),
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	resp, _ := handler(context.Background(), req)
	if resp.StatusCode != 400 {
		t.Errorf("Esperava 400 para tipo inválido, obteve %d", resp.StatusCode)
	}
}

// ------------------------
// 6️⃣ SNS_TOPIC_ARN não configurado
// ------------------------
func TestMissingSNSTopic(t *testing.T) {
	reqBody := map[string]string{"amount": "50", "type": "deposit"}
	body, _ := json.Marshal(reqBody)

	req := events.APIGatewayV2HTTPRequest{
		Body: string(body),
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	// Garante que a variável não está definida
	t.Setenv("SNS_TOPIC_ARN", "")
	resp, _ := handler(context.Background(), req)
	if resp.StatusCode != 500 {
		t.Errorf("Esperava 500 quando SNS_TOPIC_ARN não configurado, obteve %d", resp.StatusCode)
	}
}

// ------------------------
// 7️⃣ Mock de erro no SNS (pode usar interface ou pacote de mocking AWS)
// ------------------------
type mockSNSClient struct {
	shouldFail bool
}

func (m *mockSNSClient) Publish(ctx context.Context, input *sns.PublishInput, optFns ...func(*sns.Options)) (*sns.PublishOutput, error) {
	if m.shouldFail {
		return nil, errors.New("erro simulado SNS")
	}
	return &sns.PublishOutput{}, nil
}

func TestSNSPublishSuccess(t *testing.T) {
	reqBody := map[string]string{"amount": "100", "type": "deposit"}
	body, _ := json.Marshal(reqBody)

	req := events.APIGatewayV2HTTPRequest{
		Body: string(body),
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	t.Setenv("SNS_TOPIC_ARN", "arn:aws:sns:us-east-1:123456789012:test-topic")
	snsClient = &mockSNSClient{shouldFail: false}

	resp, _ := handler(context.Background(), req)
	if resp.StatusCode != 200 {
		t.Errorf("Esperava 200 no caminho de sucesso, obteve %d", resp.StatusCode)
	}
}

func TestSNSPublishFails(t *testing.T) {
	reqBody := map[string]string{"amount": "100", "type": "deposit"}
	body, _ := json.Marshal(reqBody)

	req := events.APIGatewayV2HTTPRequest{
		Body: string(body),
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: "POST",
			},
		},
	}

	t.Setenv("SNS_TOPIC_ARN", "arn:aws:sns:us-east-1:123456789012:test-topic")
	snsClient = &mockSNSClient{shouldFail: true}

	resp, _ := handler(context.Background(), req)
	if resp.StatusCode != 500 {
		t.Errorf("Esperava 500 quando Publish falha, obteve %d", resp.StatusCode)
	}
}
