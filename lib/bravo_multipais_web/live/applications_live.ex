defmodule BravoMultipaisWeb.ApplicationsLive do
  use BravoMultipaisWeb, :live_view

  alias BravoMultipais.CreditApplications.Queries
  alias BravoMultipais.CreditApplications.Commands
  alias BravoMultipaisWeb.Endpoint

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Endpoint.subscribe("applications")
    end

    # Filtros iniciales: sin filtro (nil)
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
     |> assign(:error_message, nil)
     |> assign(:success_message, nil)}
  end

  @impl true
  def handle_event("create_application", params, socket) do
    attrs = build_attrs_from_params(params)

    case Commands.create_application(attrs) do
      {:ok, _app} ->
        # Refrescamos la lista completa para simplificar
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
  def handle_info(%{event: "status_changed", payload: payload}, socket) do
    # payload = %{id: ..., country: ..., status: ..., risk_score: ...}
    apps =
      Enum.map(socket.assigns.applications, fn app ->
        if app.id == payload.id do
          %{app | status: payload.status, risk_score: payload.risk_score}
        else
          app
        end
      end)

    {:noreply, assign(socket, :applications, apps)}
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

  # params viene directo del formulario (flat)
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

  # Definimos cómo se mapea el documento según el país
  defp build_document_map("ES", value), do: %{"dni" => value}
  defp build_document_map("IT", value), do: %{"codice_fiscale" => value}
  defp build_document_map("PT", value), do: %{"nif" => value}
  defp build_document_map(country, value), do: %{"raw" => value, "country" => country}

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
                    phx-hook="CountrySelect"
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

                <!-- Documento (DNI / Codice Fiscale / NIF) -->
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

                <!-- Monto solicitado -->
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

                  <!-- Ingreso mensual -->
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
                  <!-- Filtro país -->
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

                  <!-- Filtro estado -->
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
                        <tr class="border-b border-slate-100 hover:bg-slate-50 transition-colors">
                          <td class="py-2 px-3 font-mono text-xs text-slate-700">
                            <%= app.country %>
                          </td>
                          <td class="py-2 px-3 text-slate-800">
                            <%= app.full_name %>
                          </td>
                          <td class="py-2 px-3 text-right tabular-nums text-slate-700">
                            € <%= app.amount %>
                          </td>
                          <td class="py-2 px-3 text-right tabular-nums text-slate-700">
                            € <%= app.monthly_income %>
                          </td>
                          <td class="py-2 px-3 text-center">
                            <%= status_badge(app.status) %>
                          </td>
                          <td class="py-2 px-3 text-center">
                            <%= if app.risk_score do %>
                              <span class="inline-flex items-center justify-center rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-800">
                                <%= app.risk_score %>
                              </span>
                            <% else %>
                              <span class="text-xs text-slate-400 italic">
                                pendiente
                              </span>
                            <% end %>
                          </td>
                          <td class="py-2 px-3 text-right text-xs text-slate-500">
                            <%= Calendar.strftime(app.inserted_at, "%Y-%m-%d %H:%M") %>
                          </td>
                        </tr>
                      <% end %>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
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


  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)


  # Componente pequeño para el "badge" de estado
  defp status_badge("APPROVED") do
    assigns = %{}

    ~H"""
    <span class="inline-flex items-center rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-semibold text-emerald-700 border border-emerald-200">
      Aprobada
    </span>
    """
  end

  defp status_badge("REJECTED") do
    assigns = %{}

    ~H"""
    <span class="inline-flex items-center rounded-full bg-red-50 px-2 py-0.5 text-xs font-semibold text-red-700 border border-red-200">
      Rechazada
    </span>
    """
  end

  defp status_badge("UNDER_REVIEW") do
    assigns = %{}

    ~H"""
    <span class="inline-flex items-center rounded-full bg-amber-50 px-2 py-0.5 text-xs font-semibold text-amber-700 border border-amber-200">
      En revisión
    </span>
    """
  end

  defp status_badge("PENDING_RISK") do
    assigns = %{}

    ~H"""
    <span class="inline-flex items-center rounded-full bg-slate-50 px-2 py-0.5 text-xs font-semibold text-slate-600 border border-slate-200">
      Pendiente de riesgo
    </span>
    """
  end

  defp status_badge(_other) do
    assigns = %{}

    ~H"""
    <span class="inline-flex items-center rounded-full bg-slate-50 px-2 py-0.5 text-xs font-semibold text-slate-500 border border-slate-200">
      Desconocido
    </span>
    """
  end
end
