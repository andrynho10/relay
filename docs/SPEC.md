# Relay — Especificación del sistema

Versión 0.1 · Estado: borrador para iniciar Fase 0

---

## 1. Visión

Relay es un SaaS B2B multi-tenant que reduce el costo de atención al cliente. Cada empresa cliente
(tenant) carga su documentación y conecta sus canales; un agente basado en Claude responde consultas
con citas a la fuente, clasifica y prioriza tickets, y ejecuta acciones (ej. reembolso, cambio de plan,
escalamiento) bajo políticas y aprobación humana.

Objetivo del proyecto: demostrar capacidad de construir un sistema con IA **rentable, seguro,
escalable y confiable**, con evidencia medible (métricas, tests, documentos de diseño).

### No-objetivos (para controlar el alcance)
- No es un chatbot genérico ni un wrapper de chat.
- No entrena ni hace fine-tuning de modelos.
- No aloja modelos propios (ver ADR-0003: se descarta el LLM local).
- No busca certificación formal (SOC 2 / ISO 27001 certifican organizaciones, no proyectos);
  sí busca **alineación demostrable** con esos marcos y con OWASP.

---

## 2. Modelo de negocio y economía unitaria

### Propuesta de valor
Una resolución humana de un ticket cuesta varios dólares en tiempo de personal; una resolución
automatizada debe costar centavos. Relay cobra por resultado, no por asiento.

### Modelo de precios (hipótesis a validar con datos del propio sistema)
- Plan base mensual por tenant (incluye N resoluciones).
- Cobro por **resolución automatizada** adicional (medida vía Stripe Billing con medidores de uso).
- Las conversaciones derivadas a humano no se cobran como resolución.

### Economía unitaria objetivo
Estimación inicial con precios de lista vigentes (oct 2026, verificar en la documentación oficial
de Anthropic antes de usar):

| Concepto por llamada (Sonnet 5.5) | Tokens | Costo aprox. |
|---|---|---|
| Prompt fijo en caché (cache hit) | 3.000 | $0,0003 |
| Contexto variable (documentos + conversación) | 5.000 | $0,0100 |
| Salida | 500 | $0,0050 |
| **Total por llamada** | | **~$0,015** |

Con ~3 llamadas por ticket: **~$0,05 en LLM por resolución**. Clasificación con Haiku 5.5: despreciable.

Metas medibles (se reportan en el dashboard de costos, §8):
- Costo LLM por resolución ≤ $0,06
- Costo total (LLM + infraestructura prorrateada) por resolución ≤ $0,10 a 10.000 tickets/mes
- Margen bruto objetivo ≥ 80% al precio de referencia
- ≥ 50% del tráfico atendido por el modelo más barato sin regresión en evals

Palancas de costo: enrutamiento por dificultad, prompt caching, Batch API (−50%) para trabajo
no urgente (resúmenes, evals), caché semántico propio, contexto recuperado acotado.

---

## 3. Usuarios y roles

| Rol | Ámbito | Puede |
|---|---|---|
| Platform admin | Global (solo operador) | Gestionar tenants, ver métricas agregadas. Sin acceso a contenido de tenants por defecto |
| Tenant owner | Su tenant | Facturación, SSO, usuarios, políticas del agente |
| Tenant admin | Su tenant | Documentos, herramientas, aprobaciones, configuración |
| Support agent | Su tenant | Ver/atender tickets, aprobar acciones dentro de su límite |
| Viewer | Su tenant | Solo lectura de tickets y métricas |
| End customer | Conversación propia | Chatear vía widget; sin cuenta o con identidad verificada por el tenant |

---

## 4. Funcionalidades por módulo

**4.1 Ingesta de conocimiento.** Subida de PDF/DOCX/MD/HTML a S3 con URL prefirmada → evento → SQS →
worker: validación de tipo y tamaño, escaneo, extracción de texto, **redacción de PII**, chunking,
embeddings, indexación en pgvector con `tenant_id`. Versionado de documentos y reindexado.

**4.2 Conversación (RAG).** Widget embebible + API. Respuestas en streaming (SSE). Toda respuesta
cita fragmentos fuente; si no hay respaldo suficiente, el agente lo dice y ofrece derivar a humano.

**4.3 Triage.** Clasificación de intención, urgencia, idioma y sentimiento (Haiku). Reglas de
enrutamiento configurables por tenant.

**4.4 Agente con herramientas.** Herramientas definidas por esquema (ej. `lookup_order`,
`issue_refund`, `change_plan`, `escalate_to_human`). Cada herramienta declara: permisos requeridos,
nivel de riesgo, límites (montos, frecuencia), si requiere aprobación humana. El backend valida
todo; el modelo solo propone.

**4.5 Bandeja de aprobaciones.** Cola de acciones pendientes con contexto, razonamiento resumido y
botones aprobar/rechazar. Expiración automática.

**4.6 Servidor MCP.** Las herramientas de Relay se exponen también como servidor MCP autenticado
por tenant, para que otros agentes las consuman.

**4.7 Facturación.** Stripe Billing en modo test: suscripción + medidor de resoluciones. Webhooks
idempotentes y verificados por firma.

**4.8 Panel de métricas.** Por tenant: volumen, tasa de resolución automática, CSAT simulado,
costo por resolución, latencia. Para el operador: margen, costo por modelo, salud del sistema.

**4.9 Administración y auditoría.** Gestión de usuarios (SSO/SCIM vía WorkOS), log de auditoría
inmutable, exportación y borrado completo de datos del tenant.

---

## 5. Arquitectura

```
Clientes (widget, panel web)
        │ HTTPS
   CloudFront + AWS WAF (reglas gestionadas, rate limiting)
        │
   ALB ──► web (Next.js, ECS Fargate)
        └► api (FastAPI, ECS Fargate, sin estado, autoescalado)
               │            │             │
               │            │             └─► LLMGateway ─► Claude API
               │            │                 (routing, caching, costos, timeouts, fallback)
               │            └─► Redis (rate limits, caché semántico, sesiones de streaming)
               └─► PostgreSQL + pgvector (RDS, RLS, cifrado KMS)
                         ▲
   S3 (documentos) ─evento─► SQS ─► worker (ECS Fargate): parse, PII, chunk, embed
                                     └─► DLQ + alarmas
   Telemetría: OpenTelemetry → backend de observabilidad; Sentry; Langfuse (trazas LLM)
   Secretos: Secrets Manager + KMS · Identidad: WorkOS · Billing: Stripe
```

Principios: servicios sin estado, trabajo pesado asíncrono, idempotencia, fallar de forma segura,
un solo proveedor cloud bien usado en vez de muchos mal usados.

---

## 6. Proveedores y justificación empresarial

Criterio de selección: lo que una empresa B2B exigiría (seguridad, cumplimiento del proveedor,
soporte, estándar de industria) con costo justificable por la economía unitaria. Cada elección
tiene su ADR con alternativas descartadas.

| Necesidad | Elección | Por qué (resumen) | Alternativa considerada |
|---|---|---|---|
| Cloud | **AWS** | Mayor adopción en startups y mercado laboral; servicios gestionados maduros; IAM granular | GCP |
| Cómputo | **ECS Fargate** | Sin servidores que parchar; autoescalado; costo y complejidad razonables para equipo pequeño | EKS (descartado: costo fijo del control plane y carga operativa sin beneficio a esta escala) |
| Base de datos | **RDS PostgreSQL + pgvector** | Una sola base para datos y vectores ⇒ RLS protege también la búsqueda vectorial; backups gestionados | Base vectorial dedicada (descartada: otro proveedor, otra superficie de aislamiento) |
| Colas | **SQS + DLQ** | Gestionado, durable, barato, integra con eventos de S3 | Kafka/MSK (sobredimensionado) |
| Caché | **ElastiCache (Valkey/Redis)** | Rate limiting y caché semántico | — |
| Almacenamiento | **S3** (SSE-KMS, Block Public Access, versionado) | Estándar | — |
| Borde | **CloudFront + AWS WAF** | Protección DDoS/OWASP gestionada, rate limiting en el borde | — |
| Secretos/llaves | **Secrets Manager + KMS** | Rotación, auditoría en CloudTrail | — |
| LLM | **Claude API (Anthropic)** detrás de `LLMGateway` | Acceso inmediato a modelos y funciones nuevas (prompt caching, batch); el gateway permite cambiar a Amazon Bedrock o Claude Platform on AWS si un cliente exige facturación o residencia en AWS (ADR) | Bedrock |
| Embeddings | Modelo multilingüe vía **Amazon Bedrock** (p. ej. Cohere Embed) detrás de `Embedder` | Datos permanecen en la cuenta AWS, auth por IAM, buen desempeño en español | Voyage AI (ADR comparativo con evals propios) |
| PII | **Microsoft Presidio** + reconocedores propios | Determinístico, auditable, testeable, open source | LLM para redacción (descartado) |
| Identidad | **WorkOS** | SSO SAML/OIDC y SCIM: requisito típico de clientes empresariales | Amazon Cognito |
| Facturación | **Stripe Billing** (medidores de uso) | Estándar de industria para SaaS por uso | — |
| Observabilidad | **OpenTelemetry** + Grafana Cloud, **Sentry**, **Langfuse** | OTel evita dependencia de proveedor; Langfuse especializado en trazas y costos LLM | Datadog (mejor integrado, costo alto para esta etapa) |
| IaC | **Terraform** (estado remoto en S3 con bloqueo) | Estándar más pedido | CDK |
| CI/CD | **GitHub Actions** + OIDC | Sin credenciales de larga duración; entornos con aprobación | — |
| Email transaccional | **Amazon SES** | Dentro de AWS | — |

Nota: verificar versiones, disponibilidad regional y precios vigentes de cada servicio al redactar
el ADR correspondiente. Región AWS: elegir según clientes objetivo y documentar en ADR.

---

## 7. Seguridad

Marcos de referencia:
- OWASP Top 10 for LLM Applications 2026 y OWASP Top 10 for Agentic Applications
- OWASP ASVS nivel 2 (aplicación web/API) y OWASP Top 10
- Controles inspirados en SOC 2 / ISO 27001 aplicables a un sistema (no a la organización)

Entregables obligatorios:
- `docs/security/threat-model.md` (STRIDE por componente y por flujo de datos), actualizado por fase.
- `docs/security/owasp-mapping.md`: cada riesgo OWASP LLM/Agentic → mitigación → test que la verifica.
- Suite `make redteam` en CI que bloquea el merge si falla.

Controles mínimos:
- **Aislamiento de tenants:** RLS en todas las tablas con datos de tenant (incluido pgvector);
  `tenant_id` fijado por sesión de DB desde el token, nunca desde el request body. Tests de acceso
  cruzado automatizados.
- **AuthN/AuthZ:** SSO vía WorkOS, MFA, RBAC; autorización explícita por endpoint; denegar por defecto.
- **Prompt injection:** separación de instrucciones y datos; documentos y mensajes tratados como no
  confiables; herramientas con permisos mínimos; validación de argumentos en backend; aprobación humana
  en acciones sensibles; límites por conversación. Corpus de ataques versionado en `evals/redteam/`.
- **Salida del LLM:** validación por esquema; sanitización antes de renderizar (XSS); nunca SQL/código
  construido desde salida del modelo.
- **Consumo sin límites:** rate limiting por IP, usuario y tenant (WAF + Redis); tope de tokens por
  conversación y por tenant; alertas de gasto.
- **Datos:** TLS 1.2+ en tránsito, cifrado KMS en reposo, PII redactada antes de proveedores y logs.
- **Supply chain:** lockfiles, Dependabot, escaneo SAST (CodeQL/Semgrep), secretos (gitleaks),
  contenedores (Trivy), IaC (Checkov), imágenes base mínimas y no-root, SBOM en el build.
- **DAST:** OWASP ZAP baseline contra staging en el pipeline.
- **Infra:** IAM de mínimo privilegio por servicio, subredes privadas para datos, security groups
  restrictivos, CloudTrail y GuardDuty activos, sin acceso SSH (ECS Exec auditado si se necesita).
- **Auditoría:** log append-only de acciones de usuarios y del agente (quién, qué, cuándo, resultado).

---

## 8. Confiabilidad, escalabilidad y observabilidad

SLOs iniciales (medidos, con error budget):
- Disponibilidad API: 99,9% mensual
- Latencia hasta el primer token: p95 ≤ 2 s; respuesta completa p95 ≤ 8 s
- Ingesta: documento de 50 páginas indexado p95 ≤ 2 min

Resiliencia:
- Timeouts, reintentos con backoff exponencial y jitter, circuit breaker en `LLMGateway`.
- Degradación: si el LLM no responde, el ticket se deriva a humano con mensaje claro.
- Workers idempotentes; DLQ con alarma y procedimiento de reproceso.
- Backups automáticos de RDS con PITR; **restauración probada y documentada** (`docs/runbooks/restore.md`).
- Multi-AZ documentado para producción; staging puede ser single-AZ para controlar costo.

Escalabilidad:
- API y workers sin estado con autoescalado por CPU/cola.
- Prueba de carga con k6: reportar throughput máximo, punto de quiebre y cuello de botella.

Observabilidad:
- Trazas distribuidas OTel de punta a punta (request → recuperación → LLM → herramienta).
- Por llamada LLM: modelo, tokens in/out/cache, costo, latencia, tenant.
- Dashboards: salud, SLOs, costo por resolución, costo por tenant, tasa de derivación a humano.
- Alertas accionables con runbook enlazado (`docs/runbooks/`).

---

## 9. Calidad de IA (evals)

- Dataset dorado versionado en `evals/datasets/` (≥ 150 casos, incluye español e inglés, casos sin
  respuesta en la documentación, y casos adversariales).
- Métricas: exactitud de respuesta, fidelidad a la fuente (sin alucinación), calidad de citas,
  exactitud de triage, uso correcto de herramientas, tasa de derivación apropiada.
- Evaluación por reglas + LLM-as-judge con rúbrica explícita; muestreo de revisión humana.
- En CI: cualquier cambio de prompt, modelo, chunking o recuperación corre los evals; regresión
  mayor al umbral bloquea el merge. Resultados publicados como artefacto.
- Evals en batch (Batch API) para reducir su costo.

---

## 10. Fases y criterios de aceptación

Cada fase termina con: tests verdes, evals sin regresión, docs actualizadas, demo grabable.

**Fase 0 — Fundaciones**
Monorepo, flujo de git de §13 (ruleset de `main`, plantilla de PR, CODEOWNERS, pre-commit,
release-please), Docker Compose local, CI (lint, tipos, tests, escaneos de seguridad), esqueleto Terraform,
ADRs iniciales (0001 registro de ADRs, 0002 cloud, 0003 sin LLM local, 0004 base de datos/vectores,
0005 cómputo), threat model v1, plantilla de README.
✔ `make dev` y `make check` funcionan desde cero en una máquina limpia.
✔ **Walking skeleton:** un endpoint `/health` y una página mínima desplegados en staging en AWS
  vía Terraform y GitHub Actions con OIDC. La Fase 5 endurece la producción; no es el primer
  despliegue. Así los problemas de infraestructura aparecen temprano y no al final.

**Fase 1 — Núcleo RAG (un tenant)**
Ingesta asíncrona con PII, búsqueda vectorial, chat con streaming y citas, `LLMGateway` con registro
de costos, dataset de evals v1 en CI.
✔ Evals base publicados; costo y latencia por respuesta visibles.

**Fase 2 — Multi-tenancy y seguridad de acceso**
WorkOS, RBAC, RLS en todas las tablas, auditoría, suite de acceso cruzado.
✔ Ningún test de acceso cruzado logra leer datos de otro tenant (incluido vía búsqueda vectorial).

**Fase 3 — Agente y acciones**
Herramientas con esquema y política, bandeja de aprobaciones, límites, servidor MCP, suite red team
y `owasp-mapping.md`.
✔ 100% de los ataques del corpus bloqueados o contenidos; ninguna acción sensible sin aprobación.

**Fase 4 — Economía**
Enrutamiento Haiku/Sonnet/Opus guiado por evals, prompt caching, caché semántico, Stripe con
medidores, dashboard de costos y margen.
✔ Metas de §2 medidas y reportadas (cumplidas o con análisis de brecha).

**Fase 5 — Producción en AWS**
Despliegue Terraform a staging y producción, WAF, SLOs y alertas, runbooks, prueba de restauración,
k6, ZAP, auditoría de accesibilidad.
✔ Informe de carga publicado; restauración probada; SLO dashboard en verde por 7 días.

**Fase 6 — Portafolio**
Demo pública con límites estrictos, video de 3 min, README con diagrama, caso de estudio con
métricas, al menos un postmortem real.

---

## 11. Control de costos del propio proyecto

- AWS Budgets con alertas; límites de gasto en la consola de Anthropic.
- Entornos no productivos efímeros (`terraform destroy` cuando no se usan).
- Demo pública con Haiku, rate limiting estricto y tope diario global.
- Reportar en el README el costo mensual real de operar el sistema.

---

## 12. Decisiones abiertas (resolver en Fase 0 con ADR)

- Región AWS principal.
- Proveedor de embeddings final (comparar con evals propios).
- Backend de observabilidad (Grafana Cloud vs alternativa).
- Langfuse cloud vs auto-alojado.
- Nombre definitivo del producto y dominio.

---

## 13. Versionado y flujo de trabajo

Plataforma: **GitHub** (repositorio, PRs, Actions, Dependabot, escaneo de código y de secretos).

### Flujo de ramas: trunk-based
- `main` siempre desplegable. Ramas cortas por tarea: `feat/…`, `fix/…`, `chore/…`, `docs/…`.
- Todo cambio entra por **Pull Request** con plantilla (qué, por qué, cómo se probó, riesgos de
  seguridad, impacto en costo/evals). Merge por squash; el título del PR sigue Conventional Commits.
- Aunque el equipo sea de una persona, el PR es obligatorio: deja historial revisable y el CI actúa
  como revisor. Claude Code puede abrir el PR; la persona lo revisa y lo aprueba.

### Protección de `main` (ruleset de GitHub)
- Sin push directo; requiere PR con todos los checks verdes (lint, tipos, tests, evals, red team,
  escaneos de seguridad).
- Historial lineal, commits firmados (SSH o GPG), sin force-push, conversaciones resueltas.
- `CODEOWNERS` para rutas sensibles (`infra/`, `apps/api/auth`, `apps/api/agent`, migraciones).

### Releases
- **SemVer** (`v0.x.y` durante el desarrollo; `v1.0.0` al cerrar Fase 5).
- Tags por fase: `v0.1.0` = Fase 0, `v0.2.0` = Fase 1, etc.
- `CHANGELOG.md` generado desde los commits (release-please o equivalente) y GitHub Releases.
- Imágenes de contenedor etiquetadas con el SHA del commit y la versión; nunca `latest` en entornos.
- Despliegue: merge a `main` → staging automático; producción desde un release con aprobación
  manual en GitHub Environments.

### Qué más se versiona (y cómo)
| Artefacto | Mecanismo |
|---|---|
| Esquema de base de datos | Migraciones Alembic numeradas y reversibles |
| Infraestructura | Terraform en el repo; estado remoto en S3 con bloqueo; `plan` visible en cada PR |
| API pública | Prefijo `/v1`; cambios incompatibles solo en nueva versión; OpenAPI versionado en el repo |
| Prompts del sistema | Archivos en `apps/api/prompts/` con versión explícita; cada respuesta registra la versión usada |
| Modelos LLM | IDs fijados en configuración, nunca alias implícitos; cambio de modelo = PR con evals |
| Datasets de evals y red team | En `evals/` dentro del repo; cambios por PR con justificación |
| Decisiones | ADRs numerados e inmutables (se reemplazan con uno nuevo, no se editan) |
| Documentos de tenants | Versionado de documentos y de su índice en la aplicación (§4.1) |

### Desarrollo asistido por agente (Claude Code)
- **Cuentas AWS separadas** (AWS Organizations): `dev`, `staging`, `prod`. La máquina de desarrollo
  y el agente solo tienen credenciales de `dev`, con SSO y sesiones temporales. `staging` y `prod`
  solo se tocan desde GitHub Actions con OIDC.
- **Permisos del agente** versionados en `.claude/settings.json`: denegar lectura de `.env*` y
  secretos, `git push --force`, `terraform apply`/`destroy` fuera de `dev`, y comandos destructivos.
- **Hooks deterministas** (opcional, recomendado): formatear y lintear tras cada edición, para no
  depender de que el agente lo recuerde.
- `docs/BACKLOG.md` recoge todo lo que se sale del plan; se revisa al cerrar cada fase.
- Revisión semanal: comparar avance real vs. plan, recortar alcance si hace falta.

### Higiene
- `.gitignore` y `.dockerignore` estrictos; pre-commit con gitleaks, ruff y formateo.
- Escaneo de secretos con push protection activado en GitHub.
- Nada generado (builds, `.env`, estado de Terraform) entra al repo.
