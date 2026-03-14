#!/bin/bash

echo "🐳 Criando workflow de teste hello-world..."
echo ""

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

echo ""
echo "✅ Workflow criado com sucesso!"
echo ""
echo "📋 Para ver o workflow:"
echo "   kubectl get workflows -n argo"
echo ""
echo "📋 Para ver os pods:"
echo "   kubectl get pods -n argo"
echo ""
echo "📋 Para ver os logs do workflow (use o nome do pod gerado):"
echo "   kubectl logs -n argo <NOME_DO_POD> -c main"
echo ""
echo "📋 Ou acesse a UI do Argo Workflows:"
echo "   kubectl -n argo port-forward deployment/argo-server 2746:2746"
echo "   Navegador: https://localhost:2746"
echo ""
