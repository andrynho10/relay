# CLAUDE.md — Relay

Relay es un SaaS B2B multi-tenant: un copiloto de soporte con IA que responde consultas usando
la documentación de cada empresa (RAG), clasifica tickets y ejecuta acciones con aprobación humana.
Es un proyecto de portafolio construido con estándar de producción empresarial.

La especificación completa está en `docs/SPEC.md`. Léela antes de planificar cualquier fase.
Las decisiones de arquitectura están en `docs/adr/`. No contradigas un ADR aceptado sin proponer uno nuevo.

## Forma de trabajar

- Trabaja por fases (ver `docs/SPEC.md` §10). Nunca avances a la siguiente fase sin mi aprobación.
- Para cualquier tarea que toque más de 3 archivos: primero un plan, espera mi OK, luego implementa.
- Explícame las decisiones no obvias en 1–3 frases. Debo poder defender cada línea en una entrevista.
- Si algo es ambiguo, pregunta. No inventes requisitos ni proveedores.
- Cambios pequeños y verificables. Un commit por unidad lógica (Conventional Commits, en inglés).
- Al cerrar una tarea: corre lint, tipos y tests; reporta el resultado real, no el esperado.
- Si tomas una decisión de arquitectura nueva, redacta el ADR correspondiente.
- Mantén este archivo actualizado (comandos, convenciones) y bajo ~150 líneas.

## Stack (resumen; detalle y justificación en SPEC §6)

- Backend: Python 3.12+, FastAPI, Pydantic v2, SQLAlchemy 2 + Alembic, uv, ruff, mypy --strict, pytest
- Workers: Python, consumen de Amazon SQS (con DLQ)
- Frontend: Next.js (App Router) + TypeScript strict + Tailwind; Playwright + axe para E2E/accesibilidad
- Datos: PostgreSQL 16+ con pgvector y Row-Level Security; Redis (ElastiCache/Valkey); S3
- IA: Claude API vía capa `LLMGateway` (modelos `claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5`)
- Embeddings: proveedor detrás de interfaz `Embedder` (ver ADR)
- PII: Microsoft Presidio + reconocedores propios (determinístico, sin LLM)
- Auth: WorkOS (SSO/SCIM empresarial). Billing: Stripe (modo test, cobro por uso)
- Infra: AWS (ECS Fargate, RDS, SQS, S3, CloudFront + WAF, Secrets Manager, KMS), Terraform
- CI/CD: GitHub Actions con OIDC hacia AWS (sin llaves de larga duración)
- Observabilidad: OpenTelemetry, Sentry, trazas LLM en Langfuse
- Local: Docker Compose replica todos los servicios

## Comandos

<!-- Claude: completa esta sección cuando existan los comandos reales -->
- `make dev` — levanta el entorno local
- `make check` — lint + tipos + tests unitarios
- `make test-integration` — tests contra Postgres/Redis reales en contenedores
- `make evals` — suite de evaluación de calidad de IA
- `make redteam` — suite de ataques (prompt injection, cross-tenant, escalamiento)

## Reglas no negociables

Seguridad
- Todo input externo es no confiable: usuarios, documentos subidos, respuestas del LLM, webhooks.
- La salida del LLM nunca se ejecuta ni se renderiza sin validar (esquema Pydantic / sanitización).
- Las reglas de negocio y permisos viven en el backend, nunca solo en el prompt.
- Toda query a datos de tenant pasa por RLS. Incluye búsqueda vectorial. Sin excepciones.
- Cero secretos en el código, logs, trazas o mensajes de error. Usa Secrets Manager / `.env` local ignorado.
- PII se redacta antes de enviar texto a cualquier proveedor externo y antes de loguear.
- Acciones del agente con efecto externo: permisos mínimos, límites, y aprobación humana si son sensibles.
- Cada endpoint declara explícitamente su autorización. Por defecto: denegar.
- Dependencias fijadas con lockfile. No agregues una dependencia sin decirme por qué.

Calidad
- Tipado estricto en Python y TypeScript. Nada de `Any`/`any` sin comentario justificando.
- Toda lógica nueva lleva tests. Todo bug corregido lleva un test que lo reproduce.
- Cambios en prompts, modelos o recuperación deben pasar `make evals` sin regresión.
- Accesibilidad WCAG 2.2 AA en la UI.

Costo y confiabilidad
- Toda llamada al LLM pasa por `LLMGateway`: registra tokens, costo, latencia, modelo y tenant.
- Usa el modelo más barato que pase los evals para cada tarea (Haiku → Sonnet → Opus).
- Usa prompt caching para contenido estable (system prompt, herramientas).
- Timeouts, reintentos con backoff y jitter, idempotencia en workers y webhooks.
- Si el LLM falla, se degrada a "derivar a humano", nunca a un error 500 para el usuario final.

## Convenciones

- Código, identificadores, commits y docs técnicos en inglés; docs de producto pueden ir en español.
- Estructura monorepo: `apps/api`, `apps/worker`, `apps/web`, `packages/`, `infra/`, `docs/`, `evals/`.
- Errores: excepciones de dominio tipadas; respuestas API con formato de error consistente (RFC 9457).
- Logs estructurados JSON con `trace_id` y `tenant_id`; nunca contenido de mensajes sin redactar.
- Migraciones con Alembic, siempre reversibles.

## Alcance y disciplina (anti-desvío)

- Implementa solo lo que dice el plan aprobado. Ideas extra, mejoras o refactors no pedidos:
  anótalos en `docs/BACKLOG.md` y sigue con la tarea.
- Nunca modifiques ni borres un test existente para que pase sin avisarme y explicar por qué.
- En lógica crítica (auth, RLS, permisos del agente, facturación) escribe primero el test que falla.
- No confíes en tu memoria para APIs de librerías o servicios que cambian: verifica la documentación
  oficial de la versión fijada antes de usarlas, y dime qué verificaste.
- Si una tarea crece más de lo planificado o te atascas tras 2 intentos, detente y pregúntame.
- Nunca uses credenciales de producción. Tu entorno solo tiene acceso a local y a la cuenta AWS de dev.

## Git (detalle en SPEC §13)

- Nunca trabajes en `main`. Crea una rama corta por tarea (`feat/…`, `fix/…`) y abre un PR.
- Commits pequeños con Conventional Commits. Nunca `--force`, nunca `--no-verify`.
- No hagas merge tú: yo reviso y apruebo el PR.
- Cambios de prompt o modelo: actualiza su versión y corre evals en el mismo PR.

## Continuidad entre sesiones

- Al iniciar: lee `docs/PROGRESS.md` y el plan activo en `docs/plans/` antes de hacer nada.
- Al terminar cada tarea: actualiza `docs/PROGRESS.md` (hecho, en curso, siguiente, bloqueos).
- Los planes aprobados se guardan en `docs/plans/phase-N.md` con casillas por tarea.

## Qué NO hacer

- No uses servicios fuera de los aprobados en SPEC §6 sin un ADR.
- No desactives tests, linters ni chequeos de seguridad para "hacer pasar" algo.
- No simules resultados de herramientas, tests o despliegues.
- No escribas código de demostración "temporal" en rutas de producción.
