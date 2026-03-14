.PHONY: help all setup secrets deploy update-ngrok ui test validate clean status logs

# Cores para output
GREEN=\033[0;32m
YELLOW=\033[1;33m
BLUE=\033[0;34m
NC=\033[0m # No Color

help: ## Mostra esta ajuda
	@echo "$(GREEN)Scripts de Automação - Lab CI/CD$(NC)"
	@echo ""
	@echo "$(YELLOW)Comandos disponíveis:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Fluxo mais rápido:$(NC)"
	@echo "  $(BLUE)make all$(NC)         # Executa tudo automaticamente (setup + secrets + deploy)"
	@echo ""
	@echo "$(YELLOW)Ou passo a passo:$(NC)"
	@echo "  1. make setup        # Criar cluster"
	@echo "  2. make secrets      # Configurar secrets"
	@echo "  3. make deploy       # Deploy dos manifestos"
	@echo "  4. make validate     # Validação do ambiente"
	@echo ""

all: ## 🚀 Executa tudo: setup + secrets + deploy + validação
	@echo "$(BLUE)════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN)  Instalação Completa do Ambiente CI/CD$(NC)"
	@echo "$(BLUE)════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)Isso vai executar:$(NC)"
	@echo "  1. Criar cluster k3d e instalar componentes"
	@echo "  2. Configurar secrets (GitHub + Docker Hub)"
	@echo "  3. Deploy dos manifestos do Argo"
	@echo "  4. Validação rápida"
	@echo ""
	@read -p "Continuar? (s/N): " confirm; \
	if [ "$$confirm" = "s" ] || [ "$$confirm" = "S" ]; then \
		$(MAKE) setup && \
		$(MAKE) secrets && \
		$(MAKE) deploy && \
		$(MAKE) validate; \
	else \
		echo "$(YELLOW)Cancelado. Use 'make help' para ver comandos individuais.$(NC)"; \
	fi

setup: ## Cria o cluster k3d e instala componentes base (Argo, Istio, Nginx)
	@echo "$(GREEN)🚀 Criando cluster e instalando componentes...$(NC)"
	cd cluster-config && ./setup.sh

secrets: ## Configura secrets (GitHub token e Docker Hub)
	@echo "$(GREEN)🔐 Configurando secrets...$(NC)"
	cd cluster-config && ./setup-secrets.sh

deploy: ## Deploy completo e interativo dos manifestos do Argo
	@echo "$(GREEN)📦 Fazendo deploy dos manifestos...$(NC)"
	cd cluster-config && ./deploy-argo-manifests.sh


update-ngrok: ## Atualiza a URL do Ngrok no EventSource
	@echo "$(GREEN)🌐 Atualizando URL do Ngrok...$(NC)"
	cd cluster-config && ./update-ngrok-url.sh

ui: ## Mostra como acessar a UI do Argo Workflows
	@echo "$(GREEN)🖥️  UI do Argo Workflows$(NC)"
	@echo "$(YELLOW)Acesse via Ingress: http://argoworkflows.local$(NC)"
	@echo "$(YELLOW)Certifique-se de ter argoworkflows.local no /etc/hosts$(NC)"

test: ## Cria um workflow de teste
	@echo "$(GREEN)🧪 Criando workflow de teste...$(NC)"
	cd cluster-config && ./test-workflow.sh

validate: ## Valida se todo o ambiente está configurado corretamente
	@echo "$(GREEN)🔍 Validando ambiente...$(NC)"
	cd cluster-config && ./validate.sh



status: ## Mostra o status de todos os componentes
	@echo "$(GREEN)📊 Status dos componentes:$(NC)"
	@echo ""
	@echo "$(YELLOW)Cluster:$(NC)"
	@k3d cluster list || echo "  ❌ Nenhum cluster encontrado"
	@echo ""
	@echo "$(YELLOW)Argo Events:$(NC)"
	@kubectl get pods -n argo-events 2>/dev/null || echo "  ❌ Namespace não encontrado"
	@echo ""
	@echo "$(YELLOW)Argo Workflows:$(NC)"
	@kubectl get pods -n argo 2>/dev/null || echo "  ❌ Namespace não encontrado"
	@echo ""
	@echo "$(YELLOW)EventSource e Sensor:$(NC)"
	@kubectl get eventsource,sensor -n argo-events 2>/dev/null || echo "  ❌ Recursos não encontrados"
	@echo ""
	@echo "$(YELLOW)Namespace app-b e Istio:$(NC)"
	@kubectl get namespace app-b 2>/dev/null || echo "  ❌ Namespace app-b não encontrado"
	@kubectl get gateway,virtualservice -n app-b 2>/dev/null || echo "  ❌ Recursos Istio não encontrados"
	@echo ""
	@echo "$(YELLOW)Ingress:$(NC)"
	@kubectl get ingress -n argo-events 2>/dev/null || echo "  ❌ Ingress não encontrado"
	@echo ""
	@echo "$(YELLOW)Workflows em execução:$(NC)"
	@kubectl get workflows -n argo 2>/dev/null || echo "  ℹ️  Nenhum workflow em execução"

logs: ## Mostra os logs dos componentes principais
	@echo "$(GREEN)📝 Logs dos componentes:$(NC)"
	@echo ""
	@echo "$(YELLOW)Escolha qual log visualizar:$(NC)"
	@echo "  1) EventSource (GitHub)"
	@echo "  2) Sensor (app-a)"
	@echo "  3) Sensor (app-b)"
	@echo "  4) Workflows"
	@read -p "Digite o número: " choice; \
	case $$choice in \
		1) echo "$(GREEN)Logs do EventSource:$(NC)"; kubectl logs -n argo-events -l eventsource-name=github -f ;; \
		2) echo "$(GREEN)Logs do Sensor app-a:$(NC)"; kubectl logs -n argo-events -l sensor-name=app-a-sensor -f ;; \
		3) echo "$(GREEN)Logs do Sensor app-b:$(NC)"; kubectl logs -n argo-events -l sensor-name=app-b-sensor -f ;; \
		4) echo "$(GREEN)Workflows:$(NC)"; kubectl get workflows -n argo ;; \
		*) echo "$(YELLOW)Opção inválida$(NC)" ;; \
	esac

clean: ## Remove workflows antigos
	@echo "$(YELLOW)⚠️  Removendo workflows antigos...$(NC)"
	@read -p "Tem certeza? (s/N): " confirm; \
	if [ "$$confirm" = "s" ] || [ "$$confirm" = "S" ]; then \
		kubectl delete workflows -n argo --all 2>/dev/null && echo "$(GREEN)✅ Workflows removidos$(NC)" || echo "$(YELLOW)ℹ️  Nenhum workflow para remover$(NC)"; \
	else \
		echo "$(YELLOW)Cancelado$(NC)"; \
	fi

restart-eventsource: ## Reinicia os pods do EventSource
	@echo "$(GREEN)🔄 Reiniciando EventSource...$(NC)"
	kubectl delete pods -n argo-events -l eventsource-name=github
	@echo "$(GREEN)✅ EventSource reiniciado$(NC)"

restart-sensor: ## Reinicia os pods do Sensor
	@echo "$(GREEN)🔄 Reiniciando Sensor...$(NC)"
	kubectl delete pods -n argo-events -l sensor-name=app-a-sensor
	@echo "$(GREEN)✅ Sensor reiniciado$(NC)"

destroy: ## Deleta o cluster completamente
	@echo "$(YELLOW)⚠️  ATENÇÃO: Isto vai deletar o cluster completo!$(NC)"
	@echo "$(YELLOW)Clusters k3d disponíveis:$(NC)"
	@k3d cluster list 2>/dev/null || echo "  Nenhum cluster encontrado"
	@echo ""
	@read -p "Digite o nome do cluster para deletar (ou Enter para cancelar): " cluster_name; \
	if [ -n "$$cluster_name" ]; then \
		k3d cluster delete "$$cluster_name" && echo "$(GREEN)✅ Cluster deletado$(NC)" || echo "$(YELLOW)ℹ️  Cluster não encontrado$(NC)"; \
	else \
		echo "$(YELLOW)Cancelado$(NC)"; \
	fi

watch-workflows: ## Monitora workflows em tempo real
	@echo "$(GREEN)👀 Monitorando workflows...$(NC)"
	@echo "$(YELLOW)Pressione Ctrl+C para sair$(NC)"
	@kubectl get workflows -n argo -w

watch-events: ## Monitora pods do Argo Events em tempo real
	@echo "$(GREEN)👀 Monitorando Argo Events...$(NC)"
	@echo "$(YELLOW)Pressione Ctrl+C para sair$(NC)"
	@kubectl get pods -n argo-events -w

ngrok-url: ## Mostra a URL atual do Ngrok
	@echo "$(GREEN)🌐 URL do Ngrok:$(NC)"
	@curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -oP '"public_url":"https://\K[^"]*' | head -1 | sed 's/^/  https:\/\//' || echo "  $(YELLOW)Ngrok não está rodando$(NC)"
	@echo ""
	@echo "$(YELLOW)Para configurar webhook no GitHub:$(NC)"
	@echo "  https://github.com/SEU_USUARIO/app-a/settings/hooks"

	@echo "  3. Monitore workflows: make watch-workflows"
