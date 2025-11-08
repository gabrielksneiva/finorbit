package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	_ "github.com/lib/pq"
	"github.com/shopspring/decimal"
)

// ===============================
// 💡 Estrutura da transação
// ===============================
type Transaction struct {
	UserID    string          `json:"user_id"`
	Amount    decimal.Decimal `json:"amount"`
	Type      string          `json:"type"`
	Timestamp string          `json:"timestamp"`
}

var db *sql.DB

// ===============================
// 🔧 Inicialização global (executa 1x por Lambda container)
// ===============================
func init() {
	if os.Getenv("GO_ENV") == "test" {
		log.Println("🧪 Ambiente de teste detectado — conexão RDS ignorada.")
		return
	}

	connStr := fmt.Sprintf(
		"host=%s user=%s password=%s dbname=%s sslmode=require",
		os.Getenv("DB_HOST"),
		os.Getenv("DB_USER"),
		os.Getenv("DB_PASS"),
		os.Getenv("DB_NAME"),
	)

	var err error
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatalf("❌ Erro ao conectar ao banco: %v", err)
	}

	// Testa a conexão
	if err := db.Ping(); err != nil {
		log.Fatalf("❌ Falha ao conectar ao RDS: %v", err)
	}

	log.Println("✅ Conexão com RDS estabelecida com sucesso.")

	// Verifica e cria tabela se necessário
	ensureTableExists()
}

// ===============================
// 🏗️ Criação da tabela, se não existir
// ===============================
func ensureTableExists() {
	const checkQuery = `
	SELECT EXISTS (
		SELECT FROM information_schema.tables 
		WHERE table_schema = 'public' 
		AND table_name = 'transactions'
	);
	`

	var exists bool
	err := db.QueryRow(checkQuery).Scan(&exists)
	if err != nil {
		log.Fatalf("❌ Erro ao verificar existência da tabela: %v", err)
	}

	if exists {
		log.Println("📦 Tabela 'transactions' já existe — sem alterações.")
		return
	}

	createQuery := `
	CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

	CREATE TABLE public.transactions (
		id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
		user_id UUID NOT NULL,
		amount NUMERIC(12,2) NOT NULL,
		type VARCHAR(50) NOT NULL,
		timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);
	`

	_, err = db.Exec(createQuery)
	if err != nil {
		log.Fatalf("❌ Erro ao criar tabela 'transactions': %v", err)
	}

	log.Println("✅ Tabela 'transactions' criada com sucesso!")
}

// ===============================
// 📬 Processamento das mensagens
// ===============================
func handler(ctx context.Context, sqsEvent events.SQSEvent) error {
	log.Println("🚀 Iniciando processamento de mensagens SQS...")

	for _, record := range sqsEvent.Records {
		var snsEnvelope events.SNSEntity
		if err := json.Unmarshal([]byte(record.Body), &snsEnvelope); err != nil {
			log.Printf("⚠️ Erro ao decodificar envelope SNS: %v", err)
			continue
		}

		var tx Transaction
		if err := json.Unmarshal([]byte(snsEnvelope.Message), &tx); err != nil {
			log.Printf("⚠️ Erro ao decodificar transação: %v", err)
			continue
		}

		_, err := db.Exec(
			`INSERT INTO transactions (user_id, amount, type, timestamp) VALUES ($1, $2, $3, $4)`,
			tx.UserID, tx.Amount.String(), tx.Type, tx.Timestamp,
		)
		if err != nil {
			log.Printf("❌ Erro ao inserir transação: %v", err)
			continue
		}

		log.Printf("✅ Transação salva com sucesso: user=%s | tipo=%s | valor=%s", tx.UserID, tx.Type, tx.Amount.String())
	}

	return nil
}

// ===============================
// 🚀 Entry point Lambda
// ===============================
func main() {
	if os.Getenv("GO_ENV") == "test" {
		log.Println("🧪 Modo de teste — Lambda não será iniciado.")
		return
	}

	ensureTableExists()
	lambda.Start(handler)
}
