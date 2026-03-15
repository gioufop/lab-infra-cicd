# Lab CI/CD - Guia Rápido

Pipeline automatizado de CI/CD com Kubernetes, Argo Workflows e Argo Events.

---

## 📋 Pré-requisitos

```bash
# Ferramentas necessárias
- Docker
- k3d
- kubectl
- Helm
- Ngrok (para webhooks)
```

---

## 🏗️ Arquitetura

### Duas aplicações, dois Ingress Controllers:

```
┌─────────────────────────────────────────────────────────┐
│                    Cluster k3d                          │
│                                                         │
│  ┌──────────────────┐        ┌──────────────────┐       │
│  │   Nginx Ingress  │        │  Istio Gateway   │       │
│  │    (porta 80)    │        │   (porta 8080)   │       │
│  └────────┬─────────┘        └────────┬─────────┘       │
│           │                           │                 │
│    ┌──────▼──────┐             ┌──────▼──────┐          │
│    │   app-a     │             │   app-b     │          │
│    │ namespace   │             │ namespace   │          │
│    │             │             │ (istio-     │          │
│    │             │             │  injection) │          │
│    └─────────────┘             └─────────────┘          │
│                                                         │
│  ┌─────────────────────────────────────────────┐        │
│  │        Argo Workflows + Argo Events         │        │
│  │  (CI/CD pipelines disparados por webhooks)  │        │
│  └─────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────┘
```

### Diferenças:

| App   | Ingress Controller | Porta | URL                      | Namespace      |
|-------|--------------------|-------|--------------------------|----------------|
| app-a | **Nginx Ingress**  | 80    | http://app-a.local       | app-a          |
| app-b | **Istio Gateway**  | 8080  | http://app-b.local:8080  | app-b (istio)  |

---

## 📁 Estrutura e Função dos Arquivos

### 🔧 Scripts de Automação (`cluster-config/`)

| Arquivo | Função |
|---------|--------|
| `setup.sh` | Cria cluster k3d, instala Nginx, Istio, Argo Workflows e Argo Events |
| `setup-secrets.sh` | Configura secrets do GitHub e Docker Hub |
| `deploy-argo-manifests.sh` | Aplica todos os manifestos YAML (EventSources, Sensors, RBACs) |
| `update-ngrok-url.sh` | Atualiza URL do Ngrok no EventSource |
| `validate.sh` | Valida se todos componentes estão funcionando |
| `update-hosts.sh` | Adiciona app-a.local, app-b.local e argoworkflows.local no /etc/hosts |
| `test-workflow.sh` | Cria workflow de teste |

### 📦 Manifestos de Eventos (`argo-events-manifests/`)

| Arquivo | Função |
|---------|--------|
| `github-eventsource.yaml` | Define webhook do GitHub (recebe push events) |
| `eventsource-ingress.yaml` | **Nginx Ingress** que roteia webhooks para Argo Events |

> **Nginx:** EventSource usa Nginx Ingress para receber webhooks do GitHub via Ngrok.

### 🔄 Manifestos de Workflows (`argo-workflow-manifests/`)

| Arquivo | Função | Ingress |
|---------|--------|---------|
| `workflow-deployer-rbac.yaml` | Permissões para workflows executarem |  |
| `sensor-rbac.yaml` | Permissões para sensors criarem workflows |  |
| `argo-server-ingress.yaml` | **Nginx Ingress** para UI do Argo Workflows |  |
| `app-a-sensor.yaml` | Pipeline CI/CD da app-a (clone → test → build → deploy) | **Nginx** |
| `app-b-sensor.yaml` | Pipeline CI/CD da app-b (clone → test → build → deploy) | **Istio** |
| `app-b-istio.yaml` | **Istio Gateway + VirtualService** para app-b (porta 8080) | **Istio** |

### 📄 Documentação

| Arquivo | Conteúdo |
|---------|----------|
| `README.md` | Este arquivo - Guia completo do projeto |
| `Makefile` | Comandos automatizados (make all, make setup, etc.) |

---

## 🚀 Como Executar

### 1. Editar Configurações (ANTES de rodar)

#### GitHub EventSource
Arquivo: `argo-events-manifests/github-eventsource.yaml`
```yaml
owner: "SEU_USUARIO_GITHUB"      # ← Editar
repository: "app-a"              # ou "app-b"
```

#### Docker Hub nos Sensors
Arquivo: `argo-workflow-manifests/app-a-sensor.yaml` (linha ~94)
```yaml
--destination=SEU_USUARIO_DOCKERHUB/app-a:{{workflow.parameters.commit-sha}}
              ^^^^^^^^^^^^^^^^^^^^
```

Arquivo: `argo-workflow-manifests/app-b-sensor.yaml` (linha ~94)
```yaml
--destination=SEU_USUARIO_DOCKERHUB/app-b:{{workflow.parameters.commit-sha}}
              ^^^^^^^^^^^^^^^^^^^^
```

### 2. Executar Setup Completo

```bash
cd lab-infra-cicd

# Setup completo automatizado
make all
```

**O que vai acontecer:**
1. Pergunta nome do cluster (padrão: gio-challenge)
2. Cria cluster k3d com portas 80 e 8080
3. Instala **Nginx Ingress** (porta 80)
4. Instala **Istio** (porta 8080)
5. Instala Argo Workflows e Argo Events
6. Pergunta credenciais GitHub e Docker Hub
7. Aplica todos os manifestos
8. Valida ambiente

**Tempo estimado:** 5-10 minutos

### 3. Configurar Ngrok

```bash
# Em outro terminal, iniciar Ngrok
ngrok http 80

# Voltar ao terminal do projeto
make update-ngrok
```

### 4. Configurar Webhook no GitHub

1. Vá em: `https://github.com/SEU_USUARIO/app-a/settings/hooks`
2. Clique em "Add webhook"
3. Configure:
   - **Payload URL:** `https://SUA_URL_NGROK.ngrok-free.app/github`
   - **Content type:** `application/json`
   - **Events:** Just the push event
4. Salve

Repita para app-b: `https://github.com/SEU_USUARIO/app-b/settings/hooks`

### 5. Testar

```bash
# Monitorar workflows
make watch-workflows

# Fazer push no repositório
cd /caminho/para/app-a  # ou app-b
git commit --allow-empty -m "Test pipeline"
git push origin main

# Ver workflow executar automaticamente!
```

### 6. Acessar Aplicações

```bash
# Adicionar ao /etc/hosts
make update-hosts

# Acessar no navegador:
http://app-a.local           # App-A (Nginx)
http://app-b.local:8080      # App-B (Istio) ← Note a porta 8080!
http://argoworkflows.local   # UI do Argo Workflows (Nginx)
```

---

## 🎯 Comandos Úteis

```bash
# Makefile
make all              # Setup completo
make status           # Status de todos componentes
make validate         # Valida ambiente
make ui               # Mostra como acessar UI do Argo (http://argoworkflows.local)
make watch-workflows  # Monitora workflows
make update-ngrok     # Atualiza URL Ngrok
make destroy          # Deleta cluster

# Kubectl direto
kubectl get workflows -n argo                              # Listar workflows
kubectl logs -n argo <workflow-name> -f                    # Logs de workflow
kubectl get pods -n app-a                                  # Pods da app-a
kubectl get pods -n app-b                                  # Pods da app-b
kubectl get gateway -n app-b                               # Istio Gateway
kubectl get svc -n istio-ingress                           # Istio Ingress Gateway
kubectl get ingress -n ingress-nginx                       # Nginx Ingresses
```

---

## 🔍 Troubleshooting Rápido

### Webhook não dispara workflow
```bash
# Ver logs do EventSource
kubectl logs -n argo-events -l eventsource-name=github -f

# Ver logs do Sensor
kubectl logs -n argo-events -l sensor-name=app-a-sensor -f  # ou app-b-sensor
```

### App-B não acessível em app-b.local:8080
```bash
# Verificar Istio Gateway
kubectl get svc -n istio-ingress
kubectl get gateway -n app-b
kubectl get virtualservice -n app-b

# Deve ter LoadBalancer na porta 8080
```

### URL do Ngrok mudou
```bash
# Atualizar EventSource
make update-ngrok

# Atualizar webhook no GitHub (manualmente)
```

### Validar tudo
```bash
make validate
```

---

## 📊 Fluxo Completo do Pipeline

```
1. Push no GitHub (app-a ou app-b)
         ↓
2. Webhook → Ngrok → Nginx Ingress → EventSource
         ↓
3. Sensor detecta evento
         ↓
4. Cria Workflow (Argo)
         ↓
5. Steps do Workflow:
   - Clone do repositório
   - Executa testes (go test ou pytest)
   - Build da imagem (Kaniko)
   - Push para Docker Hub
   - Deploy no Kubernetes (kubectl apply)
         ↓
6. App atualizado:
   - app-a disponível via Nginx (porta 80)
   - app-b disponível via Istio (porta 8080)
```

---

## 📝 Resumo: Nginx vs Istio

| Componente | Usa Nginx | Usa Istio |
|------------|-----------|-----------|
| EventSource (webhooks) | ✅ | ❌ |
| UI do Argo (argoworkflows.local) | ✅ | ❌ |
| App-A (aplicação) | ✅ | ❌ |
| App-B (aplicação) | ❌ | ✅ |

**Por que essa arquitetura?**
- **App-A:** Usa stack tradicional (Nginx) para demonstrar abordagem clássica
- **App-B:** Usa service mesh (Istio) para demonstrar abordagem moderna
- **Webhooks/UI:** Usam Nginx por simplicidade (não precisam de service mesh)

---

## ✅ Checklist de Setup

- [ ] Editou `owner` e `repository` no `github-eventsource.yaml`
- [ ] Editou usuário Docker Hub em `app-a-sensor.yaml`
- [ ] Editou usuário Docker Hub em `app-b-sensor.yaml`
- [ ] Executou `make all`
- [ ] Ngrok rodando e URL atualizada
- [ ] Webhooks configurados no GitHub
- [ ] Apps acessíveis:
  - [ ] http://app-a.local
  - [ ] http://app-b.local:8080
  - [ ] http://argoworkflows.local
- [ ] Pipeline testado com push
