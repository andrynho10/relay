# PROGRESS — estado del proyecto

> Archivo de traspaso entre sesiones de Claude Code. Se actualiza al cerrar cada tarea.
> Debe poder leerse en 1 minuto. Lo histórico va en git y en el CHANGELOG, no aquí.

**Última actualización:** 2026-10-13
**Fase actual:** 0 — Fundaciones · Plan: `docs/plans/phase-0.md` (aprobado y re-planificado por costo 2026-10-13)
**Rama activa / PR abierto:** `chore/repo-hygiene` (T1)

## Hecho en esta fase
- Kickoff: resumen, riesgos y decisiones de SPEC §12 (devcontainer, repo público).
- T0: plan de Fase 0 en `docs/plans/phase-0.md` (PR #2, mergeado).
- Re-planificación por costo: dos ambientes aplicados, staging efímero,
  seguridad mínima en CI, release manual, red sin NAT. SPEC v0.2 y CLAUDE.md ajustados.
- Gestión de AWS documentada: modelo de cuenta, matriz de acceso, propósito de `dev`, secretos.
- Plan organizado en hitos de CV (SPEC §10.0) y presupuesto de USD 50/mes (SPEC §11). SPEC v0.3.
- Ruleset básico de `main` aplicado (`main-protection`).

## En curso
- Tarea: T1 — `.gitattributes`, `.editorconfig`, `.gitignore`, `.dockerignore`, `.pre-commit-config.yaml`
  y README hechos; los 16 hooks pasan (`uvx pre-commit@4.6.2 run --all-files`). Falta `.env.example`,
  que crea Andrés (el agente tiene denegado `Read(./.env.*)`).

## Siguiente
1. T2 `docs/initial-adrs` (0001–0009; ADR-0009 se revisa antes de T2b).
2. Antes de T9: upgrade a plan pago, proyectos `dev`/`staging` con spend limit, Budgets 10/25/40 USD.
3. Meta inmediata: cerrar el hito 1 (fases 0 + 1, release `v0.2.0`) lo antes posible.

## Decisiones recientes (no obvias en el código)
- Hitos de CV (prioridad 1, en orden): 1 RAG demostrable (fases 0+1), 2 multi-tenant seguro, 3 agente
  con aprobación (incluye triage), 4 economía medida, 5 operación + portafolio. Cada hito = release +
  README + video corto + costo real. Meta mínima del proyecto: hito 3.
- Prioridad 2 (E1–E8): cadena de suministro, SSO/SCIM en staging de WorkOS, endurecimiento de staging
  (WAF/GuardDuty/Multi-AZ/ZAP), agente ampliado (MCP, red team completo), Stripe test, k6 + SLO 7 días,
  caché semántico, demo pública. Producción aplicada queda fuera de alcance.
- Evals: v1 con ~50 casos; subconjunto síncrono con Haiku como juez en PRs que tocan prompts/recuperación;
  suite completa por Batch API manual o semanal.
- Presupuesto USD 50/mes: Anthropic `dev` 10, `ci` 10, `staging` 5; AWS 25 de reserva (créditos
  primero). Budgets sobre costo bruto 10/25/40; tras funciones avanzadas, Budget action a 45 USD + Cost
  Anomaly Detection + SCP de costo. Staging se destruye cada noche por `schedule`.
- AWS: experiencia nueva, plan pago, proyectos `dev` y `staging` (cuentas en una organización que
  administra AWS). El SCP gestionado deniega `iam:*Provider*` → sin proveedor OIDC de GitHub. Si el spike
  de T9 lo confirma, se activan funciones avanzadas (irreversible, sin spend limit; control de gasto con
  Budgets + Budget action a 45 USD + Cost Anomaly Detection + SCP de costo). Elegido porque el CD con OIDC es parte
  central del CV; alternativas (llaves largas, runners en CodeBuild, deploy manual) descartadas.
- Matriz de acceso: `dev` = Andrés + agente con `aws login`; `staging` = solo Actions vía OIDC
  (repo + environment `staging`); `prod` = nadie. Excepción: `infra/bootstrap` con credenciales de Andrés.
- Desarrollo diario 100 % local; `dev` solo para lo no emulable, y se destruye tras usarlo.
- Región: la que AWS asigna al proyecto (`us-east-2` esperada para América), no `us-east-1`.
- API key de Anthropic: una por ambiente, en workspaces con su spend limit; staging en Secrets Manager
  creado en bootstrap (sobrevive a destroy, valor fuera del estado de Terraform).
- Staging se despliega y destruye a mano (`workflow_dispatch`); llaves KMS gestionadas por AWS.
- ADRs de embeddings, observabilidad y Langfuse se escriben en Fase 1. "Relay" es nombre en clave.

## Bloqueos y preguntas para mí
- T9 se detiene si no hay credenciales temporales para `dev` en el devcontainer, o si algo más que el
  proveedor OIDC está bloqueado.

## Trampas conocidas
- Host Windows sin `make`, Node, Terraform ni aws CLI; WSL no registrado → todo pasa por el devcontainer.
- `gh` está en `C:\Program Files\GitHub CLI\` y no aparece en el PATH de sesiones abiertas antes de instalarlo.
- El remoto no tenía `main` al principio; la primera rama subida quedó como default (ya corregido).
- El ruleset exige firma en **todos** los commits del PR, aunque se haga squash: un solo commit sin firmar
  bloquea el merge. Se arregla con una rama nueva + cherry-pick firmado, nunca con force push.
- La firma de commits desde la shell del agente falla si la clave no está en el ssh-agent de Windows
  (`ssh-add -l` con el binario de `C:\Windows\System32\OpenSSH`).
- `aws login` usa la sesión elegida en el navegador, no la del perfil → verificar con
  `aws sts get-caller-identity` y `allowed_account_ids` en Terraform.
- No usar el script de "Agent Toolkit" de AWS (curl + MCP + reglas): configurar el perfil a mano.
- `python` en Git Bash resolvía al alias de la Microsoft Store: se movió `%LOCALAPPDATA%\Python\bin`
  antes de `WindowsApps` en el PATH de usuario (respaldo en `%TEMP%\user-path-backup-20261013.txt`).
  Requiere reiniciar terminales; `py` funciona siempre.
- `core.autocrlf=true` en este host dejaba los archivos en CRLF en la copia de trabajo; `.gitattributes`
  (`eol=lf`) lo corrige. Si un hook marca `mixed-line-ending`, es eso.
- `pre-commit` no está en el host: usar `uvx pre-commit@4.6.2 run --all-files` hasta tener el devcontainer.
