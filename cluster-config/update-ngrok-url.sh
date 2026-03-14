#!/bin/bash

# Script para atualizar a URL do Ngrok no EventSource

set -e

echo "🌐 Atualização da URL do Ngrok"
echo ""

# Obtém a URL atual do arquivo (ignora linhas comentadas)
CURRENT_URL=$(grep -v '^\s*#' ../argo-events-manifests/github-eventsource.yaml | grep -oP 'url: "\K[^"]+' | head -1)

echo "ℹ️  URL atual no EventSource: $CURRENT_URL"
echo ""

# Tenta obter a URL do Ngrok se estiver rodando
if curl -s http://localhost:4040/api/tunnels &>/dev/null; then
  NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | grep -oP '"public_url":"https://\K[^"]*' | head -1)
  if [ -n "$NGROK_URL" ]; then
    echo "✅ Ngrok detectado rodando!"
    echo "   URL atual do Ngrok: https://$NGROK_URL"
    echo ""
    read -p "Usar esta URL? (S/n): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      NEW_URL="https://$NGROK_URL"
    fi
  fi
fi

# Se não detectou ou usuário escolheu não usar
if [ -z "$NEW_URL" ]; then
  echo ""
  echo "📋 Para obter a URL do Ngrok:"
  echo "   1. Abra um OUTRO terminal"
  echo "   2. Execute o comando: ngrok http 80"
  echo "   3. Copie e cole a URL gerada (ex: https://abc-123.ngrok-free.app)"
  echo ""
  read -p "Digite a nova URL do Ngrok (ex: https://abc123.ngrok-free.app): " NEW_URL
  
  if [ -z "$NEW_URL" ]; then
    echo "❌ URL não pode ser vazia!"
    exit 1
  fi
  
  # Remove trailing slash se existir
  NEW_URL="${NEW_URL%/}"
  
  # Valida formato básico da URL
  if [[ ! "$NEW_URL" =~ ^https:// ]]; then
    echo "❌ URL deve começar com https://"
    exit 1
  fi
fi

echo ""
echo "🔄 Atualizando EventSource..."
echo "   De: $CURRENT_URL"
echo "   Para: $NEW_URL"
echo ""

# Cria backup
BACKUP_FILE="../argo-events-manifests/github-eventsource.yaml.backup-$(date +%Y%m%d-%H%M%S)"
cp ../argo-events-manifests/github-eventsource.yaml "$BACKUP_FILE"
echo "📦 Backup criado: $(basename "$BACKUP_FILE")"

# Atualiza o arquivo usando delimitador # no sed para evitar conflito com / nas URLs
sed -i "s#url: \"[^\"]*\"#url: \"$NEW_URL\"#g" ../argo-events-manifests/github-eventsource.yaml

echo "✅ Arquivo atualizado!"
echo ""

# Pergunta se quer aplicar
read -p "Deseja aplicar a mudança no cluster? (S/n): " -r
echo ""
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
  kubectl apply -f ../argo-events-manifests/github-eventsource.yaml
  echo "✅ EventSource atualizado no cluster!"
  echo ""
  echo "⏳ Aguardando pods reiniciarem..."
  sleep 5
  kubectl get pods -n argo-events -l eventsource-name=github
else
  echo "ℹ️  Para aplicar manualmente:"
  echo "   kubectl apply -f ../argo-events-manifests/github-eventsource.yaml"
fi

echo ""
echo "📝 Lembre-se de atualizar o webhook no GitHub também:"
echo "   https://github.com/SEU_USUARIO/app-a/settings/hooks"
echo "   Payload URL: $NEW_URL/github"
echo ""
