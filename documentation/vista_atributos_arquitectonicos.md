# Vista de Atributos Arquitectónicos – BravoMultipais

Esta vista describe **las propiedades de calidad** que guían la arquitectura del motor de solicitudes de crédito multipaís, y las *tácticas* que usamos (o planeamos usar) para cumplirlas.

---

## 1. Seguridad

### 1.1 Objetivos

- Proteger datos sensibles de clientes (documentos, montos, ingresos, perfiles bancarios).
- Evitar filtraciones mediante logs, errores o integraciones externas.
- Tener una base clara para endurecer la seguridad si el MVP evoluciona a producto real.

### 1.2 Información privada excluida de logs

**Decisiones:**

- No logear:
  - Documentos completos (DNI, Codice Fiscale, NIF).
  - Datos de ingreso o montos exactos.
  - Información detallada de `bank_profile` (solo IDs o hashes si hace falta).
- Incluir en logs solo:
  - `application_id` (UUID).
  - País, estado, eventos de workflow, y códigos de error.

**Tácticas:**

- Normalizar el uso de `Logger` con metadatos:
  - `%{application_id: ..., status: ..., result: ...}`.
- Revisar handlers y workers para asegurar que:
  - No interpolan structs completos en logs.
  - No hacen `inspect/2` de cambiosets con datos sensibles.

---

### 1.3 Encriptación

#### 1.3.1 En reposo

**Decisiones (nivel conceptual):**

- Asumir:
  - Base de datos desplegada sobre infraestructura que soporta **cifrado en disco** (p.ej. Postgres en cloud con `storage encryption`).
- Datos especialmente sensibles susceptibles de **cifrado a nivel de columna** si se pasa a entorno real:
  - Documentos (`dni`, `codice_fiscale`, `nif`).
  - Identificadores externos (`bank_profile.external_id`).

**Tácticas:**

- Mantener el modelo preparado para:
  - Añadir módulos de cifrado (campo → `encrypted_*`).
  - Minimizar uso de estos campos en memoria y logs.

#### 1.3.2 En tránsito (optativa, pero recomendada)

**Decisiones:**

- Todas las comunicaciones externas deben asumir **HTTPS/TLS**:
  - API pública (`/api/applications`).
  - Webhooks hacia sistemas externos.

**Tácticas:**

- Configuración de endpoints Phoenix solo servidos sobre HTTPS en ambientes productivos.
- Bloquear HTTP plano o redirigir únicamente a HTTPS.

---

## 2. Mantenibilidad

### 2.1 Modularidad

**Objetivo:**
Mantener el sistema **fácil de cambiar** cuando:
- se añadan más países,
- se alteren reglas de riesgo,
- o se extienda la API.

**Decisiones de diseño:**

- **Contextos separados**:
  - `CreditApplications` – flujo de solicitudes.
  - `Policies` – reglas por país.
  - `Bank` – perfil bancario.
  - `Accounts` – usuarios / autenticación.
- **Workers especializados**:
  - `EvaluateRisk` → cálculo de score + cambio de estado.
  - `WebhookNotifier` → integración externa.

**Tácticas:**

- Evitar que la UI (LiveView / Controller) haga lógica de negocio:
  - Siempre delegar en `CreditApplications` / `Commands` / `Queries`.
- Mantener políticas de riesgo encapsuladas:
  - Nuevas reglas → cambios en `Policies`, no en todo el sistema.

---

### 2.2 Testabilidad

**Objetivo:**
Poder evolucionar reglas y flujos sin miedo a romper lo existente.

**Metas cuantitativas:**

- Cobertura de tests **≥ 90%** en:
  - `CreditApplications` (contexto).
  - `Policies` y `Bank`.
  - Workers (`EvaluateRisk`, `WebhookNotifier`).
  - API (`ApplicationController`).
- Tests ejecutados automáticamente en **pipeline de CI/CD**.

**Tácticas:**

- Separar **tests de dominio** (pure functions, contexts) de **tests de integración** (HTTP, DB, Oban).
- Usar `DataCase` / `ConnCase` para:
  - Aislar base de datos por test.
  - Probar flujos completos (API → contextos → workers).
- Añadir pruebas específicas para:
  - Cambios de estado (`CREATED` → `PENDING_RISK` → `APPROVED/REJECTED/UNDER_REVIEW`).
  - Cálculo de score y su impacto en la decisión.
  - Serialización de payloads públicos (lo que sale por API y webhooks).

---

## 3. Escalabilidad

### 3.1 Objetivo

Soportar un crecimiento gradual en:

- Número de solicitudes por día.
- Número de países.
- Número de integraciones externas que consumen la API o los webhooks.

Sin reescribir la arquitectura desde cero.

### 3.2 Estrategia Serverless / Jobs asíncronos

**Decisiones:**

- Separar el flujo en dos partes:
  - **Síncrono**:
    - Creación de solicitud (`CREATED` → `PENDING_RISK`).
    - Respuesta rápida a UI y API.
  - **Asíncrono**:
    - Evaluación de riesgo (`EvaluateRisk`).
    - Notificación por webhook (`WebhookNotifier`).
- Mantener la lógica de workers lista para:
  - Migrar a entornos **serverless** (Jobs gestionados, Lambdas, etc) si se desea.

**Tácticas:**

- Oban como motor de jobs:
  - Configurable para múltiples colas (ej. `risk`, `webhooks`).
  - Permite escalar horizontalmente los nodos que procesan jobs.
- Diseño de workers idempotentes:
  - `EvaluateRisk` y `WebhookNotifier` pueden re-intentarse sin efectos no deseados.
- Posible evolución:
  - Extraer `EvaluateRisk` a un microservicio / función serverless independiente:
    - API interna: `POST /internal/risk_evaluations`.
    - Mantener contrato claro: input = solicitud; output = score + decisión.

---

## 4. Resumen

- **Seguridad**:
  - No se logea información sensible.
  - Cifrado en reposo asumido a nivel de infraestructura; diseño preparado para cifrado por campo.
  - Cifrado en tránsito via HTTPS/TLS.

- **Mantenibilidad**:
  - Arquitectura modular basada en contextos y workers.
  - Lógica de negocio centralizada en `CreditApplications` + `Policies`.
  - Metas claras de testabilidad (≥ 90% coverage) y ejecución automática en CI/CD.

- **Escalabilidad**:
  - Separación síncrono / asíncrono para absorber carga.
  - Uso de jobs (Oban) como base para una futura estrategia **serverless**.
  - Workers idempotentes y fácilmente migrables a otros runtimes.

Esta vista de atributos sirve como **checklist arquitectónico** para validar que las decisiones futuras (nuevos países, nuevas reglas, nuevos integradores) no rompen los principios de seguridad, mantenibilidad y escalabilidad definidos para BravoMultipais.