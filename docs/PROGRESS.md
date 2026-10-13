# PROGRESS — estado del proyecto

> Archivo de traspaso entre sesiones de Claude Code. Se actualiza al cerrar cada tarea.
> Debe poder leerse en 1 minuto. Lo histórico va en git y en el CHANGELOG, no aquí.

**Última actualización:** 2026-10-13
**Fase actual:** 0 — Fundaciones · Plan: `docs/plans/phase-0.md` (aprobado 2026-10-13)
**Rama activa / PR abierto:** `docs/phase-0-plan` (T0) — commit local, falta push + PR

## Hecho en esta fase
- Kickoff: resumen, riesgos y decisiones abiertas de SPEC §12 cerradas (ver tabla en el plan).
- T0: plan de Fase 0 guardado en `docs/plans/phase-0.md`.

## En curso
- Tarea: T0 — pendiente de push y PR (gh CLI no está instalado en el host).
- Estado exacto: commit hecho en `docs/phase-0-plan`; sin firma (no hay clave de firma configurada).

## Siguiente
1. T1 `chore/repo-hygiene`.
2. T2 `docs/initial-adrs` (ADR-0009 se revisa antes de implementar el devcontainer).

## Decisiones recientes (no obvias en el código)
- Región us-east-1; devcontainer como entorno; staging efímero (~$50/mes); repo público.
- Grafana Cloud + Langfuse Cloud + "Relay" como nombre en clave, salvo objeción.
- Embeddings: ADR-0010 queda *Propuesto* hasta tener evals en Fase 1.

## Bloqueos y preguntas para mí
- Prerrequisitos del plan (cuentas AWS, clave de firma SSH, ajustes de GitHub) pendientes.

## Trampas conocidas
- Host Windows sin `make`, Node, Terraform, gh ni aws CLI; WSL no registrado → todo pasa por el devcontainer.
