# Vista de Datos – BravoMultipais

Esta vista describe cómo se representan, almacenan y relacionan los datos del sistema de **Solicitudes de Crédito Multipaís**, tanto a nivel conceptual como en la base de datos.

---

## 1. Diseño & Modelado

### 1.1 Principios de diseño de datos

- **Orientado al dominio**
  - El modelo se organiza alrededor de la entidad principal **Solicitud de Crédito** (`credit_applications`).
  - Se complementa con:
    - Usuarios / backoffice (`users`).
    - Jobs de background (Oban).
    - Intentos de webhook / notificaciones externas (`webhook_attempts`, opcional).

- **Separación entre datos internos y datos públicos**
  - La base de datos puede contener datos internos (ej. `bank_profile`) que **no se exponen directamente** en la API.
  - La API trabaja con una **proyección pública** que:
    - Simplifica el documento (DNI / Codice Fiscale / NIF…) a una representación segura.
    - Filtra el perfil bancario a unos pocos campos permitidos (ID externo, deuda total, saldo promedio, moneda).

- **Modelo evolutivo**
  - Uso de tipos flexibles (p. ej. campos JSON) para adaptarse a:
    - Nuevos países (ES, IT, PT, + futuros).
    - Nuevos atributos de riesgo o de perfil bancario.
  - Diseño de estados (`status`, `risk_score`) pensado para admitir nuevos valores sin romper el modelo.

- **Trazabilidad y auditoría**
  - Todas las entidades clave tienen `inserted_at` y `updated_at`.
  - Los intentos de webhook (opcional/futuro) se modelan para poder auditar cuándo, qué se envió y qué respondió el sistema externo.

---

## 2. Estructuras de datos (conceptual)

### 2.1 Entidad principal: Solicitud de Crédito

**Solicitud de Crédito** (Credit Application):

- **Identificación**
  - `id`: identificador único (UUID).
  - `external_reference`: referencia opcional a otro sistema (por ejemplo, un ID en un core bancario).

- **Datos del cliente**
  - `country`: país (por ejemplo `ES`, `IT`, `PT`).
  - `full_name`: nombre completo del solicitante.
  - `document`: estructura flexible que representa el documento (DNI, Codice Fiscale, NIF, etc.), almacenada como mapa/JSON.
    - Ejemplos por país:
      - ES: `{ "dni" | "nie" | "nif" : "..." }`
      - IT: `{ "codice_fiscale": "..." }`
      - PT: `{ "nif": "..." }`

- **Datos económicos**
  - `amount`: monto solicitado.
  - `monthly_income`: ingreso mensual.

- **Estado y riesgo**
  - `status`: estado de la solicitud dentro del flujo:
    - `CREATED`, `PENDING_RISK`, `UNDER_REVIEW`, `APPROVED`, `REJECTED`, etc.
  - `risk_score`: score numérico de riesgo (ej. 300–900 o similar).

- **Perfil bancario (interno)**
  - `bank_profile`: mapa/JSON con información agregada de comportamiento financiero.  
    Campos típicos:
    - `external_id`: identificador del cliente en un sistema bancario externo.
    - `total_debt`: deuda total (agregada).
    - `avg_balance`: saldo promedio.
    - `currency`: moneda usada (ej. `EUR`).
    - Otros campos internos que **no tienen por qué exponerse** externamente.

- **Metadatos**
  - `inserted_at`: fecha/hora de creación.
  - `updated_at`: fecha/hora de última actualización.

### 2.2 Proyección pública de la solicitud

Cuando se expone una solicitud vía API, no se devuelve el registro “crudo” de base de datos, sino una **vista pública**, que:

- Incluye:
  - `id`
  - `country`
  - `full_name`
  - `status`
  - `risk_score`
  - `amount`
  - `monthly_income`
  - `inserted_at` / `updated_at`
  - `external_reference`
- Documento:
  - En lugar de devolver el mapa completo, se expone una representación simplificada (por ejemplo, un string con el DNI/NIF/CF).
- Perfil bancario:
  - Sólo se devuelven campos seguros, típicamente:
    - `external_id`
    - `total_debt`
    - `avg_balance`
    - `currency`

De esta forma, el modelo de datos interno puede evolucionar sin comprometer la compatibilidad de la API ni exponer datos sensibles.

### 2.3 Otras estructuras relevantes

- **Usuario (User)**
  - Representa a:
    - Usuarios backoffice (quienes usan el panel LiveView).
    - Potenciales consumidores de API autenticados.
  - Campos principales:
    - `id`, `email`, `hashed_password`, `role`, timestamps.

- **Webhook Attempt (intento de webhook – opcional / futuro)**
  - Representa cada intento de notificación a un sistema externo cuando cambia el estado de una solicitud.
  - Campos típicos:
    - `id`
    - `application_id`
    - `target_url`
    - `payload` (JSON enviado)
    - `response_code`
    - `response_body` (opcional, truncado)
    - `attempts_count`
    - `last_attempt_at`
    - `inserted_at`

- **Jobs de background (Oban)**
  - Gestionan la evaluación de riesgo y el envío de webhooks.
  - Sus datos se guardan en tablas internas (`oban_jobs` y asociadas), manejadas por la librería; son parte del modelo de infraestructura.

---

## 3. Base de Datos

### 3.1 Tablas principales

#### 3.1.1 `credit_applications`

Tabla core donde se almacenan las solicitudes de crédito.

| Campo                | Tipo        | Descripción                                                    |
|----------------------|------------|----------------------------------------------------------------|
| `id`                 | UUID (PK)  | Identificador único de la solicitud                            |
| `country`            | varchar    | País (`ES`, `IT`, `PT`, etc.)                                  |
| `full_name`          | varchar    | Nombre completo del solicitante                                |
| `document`           | jsonb      | Documento (estructura flexible según el país)                  |
| `amount`             | numeric    | Monto solicitado                                               |
| `monthly_income`     | numeric    | Ingreso mensual del solicitante                                |
| `status`             | varchar    | Estado del flujo (CREATED, PENDING_RISK, APPROVED, etc.)       |
| `risk_score`         | integer    | Score numérico de riesgo                                       |
| `bank_profile`       | jsonb      | Perfil bancario agregado (uso interno)                         |
| `external_reference` | varchar    | Identificador externo opcional                                 |
| `inserted_at`        | timestamp  | Fecha/hora de creación                                         |
| `updated_at`         | timestamp  | Fecha/hora de última actualización                             |

#### 3.1.2 `users`

Tabla para gestionar usuarios y roles.

| Campo              | Tipo        | Descripción                                  |
|--------------------|------------|----------------------------------------------|
| `id`               | UUID (PK)  | Identificador de usuario                     |
| `email`            | varchar    | Correo electrónico de login                  |
| `hashed_password`  | varchar    | Contraseña hasheada                          |
| `role`             | varchar    | Rol (`backoffice`, `api_consumer`, etc.)     |
| `inserted_at`      | timestamp  | Fecha/hora de creación                       |
| `updated_at`       | timestamp  | Fecha/hora de última actualización           |

> En esta demo, la relación con `credit_applications` puede ser opcional.  
> En una versión más completa podría existir un campo `created_by_user_id` o similar.

#### 3.1.3 `webhook_attempts` (recomendado / futuro cercano)

Tabla propuesta para trazar notificaciones externas.

| Campo              | Tipo        | Descripción                                  |
|--------------------|------------|----------------------------------------------|
| `id`               | UUID (PK)  | Identificador del intento de webhook        |
| `application_id`   | UUID (FK)  | FK a `credit_applications.id`               |
| `target_url`       | varchar    | URL del sistema externo                      |
| `payload`          | jsonb      | JSON enviado                                 |
| `response_code`    | integer    | Código HTTP recibido                         |
| `response_body`    | text       | Cuerpo de respuesta (opcional)              |
| `attempts_count`   | integer    | Número de intentos realizados                |
| `last_attempt_at`  | timestamp  | Fecha/hora del último intento               |
| `inserted_at`      | timestamp  | Fecha/hora de creación del registro          |

### 3.2 Tablas de infraestructura (Oban y otras)

- **`oban_jobs` y tablas relacionadas**  
  - Gestionan:
    - Jobs pendientes y completados.
    - Estado, reintentos, backoff, etc.
  - Se consideran parte de la **capa de infraestructura**, pero son relevantes para:
    - Evaluación de riesgo en background.
    - Reenvío de webhooks de forma desacoplada del flujo síncrono.

---

## 4. Diagrama Entidad–Relación (ER)

A alto nivel, las entidades se relacionan de la siguiente forma:

```mermaid
erDiagram

  USERS ||--o{ CREDIT_APPLICATIONS : "crea / supervisa (opcional)"
  CREDIT_APPLICATIONS ||--o{ WEBHOOK_ATTEMPTS : "notificaciones de cambios de estado"

  USERS {
    uuid id
    string email
    string hashed_password
    string role
    timestamp inserted_at
    timestamp updated_at
  }

  CREDIT_APPLICATIONS {
    uuid id
    string country
    string full_name
    jsonb document
    numeric amount
    numeric monthly_income
    string status
    int risk_score
    jsonb bank_profile
    string external_reference
    timestamp inserted_at
    timestamp updated_at
  }

  WEBHOOK_ATTEMPTS {
    uuid id
    uuid application_id
    string target_url
    jsonb payload
    int response_code
    text response_body
    int attempts_count
    timestamp last_attempt_at
    timestamp inserted_at
  }