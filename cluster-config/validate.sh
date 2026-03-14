#!/bin/bash

# Script de validação - verifica se todo o ambiente está configurado corretamente

set -e

echo "================================================"
echo "Validação do Ambiente CI/CD"
echo "================================================"
echo ""

ERRORS=0
WARNINGS=0

# ==================================================
# Funções auxiliares
# ==================================================

check_ok() {
  echo "✅ $1"
}

check_warning() {
  echo "⚠️  $1"
  ((WARNINGS++))
}

check_error() {
  echo "❌ $1"
  ((ERRORS++))
}

# ==================================================
# 1. Verificar Cluster
# ==================================================
echo "🔍 Verificando cluster k3d..."
echo ""

# Detecta clusters k3d rodando (conta linhas excluindo header)
RUNNING_CLUSTERS=$(k3d cluster list 2>/dev/null | tail -n +2 | wc -l || true)

# Garante que é um número
if [ -z "$RUNNING_CLUSTERS" ]; then
  RUNNING_CLUSTERS=0
fi

if [ "$RUNNING_CLUSTERS" -gt 0 ]; then
  CLUSTER_NAMES=$(k3d cluster list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')
  check_ok "Cluster(s) k3d rodando: $CLUSTER_NAMES"
else
  check_error "Nenhum cluster k3d rodando foi encontrado"
  echo "   Execute: ./setup.sh"
fi

if kubectl cluster-info &>/dev/null; then
  check_ok "Conectado ao cluster Kubernetes"
else
  check_error "Não foi possível conectar ao cluster"
fi

echo ""

# ==================================================
# 2. Verificar Namespaces
# ==================================================
echo "🔍 Verificando namespaces..."
echo ""

REQUIRED_NS=("argo" "argo-events" "istio-system" "istio-ingress" "ingress-nginx")
for ns in "${REQUIRED_NS[@]}"; do
  if kubectl get namespace "$ns" &>/dev/null; then
    check_ok "Namespace '$ns' existe"
  else
    check_error "Namespace '$ns' não encontrado"
  fi
done

echo ""

# ==================================================
# 3. Verificar Pods do Argo Events
# ==================================================
echo "🔍 Verificando Argo Events..."
echo ""

# Controller
if kubectl get pods -n argo-events -l app=controller-manager 2>/dev/null | grep -q "Running"; then
  check_ok "Controller Manager está rodando"
else
  check_error "Controller Manager não está rodando"
fi

# Webhook
if kubectl get pods -n argo-events -l app=events-webhook 2>/dev/null | grep -q "Running"; then
  check_ok "Events Webhook está rodando"
else
  check_warning "Events Webhook não está rodando ou não foi encontrado"
fi

# EventBus
if kubectl get eventbus default -n argo-events &>/dev/null; then
  check_ok "EventBus 'default' existe"
  
  NATS_PODS=$(kubectl get pods -n argo-events -l eventbus-name=default 2>/dev/null | tail -n +2 | wc -l || true)
  if [ -z "$NATS_PODS" ]; then
    NATS_PODS=0
  fi
  
  if [ "$NATS_PODS" -ge 3 ]; then
    check_ok "EventBus NATS com 3 pods rodando"
  else
    check_warning "EventBus NATS tem apenas $NATS_PODS pods rodando (esperado: 3)"
  fi
else
  check_error "EventBus 'default' não encontrado"
fi

echo ""

# ==================================================
# 4. Verificar Pods do Argo Workflows
# ==================================================
echo "🔍 Verificando Argo Workflows..."
echo ""

if kubectl get pods -n argo -l app=argo-server 2>/dev/null | grep -q "Running"; then
  check_ok "Argo Server está rodando"
else
  check_error "Argo Server não está rodando"
fi

if kubectl get pods -n argo -l app=workflow-controller 2>/dev/null | grep -q "Running"; then
  check_ok "Workflow Controller está rodando"
else
  check_error "Workflow Controller não está rodando"
fi

echo ""

# ==================================================
# 5. Verificar Secrets
# ==================================================
echo "🔍 Verificando secrets..."
echo ""

if kubectl get secret github-secret -n argo-events &>/dev/null; then
  check_ok "Secret 'github-secret' existe (namespace: argo-events)"
else
  check_error "Secret 'github-secret' não encontrado"
  echo "   Execute: ./setup-secrets.sh"
fi

if kubectl get secret dockerhub-secret -n argo &>/dev/null; then
  check_ok "Secret 'dockerhub-secret' existe (namespace: argo)"
else
  check_error "Secret 'dockerhub-secret' não encontrado"
  echo "   Execute: ./setup-secrets.sh"
fi

echo ""

# ==================================================
# 6. Verificar Service Accounts e RBACs
# ==================================================
echo "🔍 Verificando RBACs e Service Accounts..."
echo ""

if kubectl get serviceaccount workflow-deployer-sa -n argo &>/dev/null; then
  check_ok "ServiceAccount 'workflow-deployer-sa' existe"
else
  check_error "ServiceAccount 'workflow-deployer-sa' não encontrado"
  echo "   Execute: ./deploy-argo-manifests.sh ou ./apply-manifests.sh"
fi

if kubectl get serviceaccount operate-workflow-sa -n argo-events &>/dev/null; then
  check_ok "ServiceAccount 'operate-workflow-sa' existe"
else
  check_error "ServiceAccount 'operate-workflow-sa' não encontrado"
  echo "   Execute: ./deploy-argo-manifests.sh ou ./apply-manifests.sh"
fi

echo ""

# ==================================================
# 7. Verificar EventSource
# ==================================================
echo "🔍 Verificando EventSource..."
echo ""

if kubectl get eventsource github -n argo-events &>/dev/null; then
  check_ok "EventSource 'github' existe"
  
  # Verifica se o serviço foi criado
  if kubectl get service github-eventsource-svc -n argo-events &>/dev/null; then
    check_ok "Serviço 'github-eventsource-svc' foi criado"
  else
    check_warning "Serviço 'github-eventsource-svc' não encontrado"
  fi
  
  # Verifica se o pod está rodando
  if kubectl get pods -n argo-events -l eventsource-name=github 2>/dev/null | grep -q "Running"; then
    check_ok "Pod do EventSource está rodando"
  else
    check_warning "Pod do EventSource não está rodando"
  fi
else
  check_error "EventSource 'github' não encontrado"
  echo "   Execute: ./deploy-argo-manifests.sh ou ./apply-manifests.sh"
fi

echo ""

# ==================================================
# 8. Verificar Ingress
# ==================================================
echo "🔍 Verificando Ingress..."
echo ""

if kubectl get ingress github-eventsource-ingress -n argo-events &>/dev/null; then
  check_ok "Ingress 'github-eventsource-ingress' existe"
else
  check_error "Ingress 'github-eventsource-ingress' não encontrado"
  echo "   Execute: ./deploy-argo-manifests.sh ou ./apply-manifests.sh"
fi

echo ""

# ==================================================
# 9. Verificar Sensor (app-a)
# ==================================================
echo "🔍 Verificando Sensor app-a..."
echo ""

if kubectl get sensor app-a-sensor -n argo-events &>/dev/null; then
  check_ok "Sensor 'app-a-sensor' existe"
  
  # Verifica se o pod está rodando
  if kubectl get pods -n argo-events -l sensor-name=app-a-sensor 2>/dev/null | grep -q "Running"; then
    check_ok "Pod do Sensor app-a está rodando"
  else
    check_warning "Pod do Sensor app-a não está rodando"
  fi
else
  check_error "Sensor 'app-a-sensor' não encontrado"
  echo "   Execute: ./deploy-argo-manifests.sh ou ./apply-manifests.sh"
fi

echo ""

# ==================================================
# 9.1. Verificar Sensor (app-b)
# ==================================================
echo "🔍 Verificando Sensor app-b..."
echo ""

if kubectl get sensor app-b-sensor -n argo-events &>/dev/null; then
  check_ok "Sensor 'app-b-sensor' existe"
  
  # Verifica se o pod está rodando
  if kubectl get pods -n argo-events -l sensor-name=app-b-sensor 2>/dev/null | grep -q "Running"; then
    check_ok "Pod do Sensor app-b está rodando"
  else
    check_warning "Pod do Sensor app-b não está rodando"
  fi
else
  check_error "Sensor 'app-b-sensor' não encontrado"
  echo "   Execute: ./deploy-argo-manifests.sh ou ./apply-manifests.sh"
fi

echo ""

# ==================================================
# 9.2. Verificar Namespace app-b com Istio
# ==================================================
echo "🔍 Verificando namespace app-b..."
echo ""

if kubectl get namespace app-b &>/dev/null; then
  check_ok "Namespace 'app-b' existe"
  
  # Verifica se Istio injection está habilitado
  ISTIO_INJECTION=$(kubectl get namespace app-b -o jsonpath='{.metadata.labels.istio-injection}')
  if [ "$ISTIO_INJECTION" == "enabled" ]; then
    check_ok "Istio injection habilitado no namespace app-b"
  else
    check_warning "Istio injection NÃO está habilitado no namespace app-b"
    echo "   Execute: kubectl label namespace app-b istio-injection=enabled"
  fi
else
  check_warning "Namespace 'app-b' não existe - será criado no primeiro workflow"
fi

echo ""

# ==================================================
# 9.3. Verificar Configurações Istio para app-b
# ==================================================
echo "🔍 Verificando Istio para app-b..."
echo ""

if kubectl get gateway app-b-gateway -n app-b &>/dev/null; then
  check_ok "Gateway 'app-b-gateway' existe"
else
  check_warning "Gateway 'app-b-gateway' não encontrado"
  echo "   Execute: kubectl apply -f argo-worflow-manifests/app-b-istio.yaml"
fi

if kubectl get virtualservice app-b-virtualservice -n app-b &>/dev/null; then
  check_ok "VirtualService 'app-b-virtualservice' existe"
else
  check_warning "VirtualService 'app-b-virtualservice' não encontrado"
  echo "   Execute: kubectl apply -f argo-worflow-manifests/app-b-istio.yaml"
fi

echo ""

# ==================================================
# 10. Verificar Ngrok
# ==================================================
echo "🔍 Verificando Ngrok..."
echo ""

if command -v ngrok &>/dev/null; then
  check_ok "Ngrok está instalado"
  
  # Verifica se está rodando
  if curl -s http://localhost:4040/api/tunnels &>/dev/null; then
    NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | grep -oP '"public_url":"https://\K[^"]*' | head -1)
    if [ -n "$NGROK_URL" ]; then
      check_ok "Ngrok está rodando"
      echo "   URL pública: https://$NGROK_URL"
    else
      check_warning "Ngrok está rodando mas não retornou URL"
    fi
  else
    check_warning "Ngrok não está rodando"
    echo "   Execute: ngrok http 80"
  fi
else
  check_warning "Ngrok não está instalado"
  echo "   Execute a seção de instalação do setup.sh"
fi

echo ""

# ==================================================
# 11. Verificar Nginx Ingress
# ==================================================
echo "🔍 Verificando Nginx Ingress..."
echo ""

if kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller 2>/dev/null | grep -q "Running"; then
  check_ok "Nginx Ingress Controller está rodando"
else
  check_error "Nginx Ingress Controller não está rodando"
fi

echo ""

# ==================================================
# Resumo
# ==================================================
echo "================================================"
echo "Resumo da Validação"
echo "================================================"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
  echo "✨ Tudo está perfeito! Ambiente 100% configurado."
  echo ""
  echo "📝 Próximos passos:"
  echo "   1. Configure os webhooks no GitHub apontando para a URL do Ngrok"
  echo "      - App-a: https://github.com/gioufop/app-a/settings/hooks"
  echo "      - App-b: https://github.com/gioufop/app-b/settings/hooks"
  echo "   2. Faça um push nos repositórios"
  echo "   3. Acompanhe: kubectl get workflows -n argo -w"
  exit 0
elif [ $ERRORS -eq 0 ]; then
  echo "⚠️  Ambiente está funcional mas com $WARNINGS avisos."
  echo ""
  echo "   Os avisos acima não impedem o funcionamento, mas é recomendado"
  echo "   resolver para ter um ambiente mais robusto."
  exit 0
else
  echo "❌ Encontrados $ERRORS erros e $WARNINGS avisos."
  echo ""
  echo "   Resolva os erros antes de tentar usar o ambiente."
  echo ""
  if [ $ERRORS -gt 0 ]; then
    echo "💡 Dica: Execute os scripts na seguinte ordem:"
    echo "   1. ./setup.sh"
    echo "   2. ./setup-secrets.sh"
    echo "   3. ./deploy-argo-manifests.sh"
  fi
  exit 1
fi
