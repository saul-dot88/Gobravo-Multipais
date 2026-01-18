# BravoMultipais – Demo de originación y evaluación de riesgo multipaís

Este proyecto implementa una solución demo de **solicitudes de crédito multipaís (ES / IT / PT)** con:

- **Backoffice web** (LiveView) para crear, filtrar y revisar solicitudes.
- **API pública** para crear y consultar solicitudes desde sistemas externos.
- **Motor de riesgo asíncrono** basado en workers (Oban).
- **Notificación vía webhooks** para integraciones downstream.

Está pensado como una base sólida para discutir diseño, arquitectura, atributos no funcionales y evolución hacia más países/productos.

---

## 1. Instrucciones de instalación y ejecución

### 1.1 Requisitos previos

- Elixir y Erlang instalados (por ejemplo usando `asdf`)
- PostgreSQL en local (o accesible vía red)
- Node.js (si se recompila la parte de assets)
- Git (para clonar el repositorio)

Versión de referencia (adaptar si es distinto en tu entorno):

- Elixir 1.15+ / 1.16+
- Phoenix 1.7+ / 1.8+
- PostgreSQL 13+

### 1.2 Clonar y configurar

```bash
git clone <URL_DEL_REPO> bravo_multipais
cd bravo_multipais

Configura tu base de datos en config/dev.exs, algo como:

config :bravo_multipais, BravoMultipais.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "bravo_multipais_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

Configura también Oban y cualquier otra integración necesaria en config/config.exs o config/dev.exs.

1.3 Instalar dependencias

mix deps.get
cd assets && npm install && cd ..

1.4 Crear y migrar la base de datos

mix ecto.create
mix ecto.migrate

(Si existe una tarea tipo mix ecto.setup, se puede usar en su lugar).

1.5 Ejecutar la aplicación

mix phx.server
# o con recarga en dev:
iex -S mix phx.server

Por defecto, la app estará en:
	•	Backoffice / LiveView: http://localhost:4000
	•	API (ejemplo): POST /api/applications, GET /api/applications/:id

1.6 Ejecutar los tests

MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
mix test

1.7 Usuarios de demo (seeds) y credenciales

El archivo priv/repo/seeds.ex define usuarios de prueba para poder acceder rápidamente al backoffice y/o probar la API sin tener que pasar por flujos de registro.

Importante: ejecuta primero:

mix ecto.seed

para insertar estos usuarios de demo en la base de datos.

Ejemplo de credenciales típicas (ajusta a lo que tengas realmente en seeds.ex):

Rol	Email	Password	Notas
backoffice	backoffice@example.com	backoffice123	Acceso al panel LiveView de solicitudes
api_client*	api_client@example.com	api123456	(Opcional) Usuario pensado para consumir la API

*Si no tienes un usuario específico para la API en seeds.ex, puedes crear uno o eliminar esta fila de la tabla.

Recomendación: abre priv/repo/seeds.ex, verifica las credenciales reales que estás insertando (email, password, rol) y actualiza esta tabla para que el README quede 100% alineado con tu código.

## Mailbox de desarrollo (Swoosh)

En entorno de desarrollo la app expone un **MailBox** para inspeccionar correos sin necesidad de un proveedor externo.

- Ruta: `http://localhost:4000/dev/mailbox`
- Está habilitado solo cuando `config :bravo_multipais, dev_routes: true`.

Uso típico:

1. Registras un usuario o solicitas un inicio de sesión (magic link / email de prueba).
2. En vez de enviar el correo a un SMTP real, **Swoosh Mailbox** lo captura.
3. Desde `http://localhost:4000/dev/mailbox` puedes:
   - Ver el listado de correos enviados.
   - Abrir el contenido HTML / texto.
   - Copiar enlaces (por ejemplo, links de login o verificación).

Esto permite probar **flujos de autenticación y notificaciones por correo** sin configurar credenciales externas ni ensuciar buzones reales.

---

## Acciones de Backoffice: Re-evaluar riesgo y Re-enviar webhook

En el panel de backoffice (LiveView) cada solicitud tiene acciones que simulan cómo operaría un equipo de riesgo / operaciones sobre las aplicaciones ya creadas.

### Re-evaluar riesgo

Botón: **“Re-evaluar riesgo”**

**Qué hace funcionalmente**

- Toma la solicitud actual (por `id`).
- Encola un **job de Oban** para recalcular el riesgo (mismo flujo que la evaluación inicial).
- Cuando el worker termina:
  - Actualiza `risk_score`, `status` y `bank_profile` en la base de datos.
  - Publica un evento en PubSub (`topic: "applications"`) para notificar al panel.
  - El LiveView actualiza:
    - La tabla de “Solicitudes recientes”.
    - El detalle de la solicitud.
    - El timeline con un nuevo evento (“Riesgo re-evaluado”, etc.).

**Por qué se hace así**

- La evaluación de riesgo puede ser costosa o depender de servicios externos → se ejecuta **fuera del request** vía Oban.
- Es **idempotente a nivel de negocio**: cada re-evaluación recalcula el estado en función de los datos actuales y reglas vigentes.
- El backoffice ve el efecto casi en tiempo real gracias a PubSub, sin recargar la página.

**Trade-offs**

- La respuesta del botón no es síncrona: el cambio de estado tarda lo que tarde el job.
- A cambio, el sistema es más robusto frente a:
  - Timeouts, reintentos, picos de carga.
  - Posibles futuras integraciones con motores de scoring externos.

---

### Re-enviar webhook

Botón: **“Re-enviar webhook”** (visible cuando la solicitud ya tiene `risk_score` / estado final).

**Qué hace funcionalmente**

- Verifica que la solicitud:
  - Existe.
  - Tiene un `status` evaluado (no `PENDING_RISK`).
- Obtiene la **vista pública** de la aplicación (proyección sin datos internos sensibles).
- Encola un **job de Oban** encargado de:
  - Construir el payload público (id, país, status, score, `external_reference`, etc.).
  - Hacer un `POST` al endpoint configurado de webhook (simulando el sistema cliente).
  - Registrar el resultado (éxito / error) en logs y en el timeline de la solicitud.

**Por qué se hace así**

- El webhook:
  - No bloquea la UI ni el flujo principal de negocio.
  - Es **reintetable**: si el sistema externo está caído o responde con error, el job puede reintentar según la política de Oban.
- El payload se genera a partir de una **proyección pública**, lo que reduce el riesgo de filtrar datos internos o sensibles.
- El botón permite al operador backoffice **recuperar integraciones** que fallaron en el pasado (ej. “cliente no recibió la notificación, re-enviar”).

**Trade-offs y decisiones**

- **Asíncrono**: el usuario del backoffice no ve el resultado al instante, pero puede:
  - Revisar logs.
  - Ver la entrada en el timeline cuando se complete.
- **Modelado simple**: para el MVP se asume un solo endpoint de webhook por entorno.
  - En una versión más avanzada podría haber:
    - Distintos endpoints por cliente.
    - Versionado del payload.
    - Firmas HMAC para validar autenticidad en el sistema receptor.

---

## Resumen de flujo end-to-end con estas acciones

1. **Crear solicitud** (Backoffice o API).
2. **Encolar evaluación de riesgo** (automática).
3. **Worker de riesgo** calcula score y status, actualiza DB, emite eventos.
4. **UI backoffice** se actualiza (tabla + detalle + timeline).
5. **Webhook automático** (si aplica) notifica al sistema externo.
6. **Backoffice puede:**
   - Re-evaluar riesgo (cambio de política, nueva info, etc.).
   - Re-enviar el webhook (si el sistema cliente tuvo problemas).

Este ciclo muestra que el sistema está pensado para:
- Separar **interacciones humanas** (UI) de **procesos técnicos** (workers).
- Mantener el flujo **observable y recuperable**, incluso cuando algo falla fuera de nuestro control.

⸻

2. Supuestos

Esta demo se construye con las siguientes suposiciones:
	•	Alcance funcional acotado: se centra en un flujo relativamente simple de:
	•	Creación de solicitud.
	•	Evaluación de riesgo.
	•	Consulta de estado y score.
	•	Países soportados: España (ES), Italia (IT) y Portugal (PT).
	•	Producto: un único tipo de crédito de consumo (mismo modelo para los 3 países).
	•	Reglas de riesgo simplificadas:
	•	El motor calcula un risk_score numérico.
	•	A partir de ese score deriva un status final: APPROVED, UNDER_REVIEW, REJECTED.
	•	Datos bancarios simulados:
	•	El bank_profile se construye en el worker como un mapa/JSON sintético (score, deuda, saldo medio…).
	•	Webhooks simulados:
	•	El envío de webhooks se hace mediante un worker (WebhookNotifier) pensado para integraciones futuras.
	•	Sin multi-tenant duro:
	•	El campo country diferencia mercados, pero no se ha modelado una separación estricta por tenant.

Todo esto se puede endurecer o refinar en una evolución futura, pero sirve para la conversación técnica (arquitectura, data, riesgo, etc.).

⸻

3. Modelo de datos (vista general)

3.1 Entidad principal: credit_applications

Tabla central del dominio de solicitudes de crédito.

Campos principales (conceptualmente):
	•	id (UUID): identificador único.
	•	country (string): "ES" | "IT" | "PT".
	•	full_name (string): nombre del solicitante.
	•	document (jsonb): documento identificativo (estructura varía por país).
	•	ES: %{"dni" => "..."}
	•	IT: %{"codice_fiscale" => "..."}
	•	PT: %{"nif" => "..."}
	•	amount (numeric/decimal): monto solicitado.
	•	monthly_income (numeric/decimal): ingreso mensual declarado.
	•	status (string):
	•	CREATED
	•	PENDING_RISK
	•	UNDER_REVIEW
	•	APPROVED
	•	REJECTED
	•	risk_score (int, nullable): score calculado por el motor.
	•	bank_profile (jsonb, nullable): perfil bancario sintetizado:
	•	score, total_debt, avg_balance, currency, external_id, etc.
	•	external_reference (string, nullable): referencia externa opcional.
	•	inserted_at, updated_at (timestamp): audit básico.

3.2 Relación con otros componentes

A nivel conceptual:
	•	credit_applications se relaciona con:
	•	Workers de riesgo (Oban jobs) que:
	•	leen la aplicación,
	•	calculan score,
	•	actualizan status y risk_score,
	•	publican eventos en PubSub.
	•	Webhooks: se encolan jobs para notificar cambios de estado.

Nota: el archivo de migración de credit_applications concreta los tipos y constraints exactos (índices, NOT NULL, defaults).

⸻

4. Decisiones técnicas

4.1 Stack principal
	•	Phoenix + LiveView:
	•	Backoffice en tiempo real para ver solicitudes, filtros y detalle.
	•	No hay SPA separada; todo el panel se resuelve con LiveView.
	•	Ecto + PostgreSQL:
	•	Modelo relacional clásico para solicitudes.
	•	Uso de jsonb para campos semi-estructurados (document, bank_profile).
	•	Oban:
	•	Framework de jobs en base de datos para:
	•	Evaluación de riesgo (EvaluateRisk).
	•	Reenvío de webhooks (WebhookNotifier).
	•	Permite reintentos, backoff, aislamiento de fallos y monitorización.

4.2 Contextos y modularidad
	•	BravoMultipais.CreditApplications:
	•	Contexto principal del dominio de solicitudes.
	•	Expone funciones como:
	•	list_applications/1
	•	get_application_public/1
	•	create_application/1
	•	Implementa to_public/1 para proyectar el modelo interno a un JSON público seguro.
	•	BravoMultipais.CreditApplications.Queries y .Commands:
	•	Separan lectura/escritura para dejar claro:
	•	dónde se consulta,
	•	dónde se aplican reglas y cambios de estado.
	•	BravoMultipais.Workers.EvaluateRisk:
	•	Encapsula la lógica de riesgo asíncrono (dominio + persistencia + eventos).
	•	BravoMultipaisWeb.ApplicationsLive:
	•	Backoffice LiveView para el equipo interno.
	•	BravoMultipaisWeb.ApplicationController:
	•	API REST pública para creación/consulta de solicitudes.

4.3 Proyección pública vs modelo interno

Se tomó la decisión de no exponer el modelo Ecto tal cual:
	•	to_public/1:
	•	Devuelve un mapa con sólo los campos seguros para API/Backoffice externo.
	•	Normaliza document (por país) y sanitiza bank_profile para evitar filtrar datos internos.
	•	La API y el LiveView pueden reutilizar esta proyección cuando haga falta.

⸻

5. Consideraciones de seguridad

5.1 Protección de datos sensibles
	•	Documentos de identidad:
	•	Se almacenan en document (jsonb).
	•	Se evita loguear el mapa completo en logs de producción.
	•	Perfiles bancarios (bank_profile):
	•	Se exponen sólo los campos necesarios en la vista pública (ej.: score agregado, deuda, saldo promedio).
	•	Internamente se puede guardar más detalle, pero la proyección pública lo filtra.

5.2 Logs
	•	Se evita incluir:
	•	Documentos completos.
	•	Perfiles bancarios detallados.
	•	Los logs se centran en:
	•	IDs de solicitud.
	•	Estados y resultado de jobs.
	•	Mensajes de error de alto nivel.

5.3 Transporte y configuración
	•	Entorno real:
	•	Se asume despliegue detrás de HTTPS (TLS terminado en LB o reverse proxy).
	•	Secretos:
	•	SECRET_KEY_BASE, credenciales de DB y claves de webhooks deben gestionarse vía variables de entorno / vault.
	•	Webhooks:
	•	Se recomienda:
	•	Firmar los payloads con HMAC.
	•	Permitir validaciones de origen en el consumidor.

5.4 Autenticación y autorización
	•	El backoffice está detrás de un mecanismo de autenticación (current_scope + role).
	•	ApplicationsLive muestra información adicional (bancaria, score) solo a usuarios con rol backoffice.
	•	La API debería protegerse con:
	•	Token de servicio / API key.
	•	O autenticación OAuth2 / JWT, según el contexto real (no detallado en la demo).

⸻

6. Escalabilidad y grandes volúmenes de datos

Aunque esta es una demo, el diseño apunta a escalar razonablemente bien.

6.1 Dimensiones de volumen
	•	Alto volumen de:
	•	Solicitudes de crédito (credit_applications).
	•	Jobs de riesgo (Oban).
	•	Eventos de webhook.

6.2 Estrategias de escalado
	•	Aplicación Phoenix:
	•	Puede escalar horizontalmente (múltiples réplicas) detrás de un balanceador.
	•	PubSub puede apoyarse en Redis u otro backend para cluster.
	•	Base de datos:
	•	Índices por:
	•	country, status, inserted_at.
	•	Permiten filtros eficientes en la vista de backoffice y en la API.
	•	A largo plazo:
	•	Particionamiento por fecha / país.
	•	Réplicas de lectura para reportes.
	•	Oban (jobs):
	•	Permite múltiples colas y niveles de concurrencia:
	•	Ej. :risk_evaluation, :webhooks.
	•	Se puede subir el número de workers para procesar más evaluaciones en paralelo.
	•	Webhooks:
	•	Encolados como jobs:
	•	Se reintentan en caso de fallo.
	•	Se desacoplan de la latencia de servicios externos.

6.3 Manejo de grandes volúmenes
	•	El backoffice ofrece filtros por:
	•	País, estado, montos, rango de fechas, “solo evaluadas”.
	•	La API puede paginar resultados en endpoints de lista (si se habilitan).
	•	Los jobs permiten:
	•	Procesar evaluaciones de riesgo de forma incremental.
	•	No bloquear el flujo online de creación de solicitudes.

⸻

7. Concurrencia, colas, caché y webhooks

7.1 Concurrencia
	•	Elixir/Erlang permiten:
	•	Procesar muchas solicitudes concurrentes gracias a procesos ligeros.
	•	A nivel de dominio:
	•	Una solicitud de crédito se trata como unidad de trabajo:
	•	Creación: transacción Ecto.
	•	Evaluación de riesgo: job Oban independiente.
	•	Se evita el bloqueo fuerte:
	•	El usuario no espera a que termine la evaluación de riesgo para obtener respuesta.

7.2 Colas (Oban)
	•	Se usa Oban para:
	•	EvaluateRisk:
	•	Lee una credit_application en estado PENDING_RISK.
	•	Calcula un score.
	•	Actualiza status y risk_score.
	•	Publica un evento en PubSub (status_changed) para refrescar el LiveView.
	•	WebhookNotifier:
	•	Encola notificaciones hacia sistemas externos cuando hay cambios de estado/score.
	•	Ventajas:
	•	Reintentos automáticos.
	•	Backoff exponencial configurable.
	•	Aislamiento de fallos externos.
	•	Monitorización y dashboards de jobs (via Oban Web / Pro en un proyecto real).

7.3 Caché
	•	En esta demo no se introduce un caché fuerte (tipo Redis) por simplicidad.
	•	Sin embargo, la arquitectura admite:
	•	Cachear vistas agregadas (ej. contadores por país/estado).
	•	Cachear respuestas de API de solo lectura en un reverse proxy.

Se ha priorizado mantener la lógica simple y consistente sobre añadir demasiadas capas.

7.4 Webhooks
	•	Estrategia de webhooks:
	1.	Cuando cambia el estado/score de una solicitud, se puede:
	•	Registrar el evento en BD.
	•	Encolar un job de WebhookNotifier.
	2.	WebhookNotifier:
	•	Construye un payload público (no datos internos).
	•	Realiza el POST al endpoint configurado del sistema externo.
	•	Maneja reintentos en caso de error (timeouts, 5xx, etc.).
	•	Beneficio:
	•	Los sistemas externos no necesitan estar “pegados” al ciclo de vida online de la solicitud.
	•	Pueden reaccionar a eventos de negocio (aprobación, rechazo, etc.) de forma asíncrona.

⸻

8. Resumen

Este proyecto sirve como demo de:
	•	Diseño orientado a dominios (contexto CreditApplications).
	•	Separación de lectura/escritura (Queries/Commands, workers).
	•	Uso de LiveView para backoffice con actualización en tiempo real.
	•	Uso de jobs (Oban) para desacoplar evaluaciones de riesgo y webhooks.
	•	Modelo de datos simple pero extensible, preparado para más países y productos.
	•	Preocupaciones de seguridad, escalabilidad y observabilidad integradas desde el diseño.

A partir de esta base, es sencillo:
	•	Añadir nuevos países y reglas de riesgo.
	•	Endurecer la seguridad (auth, firma de webhooks, políticas de datos).
	•	Escalar a entornos de producción con mayor volumen de solicitudes y jobs.


## Configuración rápida (variables de entorno)

- `WEBHOOK_URL` (opcional): endpoint receptor del webhook (default: `http://localhost:4001/webhooks/applications`)
- `SKIP_WEBHOOKS` (opcional): si es `true|1|TRUE`, deshabilita envíos HTTP reales (útil en dev/offline)


### Dedupe / Idempotencia (WebhookNotifier)

El webhook se procesa como job de Oban (cola `:webhooks`) y usa un `unique` de 60s por:

- `application_id`
- `source` (`auto` | `manual`)

Esto evita el "spam" del botón de re-envío (no encola el mismo `manual` múltiples veces en 60s),
pero **no bloquea** el webhook automático del flujo de negocio.

En otras palabras:
- auto y manual pueden coexistir
- manual se dedupea para evitar clicks repetidos

**Auto vs Manual**
- `source=auto`: se encola automáticamente cuando el riesgo termina (evento de negocio).
- `source=manual`: se encola desde el backoffice para recuperación operativa (reintento controlado).


## Cómo probar el flujo completo (manual)

1) Crea una solicitud y espera a que el riesgo cambie de `PENDING_RISK` a estado final.
2) En el detalle, usa:
   - **Re-evaluar riesgo**: re-encola el job de riesgo (si ya está final, el worker hace early-exit).
   - **Re-enviar webhook**: encola el webhook con `source=manual` (dedupe 60s).

Tip: si estás desarrollando sin receptor real, usa `SKIP_WEBHOOKS=true`.

Nota: `EvaluateRisk` hace early-exit si la solicitud ya está en estado final (idempotencia operativa).