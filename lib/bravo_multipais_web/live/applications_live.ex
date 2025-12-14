defmodule BravoMultipaisWeb.ApplicationsLive do
  use BravoMultipaisWeb, :live_view

  alias BravoMultipais.CreditApplications.{Commands, Queries}
  alias BravoMultipaisWeb.Endpoint

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Endpoint.subscribe("applications")
    end

    filter = %{}

    applications = Queries.list_applications(filter)

    {:ok,
     socket
     |> assign(:applications, applications)
     |> assign(:countries, ["ES", "IT", "PT"])
     |> assign(:statuses, ["CREATED", "PENDING_RISK", "UNDER_REVIEW", "APPROVED", "REJECTED"])
     |> assign(:filter_country, "")
     |> assign(:filter_status, "")
     |> assign(:form, empty_form())
     |> assign(:selected_app, nil)
     |> assign(:error_message, nil)
     |> assign(:success_message, nil)}
  end

  @impl true
  def handle_event("create_application", params, socket) do
    attrs = build_attrs_from_params(params)

    case Commands.create_application(attrs) do
      {:ok, _app} ->
        applications = Queries.list_applications(%{})

        {:noreply,
         socket
         |> assign(:applications, applications)
         |> assign(:form, empty_form())
         |> assign(:error_message, nil)
         |> assign(:success_message, "Solicitud creada. Evaluando riesgo...")}

      {:error, {:validation_error, type, detail}} ->
        {:noreply,
         socket
         |> assign(:error_message, "Error de validación (#{inspect(type)}): #{inspect(detail)}")
         |> assign(:success_message, nil)}

      {:error, {:integration_error, type, detail}} ->
        {:noreply,
         socket
         |> assign(:error_message, "Error integrando proveedor bancario (#{inspect(type)}): #{inspect(detail)}")
         |> assign(:success_message, nil)}

      {:error, {:changeset_error, changeset}} ->
        {:noreply,
         socket
         |> assign(:error_message, "Datos inválidos: #{inspect(changeset.errors)}")
         |> assign(:success_message, nil)}

      {:error, other} ->
        {:noreply,
         socket
         |> assign(:error_message, "Error inesperado: #{inspect(other)}")
         |> assign(:success_message, nil)}
    end
  end

  @impl true
  def handle_event("filter", %{"country" => country, "status" => status}, socket) do
    filter =
      %{}
      |> maybe_put("country", country)
      |> maybe_put("status", status)

    applications = Queries.list_applications(filter)

    {:noreply,
     socket
     |> assign(:applications, applications)
     |> assign(:filter_country, country)
     |> assign(:filter_status, status)}
  end

  @impl true
  def handle_event("select_app", %{"id" => id}, socket) do
    case Queries.get_application(id) do
      nil ->
        {:noreply,
         socket
         |> assign(:selected_app, nil)
         |> assign(:error_message, "La solicitud seleccionada ya no existe.")}

      app ->
        {:noreply,
         socket
         |> assign(:selected_app, app)
         |> assign(:error_message, nil)}
    end
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected_app, nil)}
  end

  @impl true
  def handle_info(%{event: "status_changed", payload: payload}, socket) do
    apps =
      Enum.map(socket.assigns.applications, fn app ->
        if app.id == payload.id do
          %{app | status: payload.status, risk_score: payload.risk_score}
        else
          app
        end
      end)

    selected_app =
      case socket.assigns.selected_app do
        %{} = sel when sel.id == payload.id ->
          %{sel | status: payload.status, risk_score: payload.risk_score}

        other ->
          other
      end

    {:noreply,
     socket
     |> assign(:applications, apps)
     |> assign(:selected_app, selected_app)}
  end

  # Helpers

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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-100 py-8">
      <div class="max-w-6xl mx-auto px-4">
        <h1 class="text-3xl font-bold text-slate-800 mb-6">
          Solicitudes de Crédito Multipaís
        </h1>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Panel de creación -->
          <div class="lg:col-span-1">
            <div class="bg-white shadow rounded-2xl p-6 space-y-4">
              <h2 class="text-xl font-semibold text-slate-800 mb-2">
                Nueva solicitud
              </h2>

              <p class="text-sm text-slate-500 mb-4">
                Elige país, captura datos básicos del cliente y el sistema evaluará el riesgo en segundo plano.
              </p>

              <%= if @error_message do %>
                <div class="mb-3 text-sm text-red-700 bg-red-50 border border-red-200 rounded-lg px-3 py-2">
                  <strong>Error:</strong> <%= @error_message %>
                </div>
              <% end %>

              <%= if @success_message do %>
                <div class="mb-3 text-sm text-emerald-700 bg-emerald-50 border border-emerald-200 rounded-lg px-3 py-2">
                  <%= @success_message %>
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
                      <option value={c} selected={@form["country"] == c}><%= c %></option>
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

          <!-- Panel de lista -->
          <div class="lg:col-span-2">
            <div class="bg-white shadow rounded-2xl p-6">
              <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between mb-4">
                <div>
                  <h2 class="text-xl font-semibold text-slate-800">
                    Solicitudes recientes
                  </h2>
                  <p class="text-sm text-slate-500">
                    Se actualizan automáticamente cuando el motor de riesgo termina la evaluación.
                  </p>
                </div>

                <!-- Filtros -->
                <form phx-change="filter" class="flex flex-wrap gap-3 items-end">
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
                        <option value={c} selected={@filter_country == c}><%= c %></option>
                      <% end %>
                    </select>
                  </div>

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
                        <option value={s} selected={@filter_status == s}><%= s %></option>
                      <% end %>
                    </select>
                  </div>
                </form>
              </div>

              <div class="overflow-x-auto">
                <table class="min-w-full text-sm">
                  <thead>
                    <tr class="border-b border-slate-200 bg-slate-50">
                      <th class="text-left py-2 px-3 font-medium text-slate-600">País</th>
                      <th class="text-left py-2 px-3 font-medium text-slate-600">Nombre</th>
                      <th class="text-right py-2 px-3 font-medium text-slate-600">Monto</th>
                      <th class="text-right py-2 px-3 font-medium text-slate-600">Ingreso</th>
                      <th class="text-center py-2 px-3 font-medium text-slate-600">Estado</th>
                      <th class="text-center py-2 px-3 font-medium text-slate-600">Score</th>
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
                            <%= country_badge(app.country) %>
                          </td>

                          <!-- Nombre -->
                          <td class="py-2 px-3 text-slate-800">
                            <%= app.full_name %>
                          </td>

                          <!-- Monto -->
                          <td class="py-2 px-3 text-right tabular-nums text-slate-700">
                            € <%= app.amount %>
                          </td>

                          <!-- Ingreso mensual -->
                          <td class="py-2 px-3 text-right tabular-nums text-slate-700">
                            € <%= app.monthly_income %>
                          </td>

                          <!-- Estado -->
                          <td class="py-2 px-3 text-center">
                            <%= status_badge(app.status) %>
                          </td>

                          <!-- Score -->
                          <td class="py-2 px-3 text-center">
                            <%= risk_score_chip(app.risk_score) %>
                          </td>

                          <!-- Fecha creación -->
                          <td class="py-2 px-3 text-right text-xs text-slate-500">
                            <%= Calendar.strftime(app.inserted_at, "%Y-%m-%d %H:%M") %>
                          </td>
                        </tr>
                      <% end %>
                    <% end %>
                  </tbody>
                </table>
              </div>

              <!-- Panel de detalle -->
              <div class="mt-6">
                <%= if @selected_app do %>
                  <div class="border border-slate-200 rounded-2xl p-4 bg-slate-50">
                    <div class="flex items-start justify-between gap-4">
                      <div>
                        <h3 class="text-sm font-semibold text-slate-800 mb-1">
                          Detalle de solicitud
                        </h3>
                        <p class="text-xs text-slate-500">
                          ID:
                          <span class="font-mono"><%= @selected_app.id %></span>
                        </p>
                      </div>

                      <button
                        type="button"
                        phx-click="clear_selection"
                        class="text-xs text-slate-500 hover:text-slate-700"
                      >
                        Cerrar
                      </button>
                    </div>

                    <div class="mt-4 grid grid-cols-1 sm:grid-cols-3 gap-4 text-sm">
                      <!-- Columna 1 -->
                      <div class="space-y-1">
                        <p>
                          <span class="font-medium text-slate-600">País:</span>
                          <span class="ml-1 font-mono text-xs"><%= @selected_app.country %></span>
                        </p>
                        <p>
                          <span class="font-medium text-slate-600">Nombre:</span>
                          <span class="ml-1 text-slate-800"><%= @selected_app.full_name %></span>
                        </p>
                        <p>
                          <span class="font-medium text-slate-600">Documento:</span>
                          <span class="ml-1 text-slate-800">
                            <%= render_document(@selected_app.country, @selected_app.document) %>
                          </span>
                        </p>
                      </div>

                      <!-- Columna 2 -->
                      <div class="space-y-1">
                        <p>
                          <span class="font-medium text-slate-600">Monto:</span>
                          <span class="ml-1">€ <%= @selected_app.amount %></span>
                        </p>
                        <p>
                          <span class="font-medium text-slate-600">Ingreso mensual:</span>
                          <span class="ml-1">€ <%= @selected_app.monthly_income %></span>
                        </p>
                        <p class="flex items-center gap-2">
                          <span class="font-medium text-slate-600">Estado:</span>
                          <%= status_badge(@selected_app.status) %>
                        </p>
                        <p>
                          <span class="font-medium text-slate-600">Score de riesgo:</span>
                          <%= if @selected_app.risk_score do %>
                            <span class="ml-1 font-mono text-xs"><%= @selected_app.risk_score %></span>
                          <% else %>
                            <span class="ml-1 text-xs text-slate-400 italic">pendiente</span>
                          <% end %>
                        </p>
                      </div>

                      <!-- Columna 3 -->
                      <div class="space-y-1">
                        <%= if @selected_app.bank_profile do %>
                          <% profile = @selected_app.bank_profile %>
                          <% total_debt = map_get(profile, [:total_debt]) %>
                          <% avg_balance = map_get(profile, [:avg_balance]) %>
                          <% external_id = map_get(profile, [:external_id]) %>
                          <% currency = map_get(profile, [:currency]) || "EUR" %>

                          <p>
                            <span class="font-medium text-slate-600">Identificador externo:</span>
                            <span class="ml-1 text-xs font-mono"><%= external_id %></span>
                          </p>
                          <p>
                            <span class="font-medium text-slate-600">Deuda total:</span>
                            <span class="ml-1">
                              <%= currency %> <%= total_debt || "N/D" %>
                            </span>
                          </p>
                          <p>
                            <span class="font-medium text-slate-600">Saldo promedio:</span>
                            <span class="ml-1">
                              <%= currency %> <%= avg_balance || "N/D" %>
                            </span>
                          </p>
                        <% else %>
                          <p class="text-xs text-slate-400 italic">
                            Sin información bancaria disponible.
                          </p>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Chip de país con banderita
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
    <span><%= @flag %></span>
    <span><%= @label %></span>
  </span>
  """
end

# Badge de estado con colores y “en evaluación” animado
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
    <%= @label %>
  </span>
  """
end

# Chip de score con indicador Alto / Medio / Bajo
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
    <span :if={@score} class="font-mono"><%= @score %></span>
    <span :if={@score} class="text-[10px] uppercase tracking-wide"><%= @label %></span>
  </span>
  """
end

  # Documento según país

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

  # Helper para leer de map con keys string o atom

  defp map_get(map, [key]) do
    Map.get(map, key) || Map.get(map, to_string(key)) ||
      Map.get(map, String.to_atom("#{key}"))
  rescue
    ArgumentError -> Map.get(map, key) || Map.get(map, to_string(key))
  end
end
