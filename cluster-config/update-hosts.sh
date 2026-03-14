#!/bin/bash

set -e

echo "================================================"
echo "Script de Atualização do /etc/hosts"
echo "================================================"
echo ""

# Verificar se está rodando como root ou com sudo
if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  Este script precisa de permissões sudo"
    echo "Execute com: sudo ./update-hosts.sh"
    exit 1
fi

echo "🔍 Verificando entradas existentes no /etc/hosts..."
echo ""

# Backup do /etc/hosts
BACKUP_FILE="/etc/hosts.backup.$(date +%Y%m%d_%H%M%S)"
cp /etc/hosts "$BACKUP_FILE"
echo "✅ Backup criado: $BACKUP_FILE"
echo ""

# Entradas necessárias
ENTRIES=(
    "127.0.0.1 app-a.local"
    "127.0.0.1 app-b.local"
    "127.0.0.1 argoworkflows.local"
)

# Adicionar cada entrada se não existir
for entry in "${ENTRIES[@]}"; do
    hostname=$(echo "$entry" | awk '{print $2}')
    
    if grep -q "$hostname" /etc/hosts; then
        echo "✓ $hostname já existe no /etc/hosts"
    else
        echo "$entry" >> /etc/hosts
        echo "✅ Adicionado: $entry"
    fi
done

echo ""
echo "================================================"
echo "Configuração do /etc/hosts concluída!"
echo "================================================"
echo ""
echo "📝 Entradas atuais relacionadas ao projeto:"
grep -E "app-a.local|app-b.local|argoworkflows.local" /etc/hosts || true
echo ""
echo "🎯 URLs de Acesso:"
echo "   - App-A (Nginx):  http://app-a.local"
echo "   - App-B (Istio):  http://app-b.local:8080"
echo "   - Argo UI:        http://argoworkflows.local"
echo ""
