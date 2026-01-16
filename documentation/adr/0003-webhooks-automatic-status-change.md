# ADR-0003: Webhooks automáticos por cambio de estado (idempotencia, retries y resend)

## Estado
Propuesto (para pulir el MVP)

## Contexto
El sistema expone un “estado” de solicitud de crédito que cambia después de evaluar riesgo de forma asíncrona (Oban).
Existe un worker `BravoMultipais.Workers.WebhookNotifier` que envía un webhook con el estado público de una solicitud a un endpoint configurable (`WEBHOOK_URL`), y el Backoffice permite reenviar manualmente (“resend”).

Actualmente:
- El webhook puede enviarse manualmente, pero no existe una garantía explícita de envío automático asociado al cambio de estado.
- La entrega puede fallar por errores transitorios (red, 5xx) o permanentes (4xx).
- El consumidor downstream puede recibir duplicados (por retries o por re-evaluaciones), y requiere una estrategia de idempotencia.

Queremos que el producto sea “honesto” y operable:
- Si el estado cambia, se notifica automáticamente.
- Si falla, se reintenta con una política clara.
- Si se reenvía manualmente, el contrato sigue siendo consistente.

## Decisión
1) **El webhook se enviará automáticamente** cuando una solicitud cambie de estado como resultado de la evaluación de riesgo.
   - El punto de acoplamiento será el worker `Workers.EvaluateRisk` (infra), inmediatamente después de persistir `status`/`risk_score` con éxito.
   - La capa web (LiveView) conservará el botón “resend”, pero será un mecanismo operativo, no el camino principal.

2) **Idempotencia**: cada notificación incluirá un identificador estable para deduplicación.
   - Se agregará al payload un campo `event_id` (UUID) y un `event_type`.
   - Además se incluirá `application_id` + `status` + `risk_score` como datos de negocio.

3) **Contrato del evento**:
   - `event_type = "application.status_changed"`
   - `version = "v1"`
   - `data = CreditApplications.to_public(application)` (map público, sin PII sensible)

4) **Política de reintentos**:
   - Respuesta 2xx: éxito, no reintentar.
   - Respuesta 5xx / timeout / errores de red: reintentar (Oban).
   - Respuesta 4xx: descartar (no reintentar), ya que suele indicar error permanente de contrato o autenticación.
   - Se preserva `:discard` si la aplicación no existe.

5) **Dedupe de jobs**:
   - El worker `WebhookNotifier` usará `unique:` por args para evitar spam (por ejemplo, período de 60s).
   - El “resend” manual en Backoffice seguirá funcionando (puede generar un nuevo `event_id`), pero se recomendará incluir `reason: "manual_resend"` en payload.

6) **Configuración**:
   - `WEBHOOK_URL` seguirá siendo la fuente de verdad del endpoint.
   - Se soportará `SKIP_WEBHOOKS=true` para entornos donde no se desea notificar.

## Consecuencias

### Positivas
- Ownership: el sistema cumple el contrato “cambio de estado => notificación”.
- Agency: el backoffice permite reenviar sin tocar infraestructura manualmente.
- Goodwill: payload versionado e idempotente, facilita integraciones reales.
- Resiliencia: reintentos automáticos ante fallas transitorias.

### Negativas / trade-offs
- Mayor acoplamiento “infra”: `Workers.EvaluateRisk` encola a `WebhookNotifier`.
- Si la evaluación corre muchas veces, puede aumentar tráfico hacia downstream (mitigado con dedupe + idempotencia).
- Requiere definir claramente si `UNDER_REVIEW` se considera estado final (para evitar notificaciones redundantes).

## Alternativas consideradas
1) Disparar webhook desde la capa web (controller/liveview)
   - Rechazada: rompe separación de capas y no garantiza envío si el cambio ocurre asíncrono.
2) Publicar un evento interno (PubSub) y que otro proceso decida webhooks
   - Postergada: más complejidad para MVP; se puede evolucionar después.
3) No incluir idempotencia y confiar en “best effort”
   - Rechazada: dupes son inevitables con retries y re-evaluaciones.

## Plan de implementación (alto nivel)
1) Tras `Repo.update` exitoso en `Workers.EvaluateRisk`, encolar `WebhookNotifier` si `SKIP_WEBHOOKS != true`.
2) Añadir `event_id`, `event_type`, `version`, y `data` al payload.
3) Ajustar `WebhookNotifier` para descartar 4xx y reintentar 5xx/errores de red.
4) Añadir `unique:` a `WebhookNotifier` para dedupe.
5) Tests:
   - Verificar que un cambio de estado encola webhook automáticamente.
   - Verificar política 4xx discard vs 5xx retry.
   - Verificar payload contiene `event_id`, `event_type`, `version`.

## Notas
El evento representa una notificación del estado resultante (edge-trigger), pero el endpoint debe ser capaz de recibir duplicados. Por ello `event_id` + idempotencia es parte del contrato.