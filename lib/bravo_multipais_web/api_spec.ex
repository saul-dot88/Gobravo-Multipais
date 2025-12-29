defmodule BravoMultipaisWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for BravoMultipais public API.
  """

  alias OpenApiSpex.{Info, OpenApi, Paths, Server}
  alias BravoMultipaisWeb.Router

  @behaviour OpenApiSpex.ApiSpec

  @impl true
  def spec do
    %OpenApi{
      info: %Info{
        title: "Bravo Multipaís – Credit Applications API",
        version: "1.0.0",
        description: """
        API pública para crear y consultar solicitudes de crédito en múltiples países.

        Endpoints principales:

        - POST /api/applications
        - GET  /api/applications/:id
        """
      },
      servers: [
        %Server{
          url: "/",
          description: "Same host"
        }
      ],
      paths: Paths.from_router(Router),
      components: %OpenApiSpex.Components{
        schemas: %{
          "CreditApplicationCreateRequest" =>
            BravoMultipaisWeb.Schemas.CreditApplicationCreateRequest.schema(),
          "CreditApplicationResponse" =>
            BravoMultipaisWeb.Schemas.CreditApplicationResponse.schema(),
          "CreditApplicationError" => BravoMultipaisWeb.Schemas.Error.schema()
        }
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
