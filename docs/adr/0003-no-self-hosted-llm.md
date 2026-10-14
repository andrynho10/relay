# ADR-0003: No self-hosted LLM; Claude API behind `LLMGateway`

- **Status:** Accepted
- **Date:** 2026-10-14
- **Deciders:** Andrés Amaya Garcés

## Context

Relay's value depends on answer quality, faithful citations, safe tool use and low cost per resolution
(SPEC §2). The project has a cash budget of USD 50/month (ADR-0007) and one developer. Running a model
ourselves means GPUs, model serving, scaling and security patching; hosted models give immediate access
to new capabilities such as prompt caching and the Batch API.

## Decision

- Do not self-host or fine-tune models. Use the **Claude API** (`claude-haiku-5-5`, `claude-sonnet-5-5`,
  `claude-opus-5-5`) with model IDs pinned in configuration, never implicit aliases.
- Every model call goes through an **`LLMGateway`** that owns model routing, prompt caching, timeouts,
  retries with backoff and jitter, a circuit breaker, refusal handling, and records tokens, cost, latency,
  model and tenant per call. If the model fails or refuses, the request degrades to "hand off to a
  human", never to an error for the end user.
- The gateway's provider interface keeps Amazon Bedrock or Claude Platform on AWS as an exit if a customer
  requires AWS billing or data residency.

## Alternatives considered

- **Self-hosted open-weights model on GPUs:** an always-on GPU instance alone would exceed the project's
  whole monthly budget, quality would need its own evaluation effort, and serving adds operational load.
- **A local model (for example Ollama) for development only:** development would diverge from production
  behaviour, and evals run against it would not be representative.
- **Calling the provider SDK directly from each feature:** no central place for cost accounting,
  caching, routing or degradation.

## Consequences

- Text leaves our cloud. PII is redacted deterministically before any call (SPEC §7), and only redacted
  text reaches traces.
- We depend on one model vendor; the gateway limits the blast radius of a switch.
- The current models have API constraints the gateway must handle: thinking cannot be disabled on Sonnet
  5.5 and is billed as output, forced `tool_choice` is rejected on the 5.5 models, and `refusal` is a
  stop reason to handle (verified 2026-10-13 in Anthropic's API reference).
- Cost per token is variable and must be measured from day one (SPEC §2, ADR-0007).

## Verification and revisit triggers

- Every call appears in the gateway's cost records and in LLM traces with model, tokens and tenant.
- Revisit if a customer requires a deployment the hosted API cannot serve, or if evals show a cheaper
  hosted model meets the quality bar.
