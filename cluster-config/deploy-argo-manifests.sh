#!/bin/bash

set -e  # Exit on error

echo "================================================"
echo "Script de Deploy - Argo Events e Workflows"
echo "================================================"
echo ""

# ==================================================
# 0. Validação de Pré-requisitos
# ==================================================
echo "🔍 Validando pré-requisitos..."

# Verifica se o cluster está rodando
if ! kubectl cluster-info &>/dev/null; then
  echo "❌ Erro: Cluster Kubernetes não encontrado!"
  echo "   Execute primeiro: ./setup.sh"
  exit 1
fi

# Verifica se os namespaces necessários existem
REQUIRED_NAMESPACES=("argo" "argo-events")
for ns in "${REQUIRED_NAMESPACES[@]}"; do
  if ! kubectl get namespace "$ns" &>/dev/null; then
    echo "❌ Erro: Namespace '$ns' não encontrado!"
    echo "   Execute primeiro: ./setup.sh"
    exit 1
  fi
done

echo "✅ Pré-requisitos OK!"
echo ""

# ==================================================
# 1. Deploy dos RBACs (Argo Workflows)
# ==================================================
echo "🔧 Aplicando RBACs do Argo Workflows..."

kubectl apply -f ../argo-worflow-manifests/workflow-deployer-rbac.yaml

echo "⏳ Aguardando ServiceAccount 'workflow-deployer-sa' ficar disponível..."
sleep 3

kubectl get serviceaccount workflow-deployer-sa -n argo || echo "⚠️  ServiceAccount ainda está sendo criado..."

echo "✅ RBACs do Argo Workflows aplicados!"
echo ""

# ==================================================
# 2. Deploy dos RBACs (Argo Events)
# ==================================================
echo "🔧 Aplicando RBACs do Argo Events..."

kubectl apply -f ../argo-worflow-manifests/sensor-rbac.yaml

echo "⏳ Aguardando ServiceAccount 'operate-workflow-sa' ficar disponível..."
sleep 3

kubectl get serviceaccount operate-workflow-sa -n argo-events || echo "⚠️  ServiceAccount ainda está sendo criado..."

echo "✅ RBACs do Argo Events aplicados!"
echo ""

# ==================================================
# 3. Configuração de Secrets (GitHub e Docker Hub)
# ==================================================
echo "🔐 Configurando secrets..."
echo ""
echo "ℹ️  Os seguintes secrets precisam ser configurados:"
echo "   1. github-secret (token do GitHub)"
echo "   2. dockerhub-secret (credenciais do Docker Hub)"
echo ""

# GitHub Secret
if kubectl get secret github-secret -n argo-events &>/dev/null; then
  echo "✅ Secret 'github-secret' já existe no namespace argo-events"
else
  echo "⚠️  Secret 'github-secret' não encontrado!"
  read -p "Deseja criar o secret do GitHub agora? (s/N): " -r
  echo ""
  if [[ $REPLY =~ ^[Ss]$ ]]; then
    read -p "Digite seu GitHub Personal Access Token: " -s GITHUB_TOKEN
    echo ""
    kubectl create secret generic github-secret \
      -n argo-events \
      --from-literal=secret="$GITHUB_TOKEN"
    echo "✅ Secret 'github-secret' criado!"
  else
    echo "⚠️  Você precisará criar o secret manualmente:"
    echo "   kubectl create secret generic github-secret -n argo-events --from-literal=secret=YOUR_TOKEN"
  fi
fi

echo ""

# Docker Hub Secret
if kubectl get secret dockerhub-secret -n argo &>/dev/null; then
  echo "✅ Secret 'dockerhub-secret' já existe no namespace argo"
else
  echo "⚠️  Secret 'dockerhub-secret' não encontrado!"
  read -p "Deseja criar o secret do Docker Hub agora? (s/N): " -r
  echo ""
  if [[ $REPLY =~ ^[Ss]$ ]]; then
    read -p "Digite seu Docker Hub username: " DOCKER_USER
    read -p "Digite seu Docker Hub password: " -s DOCKER_PASS
    echo ""
    kubectl create secret docker-registry dockerhub-secret \
      -n argo \
      --docker-server=https://index.docker.io/v1/ \
      --docker-username="$DOCKER_USER" \
      --docker-password="$DOCKER_PASS"
    echo "✅ Secret 'dockerhub-secret' criado!"
  else
    echo "⚠️  Você precisará criar o secret manualmente:"
    echo "   kubectl create secret docker-registry dockerhub-secret -n argo \\"
    echo "     --docker-server=https://index.docker.io/v1/ \\"
    echo "     --docker-username=USERNAME \\"
    echo "     --docker-password=PASSWORD"
  fi
fi

echo ""
echo "✅ Configuração de secrets concluída!"
echo ""

# ==================================================
# 4. Deploy do GitHub EventSource
# ==================================================
echo "🔧 Aplicando GitHub EventSource..."
echo ""

# Verifica se o Ngrok está rodando
NGROK_RUNNING=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -oP '"public_url":"https://\K[^"]*' | head -1)

if [ -z "$NGROK_RUNNING" ]; then
  echo "⚠️  Ngrok não está rodando!"
  echo ""
  echo "📋 Para que os webhooks do GitHub funcionem:"
  echo "   1. Abra um NOVO TERMINAL"
  echo "   2. Execute o comando: ngrok http 80"
  echo "   3. Deixe rodando durante todo o uso do lab"
  echo ""
  read -p "Pressione ENTER depois de iniciar o Ngrok... " -r
  echo ""
  
  # Verifica novamente
  NGROK_RUNNING=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -oP '"public_url":"https://\K[^"]*' | head -1)
  
  if [ -n "$NGROK_RUNNING" ]; then
    echo "✅ Ngrok detectado rodando!"
    echo "   📡 URL: https://$NGROK_RUNNING"
    echo ""
  else
    echo "❌ Ngrok ainda não detectado. Continuando mesmo assim..."
    echo ""
  fi
else
  echo "✅ Ngrok já está rodando!"
  echo "   📡 URL: https://$NGROK_RUNNING"
  echo ""
fi

# Verifica se precisa atualizar a URL do ngrok
CURRENT_NGROK_URL=$(grep -v '^\s*#' ../argo-events-manifests/github-eventsource.yaml | grep -oP 'url: "\K[^"]+' | head -1)

if [ -n "$CURRENT_NGROK_URL" ]; then
  echo "ℹ️  URL do Ngrok configurada no EventSource: $CURRENT_NGROK_URL"
  
  # Compara com a URL rodando (adiciona https:// para comparação)
  if [ -n "$NGROK_RUNNING" ]; then
    NGROK_RUNNING_FULL="https://$NGROK_RUNNING"
    if [ "$NGROK_RUNNING_FULL" != "$CURRENT_NGROK_URL" ]; then
      echo "⚠️  A URL do Ngrok mudou!"
      echo "   Rodando: $NGROK_RUNNING_FULL"
      echo "   Configurada: $CURRENT_NGROK_URL"
      echo ""
    fi
  fi
  
  read -p "Deseja atualizar a URL do Ngrok no EventSource? (s/N): " -r
  echo ""
  if [[ $REPLY =~ ^[Ss]$ ]]; then
    if [ -n "$NGROK_RUNNING" ]; then
      echo "💡 Detectamos que o Ngrok está rodando com: https://$NGROK_RUNNING"
      read -p "Deseja usar essa URL? (S/n): " -r
      echo ""
      if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        NEW_NGROK_URL="https://$NGROK_RUNNING"
      else
        read -p "Digite a nova URL do Ngrok: " NEW_NGROK_URL
      fi
    else
      echo "📋 Digite a URL do Ngrok:"
      read -p "URL (ex: https://abc-123.ngrok-free.app): " NEW_NGROK_URL
    fi
    
    # Atualiza o arquivo (cria backup)
    cp ../argo-events-manifests/github-eventsource.yaml ../argo-events-manifests/github-eventsource.yaml.bak
    # Usa delimitador # no sed para evitar conflitos com / nas URLs
    sed -i "s#url: \"$CURRENT_NGROK_URL\"#url: \"$NEW_NGROK_URL\"#g" ../argo-events-manifests/github-eventsource.yaml
    echo "✅ URL atualizada para: $NEW_NGROK_URL"
    echo ""
  fi
fi

kubectl apply -f ../argo-events-manifests/github-eventsource.yaml

echo "⏳ Aguardando EventSource ficar pronto..."
sleep 10

# Verifica se o serviço foi criado
if kubectl get service github-eventsource-svc -n argo-events &>/dev/null; then
  echo "✅ EventSource criado! Serviço 'github-eventsource-svc' está disponível."
else
  echo "⚠️  Serviço ainda está sendo criado..."
fi

echo ""

# ==================================================
# 5. Deploy do Ingress para o EventSource
# ==================================================
echo "🔧 Aplicando Ingress para EventSource..."

kubectl apply -f ../argo-events-manifests/eventsource-ingress.yaml

echo "⏳ Aguardando Ingress ficar pronto..."
sleep 5

kubectl get ingress github-eventsource-ingress -n argo-events || echo "⚠️  Ingress ainda está sendo criado..."

echo "✅ Ingress aplicado!"
echo ""

# ==================================================
# 6. Deploy do Sensor (app-a)
# ==================================================
echo "🔧 Aplicando Sensor para app-a..."

kubectl apply -f ../argo-worflow-manifests/app-a-sensor.yaml

echo "⏳ Aguardando Sensor ficar pronto..."
sleep 10

if kubectl get pods -n argo-events -l sensor-name=app-a-sensor &>/dev/null; then
  kubectl wait --namespace argo-events \
    --for=condition=ready pod \
    --selector=sensor-name=app-a-sensor \
    --timeout=60s 2>/dev/null || echo "⚠️  Sensor app-a ainda está inicializando..."
fi

echo "✅ Sensor app-a aplicado!"
echo ""

# ==================================================
# 6.1. Deploy do Sensor (app-b)
# ==================================================
echo "🔧 Aplicando Sensor para app-b..."

kubectl apply -f ../argo-worflow-manifests/app-b-sensor.yaml

echo "⏳ Aguardando Sensor ficar pronto..."
sleep 10

if kubectl get pods -n argo-events -l sensor-name=app-b-sensor &>/dev/null; then
  kubectl wait --namespace argo-events \
    --for=condition=ready pod \
    --selector=sensor-name=app-b-sensor \
    --timeout=60s 2>/dev/null || echo "⚠️  Sensor app-b ainda está inicializando..."
fi

echo "✅ Sensor app-b aplicado!"
echo ""

# ==================================================
# 6.2. Configurar namespace app-b com Istio
# ==================================================
echo "🔧 Configurando namespace app-b com Istio..."

kubectl create namespace app-b --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace app-b istio-injection=enabled --overwrite

echo "✅ Namespace app-b configurado com Istio injection!"
echo ""

# ==================================================
# 6.3. Deploy das configurações Istio para app-b
# ==================================================
echo "🔧 Aplicando Istio Gateway e VirtualService para app-b..."

kubectl apply -f ../argo-worflow-manifests/app-b-istio.yaml

echo "✅ Istio Gateway e VirtualService aplicados!"
echo ""

# ==================================================
# 6.4. Deploy do Ingress do Argo Workflows UI
# ==================================================
echo "🔧 Aplicando Ingress do Argo Workflows..."

kubectl apply -f ../argo-worflow-manifests/argo-server-ingress.yaml

echo "⏳ Aguardando Ingress ficar pronto..."
sleep 3

kubectl get ingress argo-server-ingress -n argo || echo "⚠️  Ingress ainda está sendo criado..."

echo "✅ Ingress do Argo Workflows aplicado!"
echo ""
echo "ℹ️  Para acessar a UI do Argo Workflows:"
echo "   1. Adicione ao /etc/hosts: sudo bash -c 'echo \"127.0.0.1 argoworkflows.local\" >> /etc/hosts'"
echo "   2. Acesse: http://argoworkflows.local"
echo ""

# ==================================================
# 8. Configuração do Ngrok (manual)
# ==================================================
echo "🌐 Configuração do Ngrok"
echo ""

# Verifica se o Ngrok já está rodando
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -oP '"public_url":"https://\K[^"]*' | head -1)

if [ -n "$NGROK_URL" ]; then
  echo "✅ Ngrok já está rodando!"
  echo ""
  echo "   📡 URL Pública: https://$NGROK_URL"
  echo ""
  echo "📋 Configure os webhooks no GitHub:"
  echo ""
  echo "► App-a:"
  echo "   1. Acesse: https://github.com/gioufop/app-a/settings/hooks"
  echo "   2. Clique em 'Add webhook' (ou edite se já existir)"
  echo "   3. Payload URL: https://$NGROK_URL/github"
  echo "   4. Content type: application/json"
  echo "   5. Secret: (deixe vazio)"
  echo "   6. Which events: Just the push event"
  echo "   7. Active: ✓"
  echo "   8. Clique em 'Add webhook' ou 'Update webhook'"
  echo ""
  echo "► App-b:"
  echo "   1. Acesse: https://github.com/gioufop/app-b/settings/hooks"
  echo "   2. Clique em 'Add webhook' (ou edite se já existir)"
  echo "   3. Payload URL: https://$NGROK_URL/github"
  echo "   4. Content type: application/json"
  echo "   5. Secret: (deixe vazio)"
  echo "   6. Which events: Just the push event"
  echo "   7. Active: ✓"
  echo "   8. Clique em 'Add webhook' ou 'Update webhook'"
  echo ""
else
  echo "⚠️  Ngrok não está rodando."
  echo ""
  echo "📋 INSTRUÇÕES:"
  echo "   1. Abra um NOVO TERMINAL"
  echo "   2. Execute o comando: ngrok http 80"
  echo "   3. Deixe o Ngrok rodando nesse terminal"
  echo ""
  read -p "Pressione ENTER depois de iniciar o Ngrok... " -r
  echo ""
  
  echo "🔍 Verificando se o Ngrok está rodando..."
  sleep 2
  
  NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -oP '"public_url":"https://\K[^"]*' | head -1)
  
  if [ -n "$NGROK_URL" ]; then
    echo "✅ Ngrok detectado rodando!"
    echo ""
    echo "   📡 URL Pública: https://$NGROK_URL"
    echo ""
    echo "📋 Configure os webhooks no GitHub:"
    echo ""
    echo "► App-a:"
    echo "   1. Acesse: https://github.com/gioufop/app-a/settings/hooks"
    echo "   2. Clique em 'Add webhook'"
    echo "   3. Payload URL: https://$NGROK_URL/github"
    echo "   4. Content type: application/json"
    echo "   5. Secret: (deixe vazio)"
    echo "   6. Which events: Just the push event"
    echo "   7. Active: ✓"
    echo "   8. Clique em 'Add webhook'"
    echo ""
    echo "► App-b:"
    echo "   1. Acesse: https://github.com/gioufop/app-b/settings/hooks"
    echo "   2. Clique em 'Add webhook'"
    echo "   3. Payload URL: https://$NGROK_URL/github"
    echo "   4. Content type: application/json"
    echo "   5. Secret: (deixe vazio)"
    echo "   6. Which events: Just the push event"
    echo "   7. Active: ✓"
    echo "   8. Clique em 'Add webhook'"
    echo ""
  else
    echo "❌ Ngrok não detectado!"
    echo ""
    echo "   Possíveis causas:"
    echo "   - Ngrok ainda está inicializando (aguarde alguns segundos)"
    echo "   - Ngrok não foi executado corretamente"
    echo "   - Ngrok não está acessível em http://localhost:4040"
    echo ""
    echo "   Tente executar novamente: ngrok http 80"
    echo ""
  fi
fi

echo ""

# ==================================================
# Resumo da Instalação
# ==================================================
echo "================================================"
echo "✨ Deploy completo!"
echo "================================================"
echo ""
echo "📋 Componentes instalados:"
echo ""
echo "Argo Workflows RBACs:"
kubectl get serviceaccount workflow-deployer-sa -n argo 2>/dev/null || echo "  ⚠️ workflow-deployer-sa não encontrado"
echo ""
echo "Argo Events RBACs:"
kubectl get serviceaccount operate-workflow-sa -n argo-events 2>/dev/null || echo "  ⚠️ operate-workflow-sa não encontrado"
echo ""
echo "GitHub EventSource:"
kubectl get eventsource github -n argo-events 2>/dev/null || echo "  ⚠️ EventSource não encontrado"
echo ""
echo "Sensor app-a:"
kubectl get sensor app-a-sensor -n argo-events 2>/dev/null || echo "  ⚠️ Sensor app-a não encontrado"
echo ""
echo "Sensor app-b:"
kubectl get sensor app-b-sensor -n argo-events 2>/dev/null || echo "  ⚠️ Sensor app-b não encontrado"
echo ""
echo "Namespace app-b:"
kubectl get namespace app-b 2>/dev/null || echo "  ⚠️ Namespace app-b não encontrado"
echo ""
echo "Istio Gateway e VirtualService (app-b):"
kubectl get gateway,virtualservice -n app-b 2>/dev/null || echo "  ⚠️ Recursos Istio não encontrados"
echo ""
echo "Ingress (EventSource):"
kubectl get ingress github-eventsource-ingress -n argo-events 2>/dev/null || echo "  ⚠️ Ingress não encontrado"
echo ""
echo "Ingress (Argo Workflows):"
kubectl get ingress argo-server-ingress -n argo 2>/dev/null || echo "  ⚠️ Ingress não encontrado"
echo ""

# ==================================================
# Próximos Passos
# ==================================================
echo "📝 Próximos passos:"
echo ""
echo "1. ✅ Verifique se todos os pods estão rodando:"
echo "   kubectl get pods -n argo-events"
echo ""
echo "2. 🌐 Configure os webhooks no GitHub (se ainda não configurou):"
echo "   - App-a: https://github.com/gioufop/app-a/settings/hooks"
echo "   - App-b: https://github.com/gioufop/app-b/settings/hooks"
echo "   - Payload URL: https://SUA-URL-NGROK/github"
echo "   - Content type: application/json"
echo "   - Events: push"
echo ""
echo "3. 🧪 Teste fazendo um push nos repositórios:"
echo "   - app-a: git push origin main"
echo "   - app-b: git push origin main"
echo ""
echo "4. 👀 Acompanhe o workflow:"
echo "   - UI: http://argoworkflows.local (adicione ao /etc/hosts primeiro)"
echo "   - CLI: kubectl get workflows -n argo -w"
echo ""
echo "================================================"
echo ""
echo "================================================"
