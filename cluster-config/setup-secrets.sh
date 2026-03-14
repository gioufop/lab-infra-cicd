#!/bin/bash

# Script auxiliar para configurar secrets necessários

set -e

echo "================================================"
echo "Configuração de Secrets - Argo CI/CD"
echo "================================================"
echo ""

# ==================================================
# 1. GitHub Token
# ==================================================
echo "🔐 Configurando GitHub Token..."
echo ""

if kubectl get secret github-secret -n argo-events &>/dev/null; then
  echo "✅ Secret 'github-secret' já existe!"
  read -p "Deseja recriar? (s/N): " -r
  echo ""
  if [[ $REPLY =~ ^[Ss]$ ]]; then
    kubectl delete secret github-secret -n argo-events
  else
    echo "   Mantendo secret existente."
    echo ""
  fi
fi

if ! kubectl get secret github-secret -n argo-events &>/dev/null; then
  echo "ℹ️  O GitHub Personal Access Token precisa ter as seguintes permissões:"
  echo "   - repo (Full control of private repositories)"
  echo "   - admin:repo_hook (Full control of repository hooks)"
  echo ""
  echo "   Crie em: https://github.com/settings/tokens/new"
  echo ""
  
  read -p "Digite seu GitHub Personal Access Token: " -s GITHUB_TOKEN
  echo ""
  
  if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Token não pode ser vazio!"
    exit 1
  fi
  
  kubectl create secret generic github-secret \
    -n argo-events \
    --from-literal=secret="$GITHUB_TOKEN"
  
  echo "✅ Secret 'github-secret' criado com sucesso!"
fi

echo ""

# ==================================================
# 2. Docker Hub Credentials
# ==================================================
echo "🔐 Configurando Docker Hub Credentials..."
echo ""

if kubectl get secret dockerhub-secret -n argo &>/dev/null; then
  echo "✅ Secret 'dockerhub-secret' já existe!"
  read -p "Deseja recriar? (s/N): " -r
  echo ""
  if [[ $REPLY =~ ^[Ss]$ ]]; then
    kubectl delete secret dockerhub-secret -n argo
  else
    echo "   Mantendo secret existente."
    echo ""
  fi
fi

if ! kubectl get secret dockerhub-secret -n argo &>/dev/null; then
  echo "ℹ️  Você precisará do seu username e password do Docker Hub"
  echo "   (ou um Access Token criado em https://hub.docker.com/settings/security)"
  echo ""
  
  read -p "Digite seu Docker Hub username: " DOCKER_USER
  read -p "Digite seu Docker Hub password/token: " -s DOCKER_PASS
  echo ""
  
  if [ -z "$DOCKER_USER" ] || [ -z "$DOCKER_PASS" ]; then
    echo "❌ Username e password não podem ser vazios!"
    exit 1
  fi
  
  kubectl create secret docker-registry dockerhub-secret \
    -n argo \
    --docker-server=https://index.docker.io/v1/ \
    --docker-username="$DOCKER_USER" \
    --docker-password="$DOCKER_PASS"
  
  echo "✅ Secret 'dockerhub-secret' criado com sucesso!"
fi

echo ""

# ==================================================
# Resumo
# ==================================================
echo "================================================"
echo "✨ Configuração de secrets concluída!"
echo "================================================"
echo ""
echo "📋 Secrets criados:"
echo ""
kubectl get secret github-secret -n argo-events 2>/dev/null && echo "   ✅ github-secret (argo-events)" || echo "   ❌ github-secret não encontrado"
kubectl get secret dockerhub-secret -n argo 2>/dev/null && echo "   ✅ dockerhub-secret (argo)" || echo "   ❌ dockerhub-secret não encontrado"
echo ""
echo "📝 Próximo passo:"
echo "   ./deploy-argo-manifests.sh"
echo ""
