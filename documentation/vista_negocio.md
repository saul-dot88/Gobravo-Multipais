# Vista de Negocio – BravoMultipais (Motor de riesgo multipaís)

## 1. Objetivo

Diseñar y demostrar un **motor de solicitudes de crédito multipaís** (ES / IT / PT) que:

- Capture solicitudes de crédito de forma simple y coherente.
- Evalúe el riesgo en segundo plano con reglas por país.
- Exponga el resultado vía:
  - **Backoffice** para equipos internos.
  - **API REST** para integraciones externas.
- Permita **iterar rápido** sobre políticas de riesgo y monitorear su impacto.

---

## 2. Propósito

- Servir como **MVP funcional** para discutir con negocio, riesgo y tecnología:
  - Flujo de solicitud → evaluación → decisión → notificación.
  - Diferencias entre países (documentos, límites, umbrales).
- Reducir fricción entre equipos mediante un **lenguaje común**:
  - Misma entidad: `CreditApplication`.
  - Mismos estados: `CREATED`, `PENDING_RISK`, `UNDER_REVIEW`, `APPROVED`, `REJECTED`.
- Probar que el dominio está bien modelado para escalar:
  - Más países.
  - Más productos.
  - Más fuentes de datos (bancos, bureaus, scoring externos).

---

## 3. Convenciones

- **Países soportados inicialmente:** `ES`, `IT`, `PT`.
- **Estados de la solicitud:**
  - `CREATED`
  - `PENDING_RISK`
  - `UNDER_REVIEW`
  - `APPROVED`
  - `REJECTED`
- **Moneda interna de demo:** EUR (no se hace FX real; se asume contexto zona euro).
- **Entidad central:** `credit_application` con campos:
  - `country`, `full_name`, `document`, `amount`, `monthly_income`
  - `status`, `risk_score`, `bank_profile`, `external_reference`
- **Comunicación asíncrona:**
  - Evaluación de riesgo vía **Oban** (`EvaluateRisk` worker).
  - Notificación a sistemas externos vía **webhook** (`WebhookNotifier`).

---

## 4. Alcance del proyecto

### 4.1 Incluido

- **Backoffice Web (LiveView)**:
  - Crear nuevas solicitudes.
  - Filtrar solicitudes por país, estado, monto y fechas.
  - Ver detalle completo (datos, score, perfil bancario, timeline simulada).
  - Re-evaluar riesgo.
  - Re-enviar webhook manualmente.

- **API REST pública**:
  - `POST /api/applications` → crear solicitud.
  - `GET /api/applications/:id` → obtener vista pública.
  - `GET /api/applications` → listar con filtros.

- **Motor de riesgo simplificado**:
  - Cálculo de `risk_score` a partir de:
    - Relación monto / ingreso.
    - Parámetros de país.
  - Categorización:
    - Score alto → `APPROVED`.
    - Score medio → `UNDER_REVIEW`.
    - Score bajo → `REJECTED`.
  - Generación de `bank_profile` sintético (deuda total, saldo promedio, score bancario).

- **Integración asíncrona**:
  - Jobs encolados con Oban.
  - Notificación a un **endpoint externo simulado** vía webhook.
  - Timeline de eventos (creada, riesgo evaluado, estatus final, webhook reenviado).

### 4.2 Fuera de alcance (por ahora)

- Integraciones reales con:
  - Bureaus de crédito.
  - Open Banking / PSD2.
  - Core bancario.
- Gestión de múltiples productos por cliente.
- Orquestación multi-step (firma contratos, desembolso, etc.).
- Paneles productivos en Grafana / Prometheus (solo conceptualizados).

---

## 5. Hipótesis y Suposiciones

1. **Hipótesis de valor**
   - H1: Un motor común para ES/IT/PT reduce el **time-to-market** de nuevos países.
   - H2: Una vista unificada de solicitudes multipaís mejora la **operación de backoffice**.
   - H3: Un flujo asincrónico (jobs + webhooks) reduce acoplamiento con partners.

2. **Suposiciones**
   - Los países comparten un modelo de datos compatible (con variaciones mínimas).
   - Los partners externos pueden trabajar con un **modelo de request/response estable**.
   - Los volúmenes iniciales de solicitudes son manejables con una sola base de datos.
   - Los equipos de riesgo aceptan empezar con una versión **simplificada** de la política.

---

## 6. Visión

> “Un motor de originación ligero, multipaís y extensible, que permita lanzar y ajustar productos de crédito en semanas, no en meses.”

Características clave de la visión:

- **Configurable por país**: reglas encapsuladas en `Policies` y `Bank` contexts.
- **API-first**: todo lo que se puede hacer en el backoffice se puede automatizar vía API.
- **Observable**: cada solicitud deja trazabilidad de decisión y eventos.
- **Extensible**: añadir un nuevo país implica **sumar reglas**, no reescribir el core.

---

## 7. Requerimientos

### 7.1 Requerimientos funcionales

1. RF-01: Crear solicitudes de crédito indicando país, datos del cliente, monto e ingreso.
2. RF-02: Evaluar el riesgo de cada solicitud en segundo plano.
3. RF-03: Persistir el resultado de la evaluación (`risk_score`, `status`, `bank_profile`).
4. RF-04: Permitir que usuarios de backoffice consulten y filtren solicitudes.
5. RF-05: Exponer endpoints REST para:
   - Crear solicitudes.
   - Consultar solicitud por id.
   - Listar solicitudes con filtros.
6. RF-06: Enviar una notificación (webhook) a sistemas externos cuando cambie el estado.
7. RF-07: Permitir re-evaluar manualmente una solicitud desde el backoffice.
8. RF-08: Permitir re-enviar manualmente el webhook de una solicitud evaluada.

### 7.2 Requerimientos no funcionales (alto nivel)

1. RNF-01: Latencia percibida en UI:
   - Creación de solicitud < 1s (sin esperar evaluación).
2. RNF-02: Tiempo de evaluación:
   - Job de riesgo < 2s en promedio (en condiciones de demo).
3. RNF-03: Confiabilidad:
   - Reintentos configurables en los jobs.
4. RNF-04: Trazabilidad:
   - Logs por aplicación, score y cambios de estado.
   - Timeline visible en el backoffice.
5. RNF-05: Seguridad:
   - Autenticación para backoffice (scopes).
   - API protegida (auth a definir según contexto real).

---

## 8. Funcionalidades

### 8.1 Backoffice

- Formulario “Nueva solicitud” por país.
- Tabla de “Solicitudes recientes” con:
  - País, nombre, monto, ingreso, estado, score, fecha.
- Panel de detalle:
  - Datos del cliente.
  - Datos del crédito.
  - Score numérico.
  - Perfil bancario.
  - Timeline de eventos.
  - Botones:
    - “Re-evaluar riesgo”.
    - “Re-enviar webhook”.
- Filtros:
  - País, estado, rango de montos, rango de fechas, “solo evaluadas”.

### 8.2 API

- `POST /api/applications`
  - Payload: país, datos del cliente, monto, ingreso, referencia externa opcional.
  - Respuesta: versión pública (`id`, `status`, `risk_score` si existe, `document` simplificado).
- `GET /api/applications/:id`
  - Devuelve la vista pública.
- `GET /api/applications?country=ES&status=APPROVED&from_date=...`
  - Lista filtrada de aplicaciones públicas.

### 8.3 Motor de riesgo

- Worker `EvaluateRisk`:
  - Lee la solicitud por `application_id`.
  - Calcula `risk_score` según políticas por país.
  - Decide estado final (`APPROVED` / `UNDER_REVIEW` / `REJECTED`).
  - Enriquecer `bank_profile` con datos sintéticos.
  - Publica evento en PubSub (`status_changed`).

- Worker `WebhookNotifier`:
  - Llama a endpoint externo con payload público.
  - Registra resultado y actualiza timeline.

---

## 9. Casos de Uso

1. **CU-01 – Backoffice crea solicitud manual**
   - Actor: analista de backoffice.
   - Flujo:
     1. Entra al panel.
     2. Llena formulario de nueva solicitud.
     3. Envía.
     4. Ve la solicitud en la lista con estado `PENDING_RISK`.
     5. Tras unos segundos, ve el estado actualizado (`APPROVED` / `REJECTED` / `UNDER_REVIEW`).

2. **CU-02 – Partner crea solicitud vía API**
   - Actor: sistema externo (fintech / marketplace).
   - Flujo:
     1. POST `/api/applications` con datos del cliente y referencia externa.
     2. Recibe `201` con `id` y estado inicial.
     3. Espera webhook con decisión de riesgo.
     4. Actualiza su propio sistema.

3. **CU-03 – Analista revisa caso borderline**
   - Actor: analista de riesgo.
   - Flujo:
     1. Filtra solicitudes por estado `UNDER_REVIEW`.
     2. Abre detalle.
     3. Revisa score, perfil bancario y timeline.
     4. Decide si re-evaluar (por cambio de parámetros) o tomar acción manual fuera del sistema.

4. **CU-04 – Reenvío de webhook**
   - Actor: soporte técnico / integraciones.
   - Flujo:
     1. Abre detalle de una solicitud con riesgo evaluado.
     2. Da clic en “Re-enviar webhook”.
     3. Verifica que el partner externo recibe nuevamente la notificación.

---

## 10. Historias de Usuario (ejemplos)

1. **HU-01 – Backoffice crea solicitud**
   - *Como* analista de backoffice  
   - *quiero* crear una solicitud de crédito para un cliente de ES, IT o PT  
   - *para* que el motor de riesgo me sugiera si aprobarla, revisarla o rechazarla.

2. **HU-02 – Partner integra API**
   - *Como* partner externo  
   - *quiero* enviar solicitudes vía API y recibir un webhook con la decisión  
   - *para* integrar el flujo de crédito en mi propio front.

3. **HU-03 – Analista revisa borderline**
   - *Como* analista de riesgo  
   - *quiero* listar rápidamente las solicitudes con estado `UNDER_REVIEW`  
   - *para* priorizar las que requieren revisión manual.

4. **HU-04 – Soporte reenvía webhook**
   - *Como* ingeniero de integraciones  
   - *quiero* re-enviar manualmente el webhook de una solicitud ya evaluada  
   - *para* corregir fallos puntuales de comunicación sin intervenir la base de datos.

---

## 11. Costo vs Beneficio (visión de negocio)

### Costos (aproximados, cualitativos)

- **Desarrollo inicial**:
  - Modelado de dominio (contextos, políticas, workers).
  - UI de backoffice (LiveView).
  - API REST + webhooks.
- **Operación**:
  - Mantenimiento de infraestructura (Postgres, Oban, despliegues).
  - Ajuste continuo de reglas de riesgo.
- **Coordinación**:
  - Tiempo de squads de Riesgo, Negocio y Tecnología para alinear políticas.

### Beneficios esperados

- **Time-to-market**:
  - Reutilización del mismo core para varios países → lanzar un nuevo país implica principalmente ajustar reglas y textos, no reescribir todo.
- **Eficiencia operativa**:
  - Backoffice único para seguimiento multipaís.
  - Menos consultas manuales dispersas en distintos sistemas.
- **Calidad de decisiones**:
  - Misma lógica de riesgo por país, centralizada y versionable.
  - Fácil de instrumentar con métricas.
- **Facilidad de integración**:
  - API y webhooks claros → menos tiempo de integración con partners.
- **Escalabilidad futura**:
  - Base sólida para añadir fuentes de datos reales sin romper contratos con front / partners.

---

## 12. Racional y Métricas de Éxito

### Racional

- **Unificar** el flujo de solicitud de crédito multipaís en un solo motor reduce:
  - Duplicidad de código.
  - Errores de integración.
  - Tiempo de incorporación de cambios regulatorios o de política.
- **Separar** evaluación de riesgo en workers asincrónicos:
  - Permite escalar horizontalmente sólo la parte intensiva.
  - Minimiza la latencia percibida en UI/API.
- **Exponer** todo vía API y backoffice:
  - Permite tanto uso interno (operaciones) como externo (partners, frontends).

### Métricas (propuestas)

1. **Tiempo medio de decisión (TMD)**  
   - Desde `CREATED` hasta estado final (`APPROVED` / `REJECTED` / `UNDER_REVIEW`).
   - Objetivo demo: < 5 segundos.

2. **% de solicitudes en UNDER_REVIEW**  
   - Indica afinamiento de umbrales:
     - Muy alto → reglas poco discriminantes.
     - Muy bajo → poco control manual.

3. **Tasa de automatización**  
   - (# solicitudes con decisión automática) / (# total solicitudes).
   - Objetivo: maximizar sin perder control de riesgo.

4. **Errores de integración (webhook)**  
   - # de reintentos / fallos de notificación.
   - Objetivo: tendencia decreciente tras estabilizar la integración.

5. **Uso de backoffice**  
   - # consultas por analista / día.
   - % solicitudes filtradas por estado / país.

6. **Satisfacción de stakeholders** (cualitativa)  
   - Feedback de:
     - Riesgo: claridad de métricas y reglas.
     - Negocio: flexibilidad para nuevos productos/países.
     - Tech: facilidad de mantenimiento y despliegue.

---

> Este documento de vista de negocio sirve como **puente** entre lo que ya construimos a nivel técnico (contexts, workers, LiveView, API) y el lenguaje que entienden **Product, Negocio y Riesgo** para evaluar si vale la pena evolucionar este MVP hacia un producto interno real.