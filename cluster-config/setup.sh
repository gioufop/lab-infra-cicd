#!/bin/bash

set -e  # Exit on error

echo "================================================"
echo "Script de Instalação - Cluster k3d + Argo + Istio"
echo "================================================"
echo ""

# ==================================================
# 0. Configuração do Nome do Cluster
# ==================================================
read -p "Digite o nome do cluster k3d (padrão: gio-challenge): " CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-gio-challenge}

echo ""
echo "📝 Nome do cluster: $CLUSTER_NAME"
echo ""

# ==================================================
# 1. Criando o Cluster k3d
# ==================================================
echo "📦 Verificando se o cluster já existe..."

if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo "⚠️  Cluster '$CLUSTER_NAME' já existe!"
  read -p "Deseja deletar e recriar o cluster? (s/N): " -r
  echo ""
  if [[ $REPLY =~ ^[Ss]$ ]]; then
    echo "🗑️  Deletando cluster existente..."
    k3d cluster delete "$CLUSTER_NAME"
    echo "✅ Cluster deletado!"
  else
    echo "ℹ️  Usando cluster existente. Pulando criação..."
    echo ""
    # Pula para a próxima seção
    kubectl config use-context "k3d-$CLUSTER_NAME"
    echo "✅ Contexto configurado para o cluster existente!"
    echo ""
  fi
fi

if ! k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo "📦 Criando cluster k3d..."
  k3d cluster create "$CLUSTER_NAME" \
    --api-port 6550 \
    --port "80:80@loadbalancer" \
    --port "443:443@loadbalancer" \
    --port "8080:8080@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0" \
    --servers 1 \
    --agents 1

  echo "✅ Cluster k3d criado com sucesso!"
  echo ""
fi

# ==================================================
# 2. Corrigindo DNS do CoreDNS
# ==================================================
echo "🔧 Corrigindo DNS do CoreDNS..."

# Verifica se o CoreDNS está rodando
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=k8s-app=kube-dns \
  --timeout=60s 2>/dev/null || echo "⚠️  CoreDNS ainda está inicializando..."

# Aplica o patch no ConfigMap do CoreDNS para usar DNS público
kubectl patch configmap coredns -n kube-system --type merge -p '{"data":{"Corefile":".:53 {\n    errors\n    health\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n      pods insecure\n      fallthrough in-addr.arpa ip6.arpa\n    }\n    hosts /etc/coredns/NodeHosts {\n      ttl 60\n      reload 15s\n      fallthrough\n    }\n    prometheus :9153\n    forward . 8.8.8.8 1.1.1.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"}}'

# Reinicia o CoreDNS para aplicar as alterações
kubectl rollout restart deployment coredns -n kube-system

echo "⏳ Aguardando CoreDNS reiniciar..."
kubectl rollout status deployment coredns -n kube-system --timeout=60s || echo "⚠️  CoreDNS ainda está reiniciando..."

echo "✅ DNS do CoreDNS corrigido com sucesso!"
echo ""

# ==================================================
# 3. Instalando o Nginx Ingress
# ==================================================
echo "🔧 Instalando Nginx Ingress..."

# Adiciona o repositório oficial do Nginx Ingress
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Cria o namespace
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -

# Instala o Nginx Ingress Controller
if helm list -n ingress-nginx | grep -q "ingress-nginx"; then
  echo "⚠️  Nginx Ingress já instalado, fazendo upgrade..."
  helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --set controller.service.type=LoadBalancer
else
  helm install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --set controller.service.type=LoadBalancer
fi

echo "⏳ Aguardando Nginx Ingress ficar pronto..."
sleep 10

if kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller &>/dev/null; then
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s || echo "⚠️  Nginx Ingress ainda está inicializando..."
fi

echo "✅ Nginx Ingress instalado com sucesso!"
echo ""

# ==================================================
# 4. Instalando o Istio (Control Plane e Data Plane)
# ==================================================
echo "🔧 Instalando Istio..."

# Adiciona o repositório oficial do Istio
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

# Cria o namespace para o Control Plane
kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -

# Instala os componentes base e o Istiod
if helm list -n istio-system | grep -q "istio-base"; then
  echo "⚠️  Istio base já instalado, fazendo upgrade..."
  helm upgrade istio-base istio/base -n istio-system --set defaultRevision=default
else
  helm install istio-base istio/base -n istio-system --set defaultRevision=default
fi

if helm list -n istio-system | grep -q "istiod"; then
  echo "⚠️  Istiod já instalado, fazendo upgrade..."
  helm upgrade istiod istio/istiod -n istio-system --wait
else
  helm install istiod istio/istiod -n istio-system --wait
fi

# Cria o namespace isolado para o Ingress Gateway
kubectl create namespace istio-ingress --dry-run=client -o yaml | kubectl apply -f -

# Instala o Gateway no seu próprio namespace
if helm list -n istio-ingress | grep -q "istio-ingressgateway"; then
  echo "⚠️  Istio Ingress Gateway já instalado, fazendo upgrade..."
  helm upgrade istio-ingressgateway istio/gateway -n istio-ingress \
    --set service.type=LoadBalancer \
    --set 'service.ports[0].name=http2' \
    --set 'service.ports[0].port=8080' \
    --set 'service.ports[0].targetPort=8080'
else
  helm install istio-ingressgateway istio/gateway -n istio-ingress \
    --set service.type=LoadBalancer \
    --set 'service.ports[0].name=http2' \
    --set 'service.ports[0].port=8080' \
    --set 'service.ports[0].targetPort=8080'
fi

echo "✅ Istio instalado com sucesso!"
echo ""

# ==================================================
# 5. Instalando o Argo Workflows
# ==================================================
echo "🔧 Instalando Argo Workflows..."

# Criar o namespace
kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f -

# Aplicar o ficheiro de instalação oficial (versão quick-start)
kubectl apply --server-side -n argo -f https://github.com/argoproj/argo-workflows/releases/latest/download/quick-start-minimal.yaml

echo "⏳ Aguardando Argo Workflows ficar pronto..."
sleep 15

# Espera pelo argo-server e workflow-controller
if kubectl get pods -n argo -l app=argo-server &>/dev/null; then
  kubectl wait --namespace argo \
    --for=condition=ready pod \
    --selector=app=argo-server \
    --timeout=180s || echo "⚠️  Alguns pods ainda estão inicializando..."
fi

echo "✅ Argo Workflows instalado com sucesso!"
echo ""

# ==================================================
# 6. Instalando o Argo Events
# ==================================================
echo "🔧 Instalando Argo Events..."

# Criar o namespace
kubectl create namespace argo-events --dry-run=client -o yaml | kubectl apply -f -

# Instalar os controladores base e CRDs
kubectl apply -n argo-events -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install.yaml

# Instalar o Validating Webhook
kubectl apply -n argo-events -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install-validating-webhook.yaml

echo "⏳ Aguardando Argo Events ficar pronto..."
sleep 30

# Espera pelos pods do controller-manager e webhook
echo "   Aguardando controller-manager..."
kubectl wait --namespace argo-events \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=controller-manager \
  --timeout=120s 2>/dev/null || true

echo "   Aguardando events-webhook..."
kubectl wait --namespace argo-events \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=events-webhook \
  --timeout=120s 2>/dev/null || true

echo "✅ Argo Events instalado com sucesso!"
echo ""

# ==================================================
# 7. Criando EventBus
# ==================================================
echo "🔧 Criando EventBus..."

# Verifica se o EventBus já existe
if kubectl get eventbus default -n argo-events &>/dev/null; then
  echo "ℹ️  EventBus 'default' já existe, pulando criação..."
else
  cat <<EOF | kubectl apply -n argo-events -f -
apiVersion: argoproj.io/v1alpha1
kind: EventBus
metadata:
  name: default
spec:
  nats:
    native: {}
EOF

  echo "⏳ Aguardando EventBus ficar pronto..."
  sleep 30

  # Verifica se os pods do EventBus NATS estão rodando
  echo "   Aguardando pods do EventBus..."
  for i in {1..30}; do
    READY=$(kubectl get pods -n argo-events -l app.kubernetes.io/component=eventbus 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$READY" -ge 3 ]; then
      echo "   ✅ EventBus com 3 pods rodando!"
      break
    fi
    echo "   ⏳ Aguardando... ($i/30)"
    sleep 5
  done
fi

echo "✅ EventBus criado com sucesso!"
echo ""

# ==================================================
# 8. Instalando o Ngrok
# ==================================================
echo "🔧 Instalando Ngrok..."

if command -v ngrok &>/dev/null; then
  echo "ℹ️  Ngrok já está instalado, pulando..."
else
  curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/keyrings/ngrok.asc >/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/ngrok.asc] https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
  sudo apt update && sudo apt install ngrok -y
fi

echo "✅ Ngrok instalado com sucesso!"
echo ""

# ==================================================
# Resumo da Instalação
# ==================================================
echo "================================================"
echo "✨ Instalação completa!"
echo "================================================"
echo ""
echo "📋 Validação dos componentes instalados:"
echo ""
echo "Nginx Ingress:"
kubectl get pods -n ingress-nginx
echo ""
echo "Istio System:"
kubectl get pods -n istio-system
echo ""
echo "Istio Ingress:"
kubectl get pods -n istio-ingress
echo ""
echo "Argo Workflows:"
kubectl get pods -n argo
echo ""
echo "Argo Events:"
kubectl get pods -n argo-events
echo ""
# ==================================================
# 9. Criar Workflow de Teste (Opcional)
# ==================================================
echo "📝 Deseja criar um workflow de teste?"
read -p "Criar workflow hello-world? (S/n): " -r
echo ""
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
  echo "🐳 Criando workflow de teste..."
  cat <<EOF | kubectl create -n argo -f -
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: hello-world-
spec:
  entrypoint: whalesay
  templates:
  - name: whalesay
    container:
      image: docker/whalesay:latest
      command: [cowsay]
      args: ["O Workflow Controller esta rodando 100% no k3d!"]
EOF
  echo "✅ Workflow de teste criado!"
  echo "   Execute: kubectl get workflows -n argo"
  echo ""
else
  echo "ℹ️  Workflow de teste não criado."
  echo ""
fi

echo "================================================"
echo "📝 Próximos passos:"
echo "================================================"
echo ""
echo "1. Configure o Ngrok com seu token:"
echo "   ngrok config add-authtoken SEU_TOKEN_AQUI"
echo ""
echo "2. Inicie o túnel Ngrok:"
echo "   ngrok http 80"
echo ""
echo "3. Acesse a UI do Argo Workflows (em outro terminal):"
echo "   kubectl -n argo port-forward deployment/argo-server 2746:2746"
echo "   Navegador: https://localhost:2746"
echo ""
echo "4. Para criar workflows manualmente:"
echo "   cat <<EOF | kubectl create -n argo -f -"
echo "   apiVersion: argoproj.io/v1alpha1"
echo "   kind: Workflow"
echo "   metadata:"
echo "     generateName: hello-world-"
echo "   spec:"
echo "     entrypoint: whalesay"
echo "     templates:"
echo "     - name: whalesay"
echo "       container:"
echo "         image: docker/whalesay:latest"
echo "         command: [cowsay]"
echo "         args: [\"O Workflow Controller esta rodando 100% no k3d!\"]"
echo "   EOF"
echo ""
echo "================================================"
