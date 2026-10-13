# PROGRESS — estado del proyecto

> Archivo de traspaso entre sesiones de Claude Code. Se actualiza al cerrar cada tarea.
> Debe poder leerse en 1 minuto. Lo histórico va en git y en el CHANGELOG, no aquí.

**Última actualización:** 2026-10-13
**Fase actual:** 0 — Fundaciones · Plan: `docs/plans/phase-0.md` (aprobado y re-planificado por costo 2026-10-13)
**Rama activa / PR abierto:** `docs/phase-0-plan` (T0) — PR #1

## Hecho en esta fase
- Kickoff: resumen, riesgos y decisiones de SPEC §12 (devcontainer, repo público).
- T0: plan de Fase 0 en `docs/plans/phase-0.md`.
- Re-planificación por costo: línea de corte CV (SPEC §10.0), dos ambientes aplicados, staging efímero,
  seguridad mínima en CI, release manual, red sin NAT. SPEC v0.2 y CLAUDE.md ajustados.
- Gestión de AWS documentada: modelo de cuenta, matriz de acceso, propósito de `dev`, secretos.

## En curso
- Tarea: T0 — esperando revisión y squash merge del PR #1.

## Siguiente
1. T1 `chore/repo-hygiene`.
2. T2 `docs/initial-adrs` (0001–0009; ADR-0009 se revisa antes de T2b).
3. Antes de T9: upgrade a plan pago, proyectos `dev`/`staging` con spend limit, Budgets 5/10/20 USD.

## Decisiones recientes (no obvias en el código)
- Núcleo CV: RAG multi-tenant con RLS y citas, triage estructurado, `LLMGateway` con costos, evals en CI,
  WorkOS AuthKit (plan gratuito, precio a verificar en Fase 2), una herramienta sensible (`issue_refund`)
  con aprobación, red team mínimo, observabilidad (OTel de punta a punta, Langfuse, un dashboard, una
  alerta con runbook), SLO de TTFT p95, demo en staging + video. Todo lo demás es Roadmap.
- Evals: v1 con ~50 casos; subconjunto síncrono con Haiku como juez en PRs que tocan prompts/recuperación;
  suite completa por Batch API manual o semanal.
- GuardDuty, SLO de disponibilidad y k6 pasan a Roadmap; queda CloudTrail.
- AWS: experiencia nueva, plan pago, proyectos `dev` y `staging` (cuentas en una organización que
  administra AWS). El SCP gestionado deniega `iam:*Provider*` → sin proveedor OIDC de GitHub. Si el spike
  de T9 lo confirma, se activan funciones avanzadas (irreversible, sin spend limit; control de gasto con
  Budgets + Budget action a 20 USD + Cost Anomaly Detection). Elegido porque el CD con OIDC es parte
  central del CV; alternativas (llaves largas, runners en CodeBuild, deploy manual) descartadas.
- Matriz de acceso: `dev` = Andrés + agente con `aws login`; `staging` = solo Actions vía OIDC
  (repo + environment `staging`); `prod` = nadie. Excepción: `infra/bootstrap` con credenciales de Andrés.
- Desarrollo diario 100 % local; `dev` solo para lo no emulable, y se destruye tras usarlo.
- Región: la que AWS asigna al proyecto (`us-east-2` esperada para América), no `us-east-1`.
- API key de Anthropic: una por ambiente, en workspaces con su spend limit; staging en Secrets Manager
  creado en bootstrap (sobrevive a destroy, valor fuera del estado de Terraform).
- Staging se despliega y destruye a mano (`workflow_dispatch`); llaves KMS gestionadas por AWS.
- ADRs de embeddings, observabilidad y Langfuse se escriben en Fase 1. "Relay" es nombre en clave.
- Fase 5 renombrada a "Staging de demo y operación"; producción aplicada pasa a Roadmap.

## Bloqueos y preguntas para mí
- T9 se detiene si no hay credenciales temporales para `dev` en el devcontainer, o si algo más que el
  proveedor OIDC está bloqueado.

## Trampas conocidas
- Host Windows sin `make`, Node, Terraform ni aws CLI; WSL no registrado → todo pasa por el devcontainer.
- `gh` está en `C:\Program Files\GitHub CLI\` y no aparece en el PATH de sesiones abiertas antes de instalarlo.
- El remoto no tenía `main` al principio; la primera rama subida quedó como default (ya corregido).
- La firma de commits desde la shell del agente falla si la clave no está en el ssh-agent de Windows
  (`ssh-add -l` con el binario de `C:\Windows\System32\OpenSSH`).
- `aws login` usa la sesión elegida en el navegador, no la del perfil → verificar con
  `aws sts get-caller-identity` y `allowed_account_ids` en Terraform.
- No usar el script de "Agent Toolkit" de AWS (curl + MCP + reglas): configurar el perfil a mano.
