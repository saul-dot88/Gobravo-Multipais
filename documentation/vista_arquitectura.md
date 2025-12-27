# Vista de Arquitectura – BravoMultipais

## 1. Introducción

Este documento describe la **arquitectura técnica** del sistema BravoMultipais, un motor de solicitudes de crédito multipaís (ES / IT / PT) construido sobre **Elixir + Phoenix + LiveView**, con **PostgreSQL** como base de datos y **Oban** como motor de jobs asíncronos.

El objetivo es dejar claro **cómo está organizado el sistema**, cómo se conectan sus piezas y qué decisiones de diseño se han tomado para soportar los casos de uso de negocio.

---

## 2. Audiencia

- **Product Owner / Business**  
  Entender el mapa general de componentes y cómo se conectan.

- **Equipo de Desarrollo**  
  Consultar decisiones clave y puntos de extensión (nuevos países, nuevas reglas, nuevas integraciones).

- **DevOps / SRE**  
  Ubicar puntos de despliegue, monitorización y dependencias externas.

- **QA / Automatización**  
  Identificar flujos principales y puntos donde se requieren pruebas E2E / contract tests.

---

## 3. Objetivos y racional de diseño

### 3.1 Objetivos

1. **Soportar múltiples países** con reglas de riesgo diferenciadas.
2. Proveer:
   - Una **UI backoffice** para gestión y exploración de solicitudes.
   - Una **API REST** (`/api/applications`) para integraciones externas.
3. Permitir **evaluación de riesgo asíncrona** y notificación por **webhooks**.
4. Mantener un diseño **modular**, fácil de extender y probar.

### 3.2 Racional de arquitectura

- Se adopta el patrón **“Phoenix + Contexts”**:
  - La lógica de negocio vive en **contextos** (`CreditApplications`, `Policies`, `Bank`), no en controladores o LiveViews.
- Las operaciones costosas o lentas (evaluar riesgo, enviar webhooks) se mueven a **jobs Oban**, para:
  - Asegurar una buena experiencia de usuario.
  - Permitir reintentos y escalado horizontal.
- Se separa la **vista backoffice** (`ApplicationsLive`) de la **API pública** (`ApplicationController`), consumiendo ambos el mismo contexto de dominio.

---

## 4. Nivel 1 / 2 – Vista de alto nivel

### 4.1 Función del sistema

BravoMultipais permite:

1. **Crear solicitudes de crédito** desde:
   - Backoffice (LiveView).
   - API externa.
2. **Evaluar automáticamente el riesgo**:
   - Cálculo de un `risk_score`.
   - Cambio de estado: `APPROVED`, `UNDER_REVIEW`, `REJECTED`.
3. **Consultar solicitudes**:
   - Listado, filtros, detalle y timeline.
   - Exposición de un view “público” (sin datos internos sensibles).
4. **Disparar webhooks** cuando la evaluación termina (para integrarse con otros sistemas).

### 4.2 Componentes y relaciones (alto nivel)

```mermaid
flowchart TB
  subgraph PhoenixApp["BravoMultipais Web<br/>(Phoenix)"]
    lv["ApplicationsLive<br/>(LiveView backoffice)"]
    api["ApplicationController<br/>(/api/applications)"]
    usersLV["UserLive.*<br/>(login, registro, settings)"]

    subgraph Contexts["Contexts / Dominios"]
      ca["CreditApplications<br/>(Contexto)"]
      acc["Accounts<br/>(Contexto)"]
      bankC["Bank<br/>(Contexto)"]
      pol["Policies<br/>(Reglas por país)"]
    end

    repo["Repo<br/>(Ecto)"]
    obanCli["Oban<br/>(Cliente)"]
    mailer["Mailer"]
  end

  db[(PostgreSQL)]
  obanQ[(Cola Oban)]
  workerRisk["Workers.EvaluateRisk"]
  workerWebhook["Workers.WebhookNotifier"]

  %% UI/API → Contextos
  lv --> ca
  api --> ca
  usersLV --> acc

  %% Accounts / auth
  acc --> repo
  usersLV --> mailer

  %% CreditApplications
  ca --> pol
  ca --> bankC
  ca --> repo
  ca --> obanCli

  %% Bank & Policies
  bankC --> repo
  pol --> bankC

  %% Infra
  obanCli --> obanQ
  workerRisk --> db
  workerRisk --> bankC
  workerRisk --> pol
  workerRisk --> ca

  workerWebhook --> ca

  repo --> db


  ## 6. Interfaz de Usuario

### 6.1 Journeys principales

1. **Backoffice – Crear y evaluar solicitudes**
   - El usuario backoffice entra al panel.
   - Captura país, nombre, documento, monto, ingreso.
   - El sistema crea la solicitud `PENDING_RISK` y encola evaluación.
   - La tabla de **“Solicitudes recientes”** se actualiza automáticamente cuando llega el evento `status_changed`.
   - Desde el detalle puede:
     - Ver el timeline.
     - Ver/ocultar JSON completo.
     - Re-evaluar el riesgo.
     - Re-enviar el webhook (cuando hay score).

2. **Consumidor externo – API**
   - Un sistema externo hace `POST /api/applications`.
   - Recibe un payload público (sin datos internos).
   - Más tarde hace `GET /api/applications/:id` para consultar estado y score.
   - Opcionalmente se suscribe a un webhook para recibir notificaciones.

### 6.2 Wireframes / Mockups (conceptual)

**UI backoffice (LiveView):**
- Panel izquierdo: **Nueva solicitud**.
- Panel derecho:
  - Cabecera y filtros.
  - Tabla de **solicitudes recientes**.
  - Panel de detalle con:
    - Badge de estado.
    - Resumen de riesgo: `APPROVED (score 776 – perfil sano ES…)`.
    - Información bancaria sintetizada.
    - Timeline (creado, riesgo evaluado, estado final, webhook reenviado).

### 6.3 Design System (simplificado)

- **Tokens visuales**
  - Colores base: escala `slate` para fondos y texto.
  - Acciones primarias: `indigo`.
  - Estados:
    - `APPROVED` → verdes (`emerald`).
    - `UNDER_REVIEW` → amarillos (`amber`).
    - `REJECTED` → rojos (`rose`).

- **Componentes clave**
  - `status_badge/1` – badge chip con color por estado.
  - `risk_score_chip/1` – chip con score + etiqueta (Alto, Medio, Bajo).
  - `stat_card/2` – tarjetas de KPIs (total, aprobadas, rechazadas).
  - Panel de detalle con **timeline vertical**.

- **Principios**
  - Layout completamente responsive:
    - **Mobile**: “Nueva solicitud” arriba, lista y detalle debajo.
    - **Desktop**: “Nueva solicitud” a la izquierda, lista + detalle a la derecha.

---

## 7. Integración con otros sistemas

- **Entradas**
  - API REST `/api/applications`:
    - Crea solicitudes y las devuelve en formato público.
  - Eventual integración con:
    - Motor de fraude / scoring externo (vía `Bank` o `Policies`).

- **Salidas**
  - **Webhooks**:
    - Notificación de cambios de estado y score.
    - Payload público, preparado para evolucionar.

- **Cola de jobs (Oban)**
  - Permite tratar la evaluación de riesgo y webhooks como **servicios internos desacoplados**.

- **Observabilidad (futuro cercano)**
  - Exportación de métricas a **Prometheus**.
  - Dashboards en **Grafana**:
    - Número de solicitudes por país/estado.
    - Latencia media de evaluación.
    - Tasa de errores en workers.

---

## 8. Migraciones

- Uso de **Ecto Migrations** para:
  - Crear / modificar tablas de `applications`, `users`, `oban_jobs`, etc.

- **Lineamientos**
  - Migraciones siempre **idempotentes y reversibles** (`change/0` preferible).
  - Añadir campos nuevos como `nullable` y rellenar progresivamente cuando sea posible.

- **Evoluciones previstas**
  - Nuevos países → nuevos valores de `country` + reglas en `Policies`.
  - Nuevos atributos de riesgo → columnas adicionales o campos `JSONB`.

---

## 9. Roles y Responsabilidades

- **Backoffice**
  - Crear solicitudes de prueba / supervisar flujos de negocio.
  - Ver detalle y timeline.
  - Re-evaluar riesgo, re-enviar webhooks.

- **Consumidores de API**
  - Integrar `/api/applications` en sus propios sistemas.
  - Recibir webhooks y actualizar su estado interno.

- **Equipo de Desarrollo**
  - Mantener contextos, workers, API y LiveView.
  - Extender reglas por país.
  - Gestionar migraciones y refactors.

- **DevOps / SRE**
  - Despliegues, configuraciones de runtime.
  - Monitorización (logs, métricas) y alertas.

---

## 10. Deployments e instalación

- **Despliegue recomendado**
  - Phoenix Release dentro de un contenedor (Docker).
  - Base de datos externa (PostgreSQL administrado).
  - Redis u otro backend opcional si se usara para PubSub distribuido.

- **Pasos a alto nivel**
  1. Ejecutar migraciones de Ecto.
  2. Configurar variables:
     - `DATABASE_URL`
     - `SECRET_KEY_BASE`
     - Config de Oban (colas y concurrencia).
     - URLs de webhooks / integraciones externas.
  3. Levantar servicio Phoenix (`mix phx.server` o release).
  4. Configurar monitorización (Prometheus exporter, logging centralizado).

---

## 11. Riesgos

- **Complejidad de reglas de riesgo**  
  A medida que se añadan países y productos, `Policies` puede crecer en complejidad.  
  → Mitigar con:
  - Modularización interna (por país / producto).
  - Tests intensivos de regresión.

- **Dependencia de integraciones externas**  
  Si el perfil bancario o el scoring futuro dependen de sistemas externos, cualquier latencia o caída afectará tiempos de evaluación.  
  → Mitigar con:
  - Timeouts y reintentos en workers.
  - Circuit breakers / colas intermedias.

- **Crecimiento de volumen de jobs**  
  Alta tasa de solicitudes puede saturar colas de Oban.  
  → Mitigar con:
  - Configuración de múltiples colas y workers.
  - Posible migración a infraestructura serverless especializada.

- **Exposición de datos sensibles**  
  Errores en la proyección pública (`to_public/1`) podrían filtrar datos internos.  
  → Mitigar con:
  - Revisiones de seguridad.
  - Tests de contrato para los JSON públicos.
  - Revisión de logs para evitar filtrado de documentos y perfiles bancarios.