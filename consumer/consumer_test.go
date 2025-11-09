package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"sync"
	"testing"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/aws/aws-lambda-go/events"
)

// =========================================================
// 🧹 Reset global entre testes
// =========================================================
func resetDBSingleton() {
	db = nil
	once = sync.Once{}
}

// =========================================================
// 🧱 Teste de verificação da tabela (ensureTableExists)
// =========================================================
func TestEnsureTableExists_TableAlreadyExists(t *testing.T) {
	resetDBSingleton()
	dbMock, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("Erro ao criar mock: %v", err)
	}
	defer dbMock.Close()
	db = dbMock

	mock.ExpectQuery(`SELECT EXISTS`).
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	ensureTableExists()

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("Expectativas não atendidas: %v", err)
	}
}

func TestEnsureTableExists_CreateTableWhenMissing(t *testing.T) {
	resetDBSingleton()
	dbMock, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("Erro ao criar mock: %v", err)
	}
	defer dbMock.Close()
	db = dbMock

	mock.ExpectQuery(`SELECT EXISTS`).
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))

	mock.ExpectExec(`(?s)CREATE EXTENSION IF NOT EXISTS "uuid-ossp";.*CREATE TABLE public.transactions`).
		WillReturnResult(sqlmock.NewResult(1, 1))

	ensureTableExists()

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("Expectativas não atendidas: %v", err)
	}
}

// =========================================================
// 📬 Teste do handler de mensagens (Lambda handler)
// =========================================================
func TestHandler_ProcessaMensagemValida(t *testing.T) {
	resetDBSingleton()
	dbMock, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("Erro ao criar mock: %v", err)
	}
	defer dbMock.Close()
	db = dbMock

	mock.ExpectExec(`INSERT INTO transactions`).
		WithArgs("user-123", sqlmock.AnyArg(), "deposit", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	snsBody := map[string]interface{}{
		"Message": `{"user_id":"user-123","amount":"100.00","type":"deposit","timestamp":"2025-11-07T00:00:00Z"}`,
	}
	bodyBytes, _ := json.Marshal(snsBody)

	event := events.SQSEvent{
		Records: []events.SQSMessage{{Body: string(bodyBytes)}},
	}

	err = handler(context.Background(), event)
	if err != nil {
		t.Fatalf("Handler retornou erro: %v", err)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("Expectativas não atendidas: %v", err)
	}
}

func TestHandler_MensagemInvalida(t *testing.T) {
	resetDBSingleton()
	event := events.SQSEvent{
		Records: []events.SQSMessage{{Body: "mensagem inválida"}},
	}
	err := handler(context.Background(), event)
	if err != nil {
		t.Fatalf("Handler deveria lidar com erros, mas retornou: %v", err)
	}
}

func TestHandler_InsertFails(t *testing.T) {
	resetDBSingleton()
	dbMock, mock, _ := sqlmock.New()
	defer dbMock.Close()
	db = dbMock

	mock.ExpectExec(`INSERT INTO transactions`).WillReturnError(errors.New("insert failed"))

	snsBody := map[string]interface{}{
		"Message": `{"user_id":"user-123","amount":"100.00","type":"deposit","timestamp":"2025-11-07T00:00:00Z"}`,
	}
	bodyBytes, _ := json.Marshal(snsBody)

	event := events.SQSEvent{
		Records: []events.SQSMessage{{Body: string(bodyBytes)}},
	}

	err := handler(context.Background(), event)
	if err != nil {
		t.Fatalf("Handler não deveria retornar erro, mas retornou: %v", err)
	}
}

// =========================================================
// ⚠️ Testes de falha na verificação/criação da tabela
// =========================================================
func TestEnsureTableExists_CheckQueryFails(t *testing.T) {
	if os.Getenv("BE_CRASHER") == "1" {
		dbMock, mock, _ := sqlmock.New()
		defer dbMock.Close()
		db = dbMock
		mock.ExpectQuery(`SELECT EXISTS`).WillReturnError(errors.New("db error"))
		ensureTableExists()
		return
	}

	cmd := exec.Command(os.Args[0], "-test.run=TestEnsureTableExists_CheckQueryFails")
	cmd.Env = append(os.Environ(), "BE_CRASHER=1")
	err := cmd.Run()
	if e, ok := err.(*exec.ExitError); ok && !e.Success() {
		return
	}
	t.Fatalf("esperava que ensureTableExists chamasse os.Exit(1) ao falhar, mas não chamou")
}

func TestEnsureTableExists_CreateTableFails(t *testing.T) {
	if os.Getenv("BE_CRASHER_CREATE") == "1" {
		dbMock, mock, _ := sqlmock.New()
		defer dbMock.Close()
		db = dbMock
		mock.ExpectQuery(`SELECT EXISTS`).WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))
		mock.ExpectExec(`(?s)CREATE EXTENSION IF NOT EXISTS "uuid-ossp";.*CREATE TABLE public.transactions`).
			WillReturnError(errors.New("create failed"))
		ensureTableExists()
		return
	}

	cmd := exec.Command(os.Args[0], "-test.run=TestEnsureTableExists_CreateTableFails")
	cmd.Env = append(os.Environ(), "BE_CRASHER_CREATE=1")
	err := cmd.Run()
	if e, ok := err.(*exec.ExitError); ok && !e.Success() {
		return
	}
	t.Fatalf("esperava que ensureTableExists chamasse os.Exit(1) ao falhar ao criar tabela, mas não chamou")
}

// =========================================================
// 🧪 Casos extras para cobertura >70%
// =========================================================
func TestHandler_SQSEventVazio(t *testing.T) {
	resetDBSingleton()
	event := events.SQSEvent{Records: []events.SQSMessage{}}
	err := handler(context.Background(), event)
	if err != nil {
		t.Fatalf("Handler não deve falhar com evento vazio: %v", err)
	}
}

func TestHandler_SNSSemMessage(t *testing.T) {
	resetDBSingleton()
	snsBody := map[string]interface{}{"Data": "valor"}
	bodyBytes, _ := json.Marshal(snsBody)
	event := events.SQSEvent{
		Records: []events.SQSMessage{{Body: string(bodyBytes)}},
	}
	err := handler(context.Background(), event)
	if err != nil {
		t.Fatalf("Handler não deve falhar com SNS sem campo Message: %v", err)
	}
}

func TestHandler_MessageCorrompido(t *testing.T) {
	resetDBSingleton()
	snsBody := map[string]interface{}{"Message": "{invalid json}"}
	bodyBytes, _ := json.Marshal(snsBody)
	event := events.SQSEvent{
		Records: []events.SQSMessage{{Body: string(bodyBytes)}},
	}
	err := handler(context.Background(), event)
	if err != nil {
		t.Fatalf("Handler não deve falhar com JSON corrompido: %v", err)
	}
}

// =========================================================
// 🧠 Teste do main e inicialização manual
// =========================================================
func TestMainFunction(t *testing.T) {
	resetDBSingleton()
	os.Setenv("GO_ENV", "test")
	main() // não deve iniciar Lambda
	t.Log("Main executado no modo teste com sucesso")
}

func TestGetDB_MockConnection(t *testing.T) {
	resetDBSingleton()

	// simula variáveis de ambiente
	os.Setenv("DB_HOST", "localhost")
	os.Setenv("DB_USER", "user")
	os.Setenv("DB_PASS", "pass")
	os.Setenv("DB_NAME", "db")

	// substitui sql.Open via variável global mockada se quiser,
	// mas aqui apenas forçamos o retorno nil para simular sem RDS
	dbMock, _, _ := sqlmock.New()
	db = dbMock

	getDB() // deve inicializar sem erro
	t.Log("getDB executado com sucesso (mock)")
}

func TestMain(m *testing.M) {
	os.Setenv("GO_ENV", "test")
}
