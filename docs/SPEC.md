# Relay — Especificación del sistema

Versión 0.3 · Estado: Fase 0 · Organizada en hitos de CV y presupuesto de USD 50/mes el 2026-10-13 (ver §10.0, §11 y ADR-0007)

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
| Identidad | **WorkOS** | SSO SAML/OIDC y SCIM: requisito típico de clientes empresariales. Prioridad 1: AuthKit en plan gratuito (verificar en la página de precios de WorkOS al iniciar Fase 2); SSO/SCIM en el entorno staging de WorkOS: Prioridad 2, E2 (§10.0) | Amazon Cognito |
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
  Prioridad 1: los riesgos cubiertos por la prioridad 1; mapeo completo en Prioridad 2.
- Suite `make redteam` en CI que bloquea el merge si falla. Prioridad 1: acceso cruzado entre tenants
  (incluida búsqueda vectorial) + corpus pequeño de prompt injection; corpus completo en Prioridad 2.

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
- **Supply chain:** lockfiles, Dependabot, escaneo SAST (CodeQL), secretos (gitleaks),
  contenedores y dependencias (Trivy), imágenes base mínimas y no-root.
  *Prioridad 2:* Semgrep, Checkov (IaC), SBOM en el build.
- **DAST** *(Prioridad 2)*: OWASP ZAP baseline contra staging en el pipeline.
- **Infra:** IAM de mínimo privilegio por servicio, subredes privadas para datos, security groups
  restrictivos, CloudTrail activo, sin acceso SSH (ECS Exec auditado si se necesita).
  *Prioridad 2:* GuardDuty (tiene costo y no está disponible en los proyectos del plan pago sin
  funciones avanzadas).
- **Auditoría:** log append-only de acciones de usuarios y del agente (quién, qué, cuándo, resultado).

---

## 8. Confiabilidad, escalabilidad y observabilidad

SLO de prioridad 1 (medido en cada demo de staging y en los evals):
- Latencia hasta el primer token: p95 ≤ 2 s.

*Prioridad 2* (se miden en una ventana de 7 días con staging encendido, ~USD 15–20 una sola vez):
- Disponibilidad API: 99,9 % mensual con error budget.
- Respuesta completa p95 ≤ 8 s; ingesta de un documento de 50 páginas p95 ≤ 2 min.

Resiliencia:
- Timeouts, reintentos con backoff exponencial y jitter, circuit breaker en `LLMGateway`.
- Degradación: si el LLM no responde, el ticket se deriva a humano con mensaje claro.
- Workers idempotentes; DLQ con alarma y procedimiento de reproceso.
- Backups automáticos de RDS con PITR; **restauración probada y documentada** (`docs/runbooks/restore.md`).
- Multi-AZ documentado para producción; staging puede ser single-AZ para controlar costo.

Escalabilidad:
- API y workers sin estado con autoescalado por CPU/cola.
- *(Prioridad 2)* Prueba de carga con k6: reportar throughput máximo, punto de quiebre y cuello de botella.

Observabilidad (prioridad 1; cabe en los planes gratuitos de Grafana Cloud y Langfuse, a verificar en sus ADRs):
- Trazas distribuidas OTel de punta a punta (request → recuperación → LLM → herramienta).
- Trazas LLM en Langfuse. Por llamada: modelo, tokens in/out/cache, costo, latencia, tenant.
- Un dashboard: latencia (TTFT p95), costo por respuesta y por tenant, tasa de derivación a humano.
- Una alerta accionable con su runbook enlazado (`docs/runbooks/`).
- *Prioridad 2:* dashboards de SLO de disponibilidad y error budget, alertas adicionales.

---

## 9. Calidad de IA (evals)

- Dataset dorado versionado en `evals/datasets/`: ~50 casos en la v1 (Fase 1), creciendo hasta ≥ 150.
  Incluye español e inglés, casos sin respuesta en la documentación y casos adversariales.
- Métricas: exactitud de respuesta, fidelidad a la fuente (sin alucinación), calidad de citas,
  exactitud de triage, uso correcto de herramientas, tasa de derivación apropiada.
- Evaluación por reglas + LLM-as-judge con rúbrica explícita; muestreo de revisión humana, que también
  sirve para calibrar al juez.
- Dos niveles, porque la Batch API puede tardar hasta 24 h y no sirve para bloquear un merge:
  - **En PR (bloqueante):** subconjunto chico y síncrono, con Haiku como juez, solo en los PRs que
    tocan prompts, modelos, chunking o recuperación. Regresión mayor al umbral bloquea el merge.
  - **Suite completa:** por Batch API (−50 %), manual o semanal. Resultados publicados como artefacto.
- Cada corrida registra su costo; el costo de los evals se reporta junto al del sistema.

---

## 10. Fases, hitos y criterios de aceptación

Cada fase termina con: tests verdes, evals sin regresión, docs actualizadas, demo grabable.

### 10.0 Hitos de CV: terminar algo demostrable y luego escalar

Objetivo: demostrar amplitud (IA, cloud, CI/CD, seguridad, observabilidad) con un estándar mínimo de
producción y pocos dólares al mes (§11, ADR-0007), y tener algo mostrable en el CV lo antes posible.

Filosofía:
- El trabajo se organiza en **hitos**. Cada hito deja algo publicable: release etiquetado, sección del
  README actualizada, video o GIF corto (≤ 90 s) de la demo en staging, y costo real medido.
- **Prioridad 1** son los hitos, en orden. **Prioridad 2** son extensiones independientes que agrandan
  lo ya demostrable; ninguna se empieza mientras el hito en curso no esté cerrado.
- El hito 1 ya es postulable. Los hitos 2 y 3 cubren lo que más pesa para un CTO de SaaS B2B con IA
  (aislamiento entre tenants y agentes seguros); son la meta mínima del proyecto.
- Desde el hito 1, las tablas de datos llevan `tenant_id`, para que el hito 2 agregue RLS sin rehacer
  el esquema.

**Prioridad 1 — hitos**

| Hito | Fases | Qué se puede mostrar | Release |
|---|---|---|---|
| 1. RAG demostrable | 0 + 1 | Subir documentos, preguntar y recibir respuestas en streaming con citas; costo y TTFT por respuesta; trazas en Langfuse; evals bloqueando en CI; deploy a staging con OIDC | `v0.2.0` |
| 2. SaaS multi-tenant seguro | 2 | Login con WorkOS AuthKit, RBAC, RLS (incluida búsqueda vectorial), auditoría, suite de acceso cruzado en CI | `v0.3.0` |
| 3. Agente con aprobación humana | 3 | Triage con salidas estructuradas, `issue_refund` con política y límites, bandeja de aprobaciones, red team mínimo en CI | `v0.4.0` |
| 4. Economía medida | 4 | Enrutamiento Haiku/Sonnet/Opus guiado por evals, prompt caching, dashboard de costo por resolución | `v0.5.0` |
| 5. Operación | 5 + 6 | Alerta con runbook, restauración probada, auditoría de accesibilidad, costo real, caso de estudio y postmortem | `v1.0.0` |

**Prioridad 2 — escalar** (orden sugerido por valor para el CV y costo; se elige al cerrar cada hito)

| Extensión | Contenido | Costo estimado (a verificar al implementar) |
|---|---|---|
| E1. Cadena de suministro | Semgrep, Checkov, SBOM, release-please | USD 0 (Actions gratis en repo público) |
| E2. Identidad empresarial | WorkOS SSO/SCIM en el entorno *staging* de WorkOS | USD 0 (conexiones de staging no se cobran) |
| E3. Endurecimiento de staging | WAF, GuardDuty, RDS Multi-AZ como interruptores de Terraform; ZAP | Centavos por hora, solo con staging encendido; GuardDuty con prueba gratuita |
| E4. Agente ampliado | Servidor MCP, más herramientas, red team completo, `owasp-mapping.md` completo | Centavos de API (Haiku como atacante y juez) |
| E5. Facturación | Stripe Billing en modo test con medidores; margen sobre facturación | USD 0 |
| E6. Carga y confiabilidad | k6; SLO de disponibilidad en una ventana de 7 días | ~USD 15–20, una sola vez |
| E7. Caché semántico | Caché por similitud en Valkey | USD 0 local; centavos por hora en staging |
| E8. Demo pública | Demo abierta con Haiku, límites estrictos y tope diario | Solo si el presupuesto de §11 lo permite |

Fuera de alcance: producción aplicada. Existe en Terraform y se valida en CI; aplicarla duplicaría el
costo sin demostrar nada que staging no demuestre.

**Fase 0 — Fundaciones** *(hito 1)*
Monorepo, flujo de git de §13 (ruleset de `main`, plantilla de PR, CODEOWNERS, pre-commit),
devcontainer y Docker Compose local, CI (lint, tipos, tests, gitleaks, CodeQL, Trivy, Dependabot),
Terraform para `dev`, `staging` y `prod` (este último solo validado), ADRs iniciales, threat model v1,
plantilla de README.
✔ `make dev` y `make check` funcionan desde cero en una máquina limpia.
✔ **Walking skeleton:** un endpoint `/health` y una página mínima desplegados en staging en AWS
  vía Terraform y GitHub Actions con OIDC, por despliegue manual, con destroy probado.
  Así los problemas de infraestructura aparecen temprano y no al final.

**Fase 1 — Núcleo RAG, un tenant** *(hito 1)*
Ingesta asíncrona con PII, búsqueda vectorial, chat con streaming y citas, `LLMGateway` con registro
de costos, dataset de evals v1 (~50 casos) con subconjunto bloqueante en CI, trazas OTel de punta a
punta, trazas LLM en Langfuse, dashboard de latencia y costo.
✔ Evals base publicados; costo y TTFT por respuesta visibles en el dashboard y en Langfuse.
✔ Cierre del hito 1: release `v0.2.0`, README con la demo y su costo real.

**Fase 2 — Multi-tenancy y seguridad de acceso** *(hito 2)*
WorkOS AuthKit, RBAC, RLS en todas las tablas, auditoría, suite de acceso cruzado.
✔ Ningún test de acceso cruzado logra leer datos de otro tenant (incluido vía búsqueda vectorial).

**Fase 3 — Agente, triage y acciones** *(hito 3)*
Triage con salidas estructuradas (Haiku), herramienta `issue_refund` con esquema y política, bandeja
de aprobaciones, límites, red team mínimo (acceso cruzado + corpus pequeño de prompt injection).
✔ 100 % de los ataques del corpus mínimo bloqueados o contenidos; ninguna acción sensible sin aprobación.

**Fase 4 — Economía** *(hito 4)*
Enrutamiento Haiku/Sonnet/Opus guiado por evals, prompt caching, dashboard de costos.
✔ Costo por resolución y reparto de tráfico por modelo medidos y reportados (cumplidos o con análisis de brecha).

**Fase 5 — Operación** *(hito 5)*
Staging completo aplicable bajo demanda, una alerta accionable con su runbook, prueba de restauración,
auditoría de accesibilidad, costo real medido (en reposo y por hora encendido).
✔ Restauración probada; alerta disparada y resuelta con su runbook en una demo; TTFT p95 medido;
  despliegue y destroy de staging documentados y repetibles.

**Fase 6 — Portafolio** *(hito 5)*
Video de 3 min de la demo en staging, README con diagrama, caso de estudio con métricas, al menos un
postmortem real.

---

## 11. Control de costos del propio proyecto

- Presupuesto en efectivo: **USD 50 al mes** hasta fin de 2026 (~USD 125 en total), Anthropic + AWS.
  Los créditos de AWS (USD 100 + hasta 100 por actividades) se consumen antes que el efectivo; la API de
  Anthropic no está cubierta por ellos y es el gasto real esperado.

  | Partida | Tope mensual | Control |
  |---|---|---|
  | Anthropic, workspace `dev` | USD 10 | Límite de gasto del workspace |
  | Anthropic, workspace `ci` (evals) | USD 10 | Límite propio, para que un eval descontrolado no deje sin API al desarrollo |
  | Anthropic, workspace `staging` (demos) | USD 5 | Límite propio |
  | AWS | USD 25 de reserva | Créditos primero; alertas sobre costo bruto |

- Meta de costo AWS: ~USD 1–2 al mes en reposo; las demos se miden por hora encendida (ADR-0007).
- Dos ambientes aplicados: `dev` y `staging`. `prod` existe en Terraform y se valida en CI, pero nunca
  se aplica (fuera de alcance: duplicar staging no demuestra nada nuevo y duplica el costo).
- `staging` es efímero: se aplica para demos y pruebas por despliegue manual y se destruye después
  con un workflow de destroy, que además corre **cada noche** por `schedule`. Olvidar staging encendido
  cuesta como máximo un día (~USD 2).
- `dev` no tiene recursos permanentes: lo que se crea ahí se destruye después de usarlo (§13).
- Controles de gasto AWS: AWS Budgets sobre el **costo bruto** (antes de créditos, para ver cuánto se
  consume) con alertas en 10, 25 y 40 USD. Mientras se usen proyectos sin funciones avanzadas, además
  *spend limit* por proyecto. Con funciones avanzadas (§13) el spend limit desaparece y se reemplaza por:
  una *Budget action* que aplica una política de denegación al llegar a 45 USD (a verificar en T9),
  Cost Anomaly Detection, y un **SCP propio de costo** que deniega servicios caros que el proyecto no usa
  (p. ej. instancias EC2 grandes o GPU, SageMaker) y regiones fuera de la asignada.
- API key de Anthropic: una por ambiente (`dev`, `ci`, `staging`), cada una en su propio workspace de la
  consola de Anthropic con el límite de la tabla anterior (a verificar en T1). Desarrollo: `.env` local (en `.gitignore`;
  `.env.example` documenta la variable). Staging: Secrets Manager, creado en `infra/bootstrap` (no en
  `envs/staging`) para que sobreviva a cada destroy y su valor nunca esté en el estado de Terraform;
  el valor lo carga Andrés con `aws secretsmanager put-secret-value`.
- Red sin NAT Gateway (ADR-0010); llaves KMS gestionadas por AWS en staging para no pagar llaves propias.
- Demo con Haiku cuando sea posible, rate limiting estricto y tope diario global.
- Reportar en el README el costo real: en reposo (mensual) y con staging encendido (por hora).

---

## 12. Decisiones abiertas

Resueltas en Fase 0: región AWS (la asignada al proyecto, `us-east-2` esperada; ADR-0006, se confirma
en el spike de T9); alcance y costo (ADR-0007); modelo de cuenta AWS (ADR-0008, se acepta tras el
spike de T9).

Se resuelven en Fase 1, con ADR, al implementarse:
- Proveedor de embeddings final (comparar con evals propios; default provisional: Bedrock Cohere Embed).
- Backend de observabilidad (recomendación inicial: Grafana Cloud free tier vía OTel Collector).
- Langfuse Cloud vs auto-alojado (recomendación inicial: Cloud, solo texto redactado).

Sin ADR: "Relay" es nombre en clave; el dominio se decide antes de publicar la demo. Staging usa
el dominio por defecto de CloudFront.

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
- Sin push directo; requiere PR con todos los checks verdes que existan en ese momento (lint, tipos,
  tests y escaneos de seguridad desde Fase 0; evals y red team se agregan al crearse).
- Historial lineal, commits firmados (SSH o GPG), sin force-push, conversaciones resueltas.
- `CODEOWNERS` para rutas sensibles (`infra/`, `apps/api/auth`, `apps/api/agent`, migraciones).

### Releases
- **SemVer** (`v0.x.y` durante el desarrollo; `v1.0.0` al cerrar Fase 5).
- Tags por fase: `v0.1.0` = Fase 0, `v0.2.0` = Fase 1, etc.
- Release manual al cerrar cada fase: tag firmado + GitHub Release con notas escritas
  (`gh release create`). *Prioridad 2:* `CHANGELOG.md` generado con release-please.
- Imágenes de contenedor etiquetadas con el SHA del commit y la versión; nunca `latest` en entornos.
- Despliegue: `staging` por `workflow_dispatch` (no en cada merge, porque es efímero). Destroy por otro
  workflow, manual y también **programado cada noche** (si se olvida apagar staging, no pasa de un
  día); ambos usan el GitHub Environment `staging`. *Fuera de alcance:* producción desde un
  release con aprobación manual.

### Qué más se versiona (y cómo)
| Artefacto | Mecanismo |
|---|---|
| Esquema de base de datos | Migraciones Alembic numeradas y reversibles |
| Infraestructura | Terraform en el repo; estado remoto en S3 con bloqueo; `plan` de `staging` visible en cada PR; `prod` solo `validate` |
| API pública | Prefijo `/v1`; cambios incompatibles solo en nueva versión; OpenAPI versionado en el repo |
| Prompts del sistema | Archivos en `apps/api/prompts/` con versión explícita; cada respuesta registra la versión usada |
| Modelos LLM | IDs fijados en configuración, nunca alias implícitos; cambio de modelo = PR con evals |
| Datasets de evals y red team | En `evals/` dentro del repo; cambios por PR con justificación |
| Decisiones | ADRs numerados e inmutables (se reemplazan con uno nuevo, no se editan) |
| Documentos de tenants | Versionado de documentos y de su índice en la aplicación (§4.1) |

### Desarrollo asistido por agente (Claude Code)
- **Cuenta AWS** en la nueva experiencia de cuentas, con plan pago (upgrade justo antes de T9) y dos
  **proyectos**: `dev` y `staging`. Cada proyecto es una cuenta AWS dentro de una organización que
  administra AWS (ADR-0008). Región: la que AWS asigna al proyecto según el país de contacto
  (`us-east-2` para América; ADR-0006).
- **Funciones avanzadas:** el SCP gestionado de los proyectos deniega `iam:*Provider*`, por lo que no
  se puede crear el proveedor OIDC de GitHub. Si el spike de T9 lo confirma, se activan las funciones
  avanzadas: pasamos a administrar la organización y los proyectos quedan como cuentas miembro.
  La activación es irreversible y elimina los *spend limits*; el control de gasto pasa a Budgets +
  *Budget action* + Cost Anomaly Detection (§11). Otros disparadores: dar acceso con Identity Center a
  otra persona, necesitar GuardDuty o Security Hub.
- **Matriz de acceso:**

  | Ambiente | Quién | Cómo |
  |---|---|---|
  | `dev` | Andrés y el agente | Solo credenciales temporales (`aws login`) desde el devcontainer |
  | `staging` | Solo GitHub Actions | OIDC; el rol de deploy confía solo en este repo y en el GitHub Environment `staging` |
  | `prod` | Nadie | Sin proyecto ni credenciales; solo existe en Terraform |

  Única excepción: `infra/bootstrap` se ejecuta una vez por proyecto con las credenciales de Andrés
  (runbook de bootstrap; threat model).
- **Propósito de `dev`:** el desarrollo diario es 100 % local (Docker Compose). `dev` solo se usa para
  lo que no se puede emular localmente (p. ej. embeddings de Bedrock, probar un módulo Terraform antes
  de staging). Todo lo creado en `dev` se destruye después de usarlo.
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
