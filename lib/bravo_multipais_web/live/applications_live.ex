defmodule BravoMultipaisWeb.ApplicationsLive do
  use BravoMultipaisWeb, :live_view

  on_mount {BravoMultipaisWeb.UserAuth, :require_backoffice}

  alias BravoMultipais.CreditApplications
  alias BravoMultipais.CreditApplications.{Application, Queries}
  alias BravoMultipais.Workers.{EvaluateRisk, WebhookNotifier}
  alias BravoMultipaisWeb.Endpoint

  @topic "applications"
  @default_per_page 20

  @risk_copy %{
    "ES" => %{
      "APPROVED" => "perfil sano ES – endeudamiento y ratios dentro de lo esperado",
      "UNDER_REVIEW" => "caso borderline ES – requiere revisión manual por ratios al límite",
      "REJECTED" => "riesgo alto ES – fuera de los parámetros de la política"
    },
    "IT" => %{
      "APPROVED" => "profilo sano IT – carga de deuda razonable para el ingreso",
      "UNDER_REVIEW" => "caso borderline IT – conviene mirar el expediente con detalle",
      "REJECTED" => "rischio alto IT – no cumple con la política interna"
    },
    "PT" => %{
      "APPROVED" => "perfil saudável PT – score externo y dívida em níveis confortáveis",
      "UNDER_REVIEW" => "caso para revisão PT – indicadores de risco no limite",
      "REJECTED" => "risco elevado PT – fora da política de concessão"
    },
    "DEFAULT" => %{
      "APPROVED" => "perfil sano – dentro de política",
      "UNDER_REVIEW" => "caso borderline – revisar manualmente",
      "REJECTED" => "riesgo alto – fuera de política"
    }
  }

  # ─────────────────────────────────────────────
  # mount
  # ─────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    filters = %{}
    page = 1
    per_page = @default_per_page

    page_data = CreditApplications.list_applications(filters, page: page, per_page: per_page)

    socket =
      socket
      |> assign(
        applications: page_data.entries,
        stats: build_stats(page_data.entries),
        form: %{
          "country" => "ES",
          "full_name" => "",
          "document_value" => "",
          "amount" => "",
          "monthly_income" => ""
        },
        current_scope: scope,
        countries: ["ES", "IT", "PT"],
        statuses: ["CREATED", "PENDING_RISK", "UNDER_REVIEW", "APPROVED", "REJECTED"],
        filter_country: nil,
        filter_status: nil,
        filter_min_amount: nil,
        filter_max_amount: nil,
        filter_from_date: nil,
        filter_to_date: nil,
        only_evaluated: false,
        selected_application_id: nil,
        selected_app: nil,
        show_raw_json: false,
        error_message: nil,
        success_message: nil,
        webhook_events: %{},
        page: page_data.page,
        per_page: page_data.per_page,
        total_pages: page_data.total_pages,
        total_entries: page_data.total
      )

    socket =
      if connected?(socket) do
        Endpoint.subscribe(@topic)
        socket
      else
        socket
      end

    {:ok, socket}
  end

  # ─────────────────────────────────────────────
  # handle_event
  # ─────────────────────────────────────────────

  @impl true
  def handle_event("create_application", params, socket) do
    attrs = build_attrs_from_params(params)

    case CreditApplications.create_application(attrs, source: "backoffice") do
      {:ok, app} ->
        # recargamos con filtros actuales pero enviando a página 1
        filters = current_filters(socket.assigns)

        page_data =
          CreditApplications.list_applications(filters,
            page: 1,
            per_page: socket.assigns.per_page || @default_per_page
          )

        socket =
          socket
          |> put_flash(:info, "Solicitud creada (#{app.country}). Evaluando riesgo…")
          |> assign(:applications, page_data.entries)
          |> assign(:stats, build_stats(page_data.entries))
          |> assign(:form, empty_form())
          |> assign(:error_message, nil)
          |> assign(:success_message, "Solicitud creada correctamente.")
          |> assign(:page, page_data.page)
          |> assign(:per_page, page_data.per_page)
          |> assign(:total_pages, page_data.total_pages)
          |> assign(:total_entries, page_data.total)
          |> schedule_clear_messages()

        {:noreply, socket}

      {:error, {:policy_error, reason}} ->
        socket =
          socket
          |> put_flash(:error, "Business rule failed: #{inspect(reason)}")
          |> assign(:error_message, "Regla de negocio falló: #{inspect(reason)}")
          |> schedule_clear_messages()

        {:noreply, socket}

      {:error, {:invalid_changeset, changeset}} ->
        socket =
          socket
          |> put_flash(:error, "Payload inválido para crear la solicitud.")
          |> assign(:error_message, "Errores de validación en la solicitud.")
          |> assign(:changeset, changeset)
          |> schedule_clear_messages()

        {:noreply, socket}

      {:error, :invalid_payload} ->
        socket =
          socket
          |> put_flash(:error, "Payload inválido: falta país o documento.")
          |> assign(:error_message, "Faltan datos obligatorios (país/documento).")
          |> schedule_clear_messages()

        {:noreply, socket}

      {:error, {:job_enqueue_failed, reason}} ->
        socket =
          socket
          |> put_flash(:error, "La solicitud se guardó, pero falló el job de riesgo.")
          |> assign(:error_message, "Job de riesgo no pudo encolarse: #{inspect(reason)}")
          |> schedule_clear_messages()

        {:noreply, socket}

      {:error, other} ->
        socket =
          socket
          |> put_flash(:error, "Ocurrió un error inesperado al crear la solicitud.")
          |> assign(:error_message, "Error inesperado: #{inspect(other)}")
          |> schedule_clear_messages()

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    country = blank_to_nil(params["country"])
    status = blank_to_nil(params["status"])
    min_amount = blank_to_nil(params["min_amount"])
    max_amount = blank_to_nil(params["max_amount"])
    from_date = blank_to_nil(params["from_date"])
    to_date = blank_to_nil(params["to_date"])
    only_evaluated = Map.has_key?(params, "only_evaluated")

    filters = %{
      country: country,
      status: status,
      min_amount: min_amount,
      max_amount: max_amount,
      from_date: from_date,
      to_date: to_date,
      only_evaluated: only_evaluated
    }

    page_data =
      CreditApplications.list_applications(filters,
        page: 1,
        per_page: socket.assigns.per_page || @default_per_page
      )

    socket =
      socket
      |> assign(
        applications: page_data.entries,
        stats: build_stats(page_data.entries),
        filter_country: country,
        filter_status: status,
        filter_min_amount: min_amount,
        filter_max_amount: max_amount,
        filter_from_date: from_date,
        filter_to_date: to_date,
        only_evaluated: only_evaluated,
        selected_application_id: nil,
        selected_app: nil,
        page: page_data.page,
        per_page: page_data.per_page,
        total_pages: page_data.total_pages,
        total_entries: page_data.total
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_page", %{"page" => page_str}, socket) do
    page =
      case Integer.parse(page_str) do
        {p, _} when p >= 1 -> p
        _ -> 1
      end

    per_page = socket.assigns.per_page || @default_per_page
    filters = current_filters(socket.assigns)

    page_data = CreditApplications.list_applications(filters, page: page, per_page: per_page)

    {:noreply,
     socket
     |> assign(:applications, page_data.entries)
     |> assign(:stats, build_stats(page_data.entries))
     |> assign(:page, page_data.page)
     |> assign(:per_page, page_data.per_page)
     |> assign(:total_pages, page_data.total_pages)
     |> assign(:total_entries, page_data.total)}
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value

  @impl true
  def handle_event("select_app", %{"id" => id}, socket) do
    case Queries.get_application(id) do
      nil ->
        {:noreply,
         socket
         |> assign(:selected_app, nil)
         |> assign(:show_raw_json, false)
         |> assign(:error_message, "La solicitud seleccionada ya no existe.")
         |> assign(:success_message, nil)
         |> schedule_clear_messages()}

      %Application{} = app ->
        {:noreply,
         socket
         |> assign(:selected_app, app)
         |> assign(:show_raw_json, false)
         |> assign(:error_message, nil)}
    end
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    socket =
      socket
      |> assign(:selected_app, nil)
      |> assign(:show_raw_json, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_raw_json", _params, socket) do
    {:noreply, update(socket, :show_raw_json, fn current -> not current end)}
  end

  @impl true
  def handle_event("re_evaluate_risk", %{"id" => id}, socket) do
    case EvaluateRisk.enqueue(id) do
      :ok ->
        socket =
          socket
          |> assign(:success_message, "Re-evaluación de riesgo encolada correctamente.")
          |> assign(:error_message, nil)
          |> schedule_clear_messages()

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:error_message, "No se pudo encolar la re-evaluación: #{inspect(reason)}")
          |> assign(:success_message, nil)
          |> schedule_clear_messages()

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("resend_webhook", %{"id" => id}, socket) do
    # Mejor obtener el status real de DB (la vista puede estar stale)
    status =
      case Queries.get_application(id) do
        %Application{status: s} -> s
        _ -> "UNKNOWN"
      end

    case WebhookNotifier.enqueue_manual(id, status) do
      :ok ->
        {:noreply,
         socket
         |> assign(:success_message, "Webhook reenviado (manual) y encolado para entrega.")
         |> assign(:error_message, nil)
         |> schedule_clear_messages()}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "No se pudo reenviar el webhook.")
         |> assign(:error_message, "No se pudo reenviar el webhook: #{inspect(reason)}")
         |> assign(:success_message, nil)
         |> schedule_clear_messages()}
    end
  end

  # ─────────────────────────────────────────────
  # render + componentes
  # ─────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-slate-100 py-8">
        <div class="max-w-6xl mx-auto px-4">
          <.backoffice_header current_scope={@current_scope} />
          <.applications_panel {assigns} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Header
  defp backoffice_header(assigns) do
    ~H"""
    <div class="mb-6">
      <h1 class="text-3xl font-bold text-slate-800 mb-1">
        Solicitudes de Crédito Multipaís
      </h1>

      <%= if @current_scope do %>
        <p class="text-sm text-slate-500">
          Sesión iniciada como
          <span class="font-semibold">
            {@current_scope.user.email}
          </span>
          · rol:
          <span class="font-mono">
            {@current_scope.role}
          </span>
        </p>

        <%= if backoffice?(@current_scope) do %>
          <div class="mt-2 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800">
            <strong>Demo backoffice:</strong>
            este panel está pensado para usuarios con rol <code>backoffice</code>.
          </div>
        <% else %>
          <div class="mt-2 rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 text-xs text-slate-700">
            <strong>Vista limitada:</strong> algunas columnas y detalles están ocultos para tu rol.
          </div>
        <% end %>
      <% else %>
        <p class="text-sm text-slate-500">
          No hay scope de usuario cargado. Esta vista debería usarse detrás de login.
        </p>
      <% end %>
    </div>
    """
  end

  # Panel principal (form + tabla + detalle)
  defp applications_panel(assigns) do
    assigns =
      assigns
      |> assign_new(:applications, fn -> [] end)
      |> assign_new(:countries, fn -> ["ES", "IT", "PT"] end)
      |> assign_new(:statuses, fn ->
        ["CREATED", "PENDING_RISK", "UNDER_REVIEW", "APPROVED", "REJECTED"]
      end)
      |> assign_new(:form, fn ->
        %{
          "country" => "ES",
          "full_name" => "",
          "document_value" => "",
          "amount" => "",
          "monthly_income" => ""
        }
      end)
      |> assign_new(:current_scope, fn -> nil end)
      |> assign_new(:filter_country, fn -> nil end)
      |> assign_new(:filter_status, fn -> nil end)
      |> assign_new(:filter_min_amount, fn -> nil end)
      |> assign_new(:filter_max_amount, fn -> nil end)
      |> assign_new(:filter_from_date, fn -> nil end)
      |> assign_new(:filter_to_date, fn -> nil end)
      |> assign_new(:only_evaluated, fn -> false end)
      |> assign_new(:selected_app, fn -> nil end)
      |> assign_new(:show_raw_json, fn -> false end)
      |> assign_new(:error_message, fn -> nil end)
      |> assign_new(:success_message, fn -> nil end)
      |> assign_new(:webhook_events, fn -> %{} end)

    assigns = assign(assigns, :stats, build_stats(assigns.applications || []))

    ~H"""
    <div class="mb-6 grid gap-4 sm:grid-cols-3">
      <.stat_card label="Total solicitudes" value={@stats.total} />
      <.stat_card label="Pendientes de riesgo" value={@stats.pending_risk} />
      <.stat_card label="Aprobadas" value={@stats.approved} />
      <.stat_card label="Rechazadas" value={@stats.rejected} />
    </div>

    <!-- Layout principal:
         - Mobile: 1 columna (stack)
         - Desktop: 2 columnas, derecha bastante más ancha -->
    <div class="grid grid-cols-1 lg:grid-cols-[minmax(0,0.9fr)_minmax(0,2.3fr)] gap-8 items-start">
      <!-- Panel de creación -->
      <div>
        <div class="bg-white shadow rounded-2xl p-6 space-y-4">
          <h2 class="text-xl font-semibold text-slate-800 mb-2">
            Nueva solicitud
          </h2>

          <p class="text-sm text-slate-500 mb-4">
            Elige país, captura datos básicos del cliente y el sistema evaluará el riesgo en segundo plano.
          </p>

          <%= if @error_message do %>
            <div class="mb-3 text-sm text-red-700 bg-red-50 border border-red-200 rounded-lg px-3 py-2">
              <strong>Error:</strong> {@error_message}
            </div>
          <% end %>

          <%= if @success_message do %>
            <div class="mb-3 text-sm text-emerald-700 bg-emerald-50 border border-emerald-200 rounded-lg px-3 py-2">
              {@success_message}
            </div>
          <% end %>

          <form phx-submit="create_application" class="space-y-4">
            <!-- País -->
            <div>
              <label class="block text-sm font-medium text-slate-700 mb-1">
                País
              </label>
              <select
                name="country"
                class="block w-full rounded-xl border-slate-300 shadow-sm text-sm focus:border-indigo-500 focus:ring-indigo-500"
              >
                <%= for c <- @countries do %>
                  <option value={c} selected={@form["country"] == c}>{c}</option>
                <% end %>
              </select>
            </div>
            
    <!-- Nombre completo -->
            <div>
              <label class="block text-sm font-medium text-slate-700 mb-1">
                Nombre completo
              </label>
              <input
                type="text"
                name="full_name"
                value={@form["full_name"]}
                placeholder="Ej. Juan Pérez"
                class="block w-full rounded-xl border-slate-300 shadow-sm text-sm focus:border-indigo-500 focus:ring-indigo-500"
                required
              />
            </div>
            
    <!-- Documento -->
            <div>
              <label class="block text-sm font-medium text-slate-700 mb-1">
                Documento (DNI / Codice Fiscale / NIF)
              </label>
              <input
                type="text"
                name="document_value"
                value={@form["document_value"]}
                placeholder="Dependiendo del país: DNI, CF, NIF..."
                class="block w-full rounded-xl border-slate-300 shadow-sm text-sm focus:border-indigo-500 focus:ring-indigo-500"
                required
              />
            </div>
            
    <!-- Monto e ingreso -->
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-slate-700 mb-1">
                  Monto solicitado
                </label>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  name="amount"
                  value={@form["amount"]}
                  placeholder="Ej. 5000"
                  class="block w-full rounded-xl border-slate-300 shadow-sm text-sm focus:border-indigo-500 focus:ring-indigo-500"
                  required
                />
              </div>

              <div>
                <label class="block text-sm font-medium text-slate-700 mb-1">
                  Ingreso mensual
                </label>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  name="monthly_income"
                  value={@form["monthly_income"]}
                  placeholder="Ej. 2000"
                  class="block w-full rounded-xl border-slate-300 shadow-sm text-sm focus:border-indigo-500 focus:ring-indigo-500"
                  required
                />
              </div>
            </div>

            <div class="pt-2">
              <button
                type="submit"
                class="inline-flex items-center justify-center px-4 py-2 rounded-xl text-sm font-semibold text-white bg-indigo-600 hover:bg-indigo-700 shadow-sm focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 w-full"
              >
                Crear solicitud
              </button>
            </div>
          </form>
        </div>
      </div>
      
    <!-- Panel de lista + detalle -->
      <div>
        <div class="bg-white shadow rounded-2xl p-6 space-y-6">
          <!-- Cabecera + filtros -->
          <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div class="max-w-sm">
              <h2 class="text-xl font-semibold text-slate-800">
                Solicitudes recientes
              </h2>
              <p class="text-sm text-slate-500">
                Se actualizan automáticamente cuando el motor de riesgo termina la evaluación.
              </p>
            </div>
            
    <!-- Filtros -->
            <form phx-change="filter" class="flex flex-wrap gap-3 items-end">
              <!-- País -->
              <div>
                <label class="block text-xs font-medium text-slate-600 mb-1">
                  País
                </label>
                <select
                  name="country"
                  class="block w-32 rounded-xl border-slate-300 shadow-sm text-xs focus:border-indigo-500 focus:ring-indigo-500"
                >
                  <option value="">Todos</option>
                  <%= for c <- @countries do %>
                    <option value={c} selected={@filter_country == c}>{c}</option>
                  <% end %>
                </select>
              </div>
              
    <!-- Estado -->
              <div>
                <label class="block text-xs font-medium text-slate-600 mb-1">
                  Estado
                </label>
                <select
                  name="status"
                  class="block w-40 rounded-xl border-slate-300 shadow-sm text-xs focus:border-indigo-500 focus:ring-indigo-500"
                >
                  <option value="">Todos</option>
                  <%= for s <- @statuses do %>
                    <option value={s} selected={@filter_status == s}>{s}</option>
                  <% end %>
                </select>
              </div>
              
    <!-- Sólo evaluadas -->
              <div class="flex items-center mt-2 sm:mt-0">
                <input
                  type="checkbox"
                  name="only_evaluated"
                  value="true"
                  checked={@only_evaluated}
                  class="h-4 w-4 rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
                />
                <span class="ml-2 text-xs text-slate-600">
                  Sólo con riesgo evaluado
                </span>
              </div>
              
    <!-- Rango de monto -->
              <div>
                <label class="block text-xs font-medium text-slate-600 mb-1">
                  Monto (mín)
                </label>
                <input
                  type="number"
                  name="min_amount"
                  step="0.01"
                  min="0"
                  value={@filter_min_amount || ""}
                  class="block w-28 rounded-xl border-slate-300 shadow-sm text-xs focus:border-indigo-500 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-slate-600 mb-1">
                  Monto (máx)
                </label>
                <input
                  type="number"
                  name="max_amount"
                  step="0.01"
                  min="0"
                  value={@filter_max_amount || ""}
                  class="block w-28 rounded-xl border-slate-300 shadow-sm text-xs focus:border-indigo-500 focus:ring-indigo-500"
                />
              </div>
              
    <!-- Rango de fechas -->
              <div>
                <label class="block text-xs font-medium text-slate-600 mb-1">
                  Desde
                </label>
                <input
                  type="date"
                  name="from_date"
                  value={@filter_from_date || ""}
                  class="block w-36 rounded-xl border-slate-300 shadow-sm text-xs focus:border-indigo-500 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-slate-600 mb-1">
                  Hasta
                </label>
                <input
                  type="date"
                  name="to_date"
                  value={@filter_to_date || ""}
                  class="block w-36 rounded-xl border-slate-300 shadow-sm text-xs focus:border-indigo-500 focus:ring-indigo-500"
                />
              </div>
            </form>
          </div>
          
    <!-- Tabla -->
          <div class="overflow-x-auto">
            <table class="min-w-full text-sm">
              <thead>
                <tr class="border-b border-slate-200 bg-slate-50">
                  <th class="text-left py-2 px-3 font-medium text-slate-600">País</th>
                  <th class="text-left py-2 px-3 font-medium text-slate-600">Nombre</th>
                  <th class="text-right py-2 px-3 font-medium text-slate-600">Monto</th>
                  <th class="text-right py-2 px-3 font-medium text-slate-600">Ingreso</th>
                  <th class="text-center py-2 px-3 font-medium text-slate-600">Estado</th>

                  <%= if backoffice?(@current_scope) do %>
                    <th class="text-center py-2 px-3 font-medium text-slate-600">Score</th>
                  <% end %>

                  <th class="text-right py-2 px-3 font-medium text-slate-600">Creada</th>
                </tr>
              </thead>
              <tbody>
                <%= if @applications == [] do %>
                  <tr>
                    <td colspan="7" class="text-center text-slate-400 py-6">
                      Aún no hay solicitudes. Crea la primera desde el panel izquierdo.
                    </td>
                  </tr>
                <% else %>
                  <%= for app <- @applications do %>
                    <tr
                      phx-click="select_app"
                      phx-value-id={app.id}
                      class={[
                        "border-b border-slate-100 hover:bg-slate-50 transition-colors cursor-pointer",
                        @selected_app && @selected_app.id == app.id && "bg-indigo-50/60"
                      ]}
                    >
                      <!-- País -->
                      <td class="py-2 px-3">
                        {country_badge(app.country)}
                      </td>
                      
    <!-- Nombre -->
                      <td class="py-2 px-3 text-slate-800">
                        {app.full_name}
                      </td>
                      
    <!-- Monto -->
                      <td class="py-2 px-3 text-right tabular-nums text-slate-700">
                        € {app.amount}
                      </td>
                      
    <!-- Ingreso mensual -->
                      <td class="py-2 px-3 text-right tabular-nums text-slate-700">
                        € {app.monthly_income}
                      </td>
                      
    <!-- Estado -->
                      <td class="py-2 px-3 text-center">
                        {status_badge(app.status)}
                      </td>
                      
    <!-- Score: sólo backoffice ve el chip -->
                      <%= if backoffice?(@current_scope) do %>
                        <td class="py-2 px-3 text-center">
                          {risk_score_chip(app.risk_score)}
                        </td>
                      <% end %>
                      
    <!-- Fecha creación -->
                      <td class="py-2 px-3 text-right text-xs text-slate-500">
                        {Calendar.strftime(app.inserted_at, "%Y-%m-%d %H:%M")}
                      </td>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>
          
    <!-- Panel de detalle -->
          <div class="mt-4">
            <%= if @selected_app do %>
              <div class="border border-slate-200 rounded-2xl p-6 bg-slate-50/80 shadow-sm">
                <div class="flex flex-wrap items-start justify-between gap-4">
                  <div class="space-y-2">
                    <!-- Badge de estado + resumen de riesgo -->
                    <div class="flex flex-wrap items-center gap-2">
                      {status_badge(@selected_app.status)}

                      <span
                        :if={@selected_app.risk_score}
                        class="text-[11px] text-slate-600"
                      >
                        {risk_summary(@selected_app)}
                      </span>
                    </div>

                    <div class="space-y-1">
                      <h3 class="text-base font-semibold text-slate-900 leading-snug">
                        Detalle de solicitud
                      </h3>
                      <p class="text-[11px] text-slate-500 leading-relaxed">
                        ID:
                        <span class="font-mono break-all">
                          {@selected_app.id}
                        </span>
                      </p>
                    </div>
                  </div>

                  <div class="flex flex-wrap items-center gap-2">
                    <button
                      type="button"
                      phx-click="toggle_raw_json"
                      class="text-xs px-3 py-1.5 rounded-full border border-slate-300 text-slate-600 hover:bg-slate-100 bg-white"
                    >
                      {if @show_raw_json, do: "Ocultar JSON", else: "Ver JSON completo"}
                    </button>

                    <button
                      type="button"
                      phx-click="clear_selection"
                      class="text-xs text-slate-400 hover:text-slate-600"
                    >
                      Cerrar
                    </button>
                  </div>
                </div>

                <%= if @show_raw_json do %>
                  <div class="mt-4">
                    <pre class="text-xs bg-slate-900 text-slate-100 rounded-xl p-3 overflow-x-auto max-h-80">
    {Jason.encode!(@selected_app, pretty: true)}
                    </pre>
                  </div>
                <% else %>
                  <div class="mt-6 grid grid-cols-1 md:grid-cols-2 gap-6 text-sm leading-relaxed">
                    <!-- Columna 1 -->
                    <div class="space-y-2">
                      <p>
                        <span class="font-medium text-slate-600">País:</span>
                        <span class="ml-1 font-mono text-xs">{@selected_app.country}</span>
                      </p>
                      <p>
                        <span class="font-medium text-slate-600">Nombre:</span>
                        <span class="ml-1 text-slate-800">{@selected_app.full_name}</span>
                      </p>
                      <p>
                        <span class="font-medium text-slate-600">Documento:</span>
                        <span class="ml-1 text-slate-800 break-all">
                          {render_document(@selected_app.country, @selected_app.document)}
                        </span>
                      </p>
                    </div>
                    
    <!-- Columna 2 -->
                    <div class="space-y-2">
                      <p>
                        <span class="font-medium text-slate-600">Monto:</span>
                        <span class="ml-1">€ {@selected_app.amount}</span>
                      </p>
                      <p>
                        <span class="font-medium text-slate-600">Ingreso mensual:</span>
                        <span class="ml-1">€ {@selected_app.monthly_income}</span>
                      </p>
                      <p class="flex items-center flex-wrap gap-2">
                        <span class="font-medium text-slate-600">Estado:</span>
                        {status_badge(@selected_app.status)}
                      </p>
                      <p class="flex items-center flex-wrap gap-2">
                        <span class="font-medium text-slate-600">Score de riesgo:</span>
                        <%= if @selected_app.risk_score do %>
                          <span class="font-mono text-xs">{@selected_app.risk_score}</span>
                        <% else %>
                          <span class="text-xs text-slate-400 italic">pendiente</span>
                        <% end %>
                        <button
                          type="button"
                          phx-click="re_evaluate_risk"
                          phx-value-id={@selected_app.id}
                          class="inline-flex items-center px-3 py-1.5 rounded-full text-[11px] font-medium border border-indigo-200 text-indigo-700 bg-indigo-50 hover:bg-indigo-100"
                        >
                          Re-evaluar riesgo
                        </button>
                      </p>
                    </div>
                    
    <!-- Columna 3: info bancaria + timeline + acciones
                         (se apila debajo en 2 columnas gracias al grid md:grid-cols-2) -->
                    <div class="md:col-span-2 lg:col-span-1 space-y-4">
                      <%= if backoffice?(@current_scope) do %>
                        <%= if @selected_app.bank_profile do %>
                          <% profile = @selected_app.bank_profile %>
                          <% total_debt = map_get(profile, [:total_debt]) %>
                          <% avg_balance = map_get(profile, [:avg_balance]) %>
                          <% external_id = map_get(profile, [:external_id]) %>
                          <% currency = map_get(profile, [:currency]) || "EUR" %>

                          <div class="space-y-1">
                            <h4 class="text-xs font-semibold text-slate-500 uppercase tracking-wide">
                              Información bancaria
                            </h4>
                            <p>
                              <span class="font-medium text-slate-600">Identificador externo:</span>
                              <span class="ml-1 text-xs font-mono break-all">
                                {external_id}
                              </span>
                            </p>
                            <p>
                              <span class="font-medium text-slate-600">Deuda total:</span>
                              <span class="ml-1">
                                {currency} {total_debt || "N/D"}
                              </span>
                            </p>
                            <p>
                              <span class="font-medium text-slate-600">Saldo promedio:</span>
                              <span class="ml-1">
                                {currency} {avg_balance || "N/D"}
                              </span>
                            </p>
                          </div>

                          <div class="pt-3 border-t border-slate-200">
                            <h4 class="text-[11px] font-semibold text-slate-500 uppercase tracking-wide mb-2">
                              Timeline (simulada)
                            </h4>

                            <ol class="relative border-l border-slate-200 pl-6 space-y-3 text-xs">
                              <%= for event <- build_timeline(@selected_app, @webhook_events) do %>
                                <li class="relative">
                                  <span class={[
                                    "absolute -left-2 top-1 h-3 w-3 rounded-full border border-white shadow",
                                    case event.type do
                                      :created ->
                                        "bg-slate-400"

                                      :risk_evaluated ->
                                        "bg-indigo-500"

                                      :final_status ->
                                        if @selected_app.status == "APPROVED",
                                          do: "bg-emerald-500",
                                          else: "bg-rose-500"

                                      :webhook ->
                                        "bg-sky-500"
                                    end
                                  ]} />

                                  <p class="ml-1 text-[11px] text-slate-500">
                                    {Calendar.strftime(event.at, "%Y-%m-%d %H:%M")}
                                  </p>
                                  <p class="ml-1 text-[12px] text-slate-800">
                                    {event.label}
                                  </p>
                                </li>
                              <% end %>
                            </ol>
                          </div>
                        <% else %>
                          <p class="text-xs text-slate-400 italic">
                            Sin información bancaria disponible.
                          </p>
                        <% end %>
                        
    <!-- Acciones de integración -->
                        <div class="flex flex-wrap gap-2 pt-2">
                          <% disabled = is_nil(@selected_app.risk_score) %>

                          <button
                            type="button"
                            phx-click="resend_webhook"
                            phx-value-id={@selected_app.id}
                            disabled={disabled}
                            class={[
                              "inline-flex items-center px-3 py-1.5 rounded-full text-[11px] font-medium border shadow-sm",
                              disabled &&
                                "opacity-60 cursor-not-allowed border-slate-200 text-slate-400 bg-slate-50",
                              !disabled &&
                                "border-amber-200 text-amber-800 bg-amber-50 hover:bg-amber-100"
                            ]}
                          >
                            Re-enviar webhook
                          </button>

                          <%= if disabled do %>
                            <p class="text-[11px] text-slate-400">
                              Disponible cuando el riesgo esté evaluado.
                            </p>
                          <% end %>
                        </div>
                      <% else %>
                        <p class="text-xs text-slate-400 italic">
                          Información bancaria disponible sólo para usuarios backoffice.
                        </p>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ─────────────────────────────────────────────
  # Helpers de datos/roles
  # ─────────────────────────────────────────────

  defp current_filters(assigns) do
    %{
      country: assigns[:filter_country],
      status: assigns[:filter_status],
      min_amount: assigns[:filter_min_amount],
      max_amount: assigns[:filter_max_amount],
      from_date: assigns[:filter_from_date],
      to_date: assigns[:filter_to_date],
      only_evaluated: assigns[:only_evaluated] || false
    }
  end

  # Evento de webhook reenviado (viene del WebhookNotifier)
  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: @topic,
          event: "webhook_resent",
          payload: %{application_id: application_id, at: at}
        },
        socket
      ) do
    at_naive =
      case at do
        %NaiveDateTime{} = n -> n
        %DateTime{} = dt -> DateTime.to_naive(dt)
        _ -> NaiveDateTime.utc_now()
      end

    webhook_events =
      (socket.assigns[:webhook_events] || %{})
      |> Map.put(application_id, at_naive)

    app =
      Enum.find(socket.assigns.applications || [], fn a -> a.id == application_id end) ||
        Queries.get_application(application_id)

    toast_msg =
      case app do
        %Application{country: country, status: status} ->
          "Webhook reenviado (#{country}) para solicitud #{status}."

        _ ->
          "Webhook reenviado correctamente."
      end

    {:noreply,
     socket
     |> assign(:webhook_events, webhook_events)
     |> assign(:success_message, toast_msg)
     |> assign(:error_message, nil)
     |> schedule_clear_messages()}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: @topic,
          event: "status_changed",
          payload: %{id: id}
        },
        socket
      ) do
    filters = current_filters(socket.assigns)

    page_data =
      CreditApplications.list_applications(filters,
        page: socket.assigns.page || 1,
        per_page: socket.assigns.per_page || @default_per_page
      )

    apps = page_data.entries

    updated_app =
      Enum.find(apps, fn a -> a.id == id end) ||
        Queries.get_application(id)

    selected_app =
      case socket.assigns.selected_app do
        %Application{id: ^id} -> updated_app
        other -> other
      end

    toast_msg =
      case updated_app do
        %Application{status: status, risk_score: score, country: country} ->
          score_text = if is_integer(score), do: Integer.to_string(score), else: "N/D"
          "Riesgo evaluado (#{country}): #{status} (score #{score_text})"

        _ ->
          "Riesgo evaluado."
      end

    {:noreply,
     socket
     |> assign(:applications, apps)
     |> assign(:stats, build_stats(apps))
     |> assign(:selected_app, selected_app)
     |> assign(:success_message, toast_msg)
     |> assign(:error_message, nil)
     |> schedule_clear_messages()
     |> assign(:page, page_data.page)
     |> assign(:per_page, page_data.per_page)
     |> assign(:total_pages, page_data.total_pages)
     |> assign(:total_entries, page_data.total)}
  end

  @impl true
  def handle_info(:clear_messages, socket) do
    {:noreply,
     socket
     |> assign(:success_message, nil)
     |> assign(:error_message, nil)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp empty_form do
    %{
      "country" => "ES",
      "full_name" => "",
      "document_value" => "",
      "amount" => "",
      "monthly_income" => ""
    }
  end

  defp build_attrs_from_params(%{
         "country" => country,
         "full_name" => full_name,
         "document_value" => doc_value,
         "amount" => amount,
         "monthly_income" => income
       }) do
    %{
      "country" => country,
      "full_name" => full_name,
      "document" => build_document_map(country, doc_value),
      "amount" => amount,
      "monthly_income" => income
    }
  end

  defp build_attrs_from_params(other), do: other

  defp build_document_map("ES", value), do: %{"dni" => value}
  defp build_document_map("IT", value), do: %{"codice_fiscale" => value}
  defp build_document_map("PT", value), do: %{"nif" => value}
  defp build_document_map(country, value), do: %{"raw" => value, "country" => country}

  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # ─────────────────────────────────────────────
  # UI helpers
  # ─────────────────────────────────────────────

  defp country_badge(country) do
    {flag, label} =
      case country do
        "ES" -> {"🇪🇸", "ES"}
        "IT" -> {"🇮🇹", "IT"}
        "PT" -> {"🇵🇹", "PT"}
        other -> {"🌍", to_string(other || "N/A")}
      end

    assigns = %{flag: flag, label: label}

    ~H"""
    <span class="inline-flex items-center gap-1 rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-700">
      <span>{@flag}</span>
      <span>{@label}</span>
    </span>
    """
  end

  defp status_badge(status) do
    {label, classes} =
      case status do
        "APPROVED" ->
          {"Aprobada", "bg-emerald-50 text-emerald-700 border-emerald-200"}

        "UNDER_REVIEW" ->
          {"En revisión", "bg-amber-50 text-amber-700 border-amber-200"}

        "REJECTED" ->
          {"Rechazada", "bg-rose-50 text-rose-700 border-rose-200"}

        "PENDING_RISK" ->
          {"En evaluación de riesgo", "bg-slate-100 text-slate-600 border-slate-200"}

        other ->
          {other || "Desconocido", "bg-slate-100 text-slate-600 border-slate-200"}
      end

    assigns = %{label: label, classes: classes, status: status}

    ~H"""
    <span class={
      "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-medium " <> @classes
    }>
      <span
        :if={@status in ["PENDING_RISK", "UNDER_REVIEW"]}
        class="h-1.5 w-1.5 rounded-full bg-amber-400 animate-pulse"
      />
      {@label}
    </span>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-2xl border border-slate-200 bg-white/70 p-4 shadow-sm">
      <p class="text-[11px] font-medium uppercase tracking-wide text-slate-500">
        {@label}
      </p>

      <p class="mt-1 text-2xl font-semibold text-slate-900">
        {@value}
      </p>
    </div>
    """
  end

  defp risk_score_chip(nil) do
    assigns = %{}

    ~H"""
    <span class="text-xs text-slate-400 italic">
      Pendiente
    </span>
    """
  end

  defp risk_score_chip(score) do
    {classes, label} =
      cond do
        is_nil(score) ->
          {"bg-slate-100 text-slate-500 border-slate-200", "Pendiente"}

        score >= 730 ->
          {"bg-emerald-50 text-emerald-700 border-emerald-200", "Alto"}

        score >= 650 ->
          {"bg-amber-50 text-amber-700 border-amber-200", "Medio"}

        true ->
          {"bg-rose-50 text-rose-700 border-rose-200", "Bajo"}
      end

    assigns = %{score: score, classes: classes, label: label}

    ~H"""
    <span class={
      "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-medium " <> @classes
    }>
      <span :if={@score} class="font-mono">{@score}</span>
      <span :if={@score} class="text-[10px] uppercase tracking-wide">{@label}</span>
    </span>
    """
  end

  # Nivel de riesgo a partir del score numérico
  defp risk_level(score) when is_integer(score) do
    cond do
      score >= 740 -> {:low, "Riesgo bajo"}
      score >= 660 -> {:medium, "Riesgo medio"}
      true -> {:high, "Riesgo alto"}
    end
  end

  defp risk_level(nil), do: {:unknown, "Pendiente"}

  defp risk_level_badge(nil) do
    assigns = %{}

    ~H"""
    <span class="inline-flex items-center rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-medium text-slate-500">
      Pendiente
    </span>
    """
  end

  defp risk_level_badge(score) when is_integer(score) do
    {level, label} = risk_level(score)

    {bg, text} =
      case level do
        :low -> {"bg-emerald-50", "text-emerald-700"}
        :medium -> {"bg-amber-50", "text-amber-700"}
        :high -> {"bg-rose-50", "text-rose-700"}
        _ -> {"bg-slate-100", "text-slate-500"}
      end

    assigns = %{label: label, bg: bg, text: text}

    ~H"""
    <span class={"inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-medium #{@bg} #{@text}"}>
      {@label}
    </span>
    """
  end

  defp build_timeline(app, webhook_events) do
    base = [
      %{
        label: "Solicitud creada",
        at: app.inserted_at,
        type: :created
      }
    ]

    base =
      if app.risk_score do
        base ++
          [
            %{
              label: "Riesgo evaluado (score #{app.risk_score})",
              at: app.updated_at,
              type: :risk_evaluated
            }
          ]
      else
        base
      end

    base =
      if app.status in ["APPROVED", "REJECTED"] do
        base ++
          [
            %{
              label: "Solicitud #{String.downcase(app.status)}",
              at: app.updated_at,
              type: :final_status
            }
          ]
      else
        base
      end

    base =
      case Map.get(webhook_events, app.id) do
        nil ->
          base

        at ->
          base ++
            [
              %{
                label: "Webhook reenviado",
                at: at,
                type: :webhook
              }
            ]
      end

    Enum.sort_by(base, & &1.at)
  end

  defp render_document("ES", doc) when is_map(doc) do
    doc["dni"] || doc[:dni] || doc["nif"] || doc[:nif] || doc["nie"] || doc[:nie] || "N/D"
  end

  defp render_document("IT", doc) when is_map(doc) do
    doc["codice_fiscale"] || doc[:codice_fiscale] || "N/D"
  end

  defp render_document("PT", doc) when is_map(doc) do
    doc["nif"] || doc[:nif] || "N/D"
  end

  defp render_document(_country, doc) when is_map(doc) do
    inspect(doc)
  end

  defp render_document(_country, _), do: "N/D"

  defp map_get(map, [key]) do
    Map.get(map, key) ||
      Map.get(map, to_string(key)) ||
      Map.get(map, String.to_atom("#{key}"))
  rescue
    ArgumentError -> Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp backoffice?(%{role: "backoffice"}), do: true
  defp backoffice?(_), do: false

  defp build_stats(applications) do
    %{
      total: Enum.count(applications),
      pending_risk: Enum.count(applications, &(&1.status == "PENDING_RISK")),
      approved: Enum.count(applications, &(&1.status == "APPROVED")),
      rejected: Enum.count(applications, &(&1.status == "REJECTED"))
    }
  end

  defp schedule_clear_messages(socket) do
    Process.send_after(self(), :clear_messages, 3_000)
    socket
  end

  defp risk_summary(%{country: country, status: status, risk_score: score})
       when is_integer(score) and is_binary(country) and is_binary(status) do
    country = String.upcase(country)

    base_copy =
      @risk_copy
      |> Map.get(country, @risk_copy["DEFAULT"])
      |> Map.get(status, "riesgo calculado")

    "#{status} (score #{score} – #{base_copy})"
  end

  defp risk_summary(_), do: "Sin evaluación de riesgo aún"
end
