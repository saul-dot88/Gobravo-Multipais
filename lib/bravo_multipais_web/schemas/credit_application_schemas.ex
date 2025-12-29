defmodule BravoMultipaisWeb.Schemas.CreditApplicationCreateRequest do
  require OpenApiSpex
  alias OpenApiSpex.Schema

  @behaviour OpenApiSpex.Schema

  @impl true
  def schema do
    %Schema{
      title: "CreditApplicationCreateRequest",
      type: :object,
      required: [:country, :full_name, :document, :amount, :monthly_income],
      properties: %{
        country: %Schema{
          type: :string,
          enum: ["ES", "IT", "PT"],
          description: "País donde se origina la solicitud"
        },
        full_name: %Schema{
          type: :string,
          description: "Nombre completo del solicitante"
        },
        document: %Schema{
          type: :object,
          description: "Documento de identidad, según país",
          oneOf: [
            %Schema{
              title: "ES DNI/NIF",
              type: :object,
              required: [:dni],
              properties: %{dni: %Schema{type: :string}}
            },
            %Schema{
              title: "IT Codice Fiscale",
              type: :object,
              required: [:codice_fiscale],
              properties: %{codice_fiscale: %Schema{type: :string}}
            },
            %Schema{
              title: "PT NIF",
              type: :object,
              required: [:nif],
              properties: %{nif: %Schema{type: :string}}
            }
          ]
        },
        amount: %Schema{
          type: :number,
          format: :float,
          description: "Monto solicitado"
        },
        monthly_income: %Schema{
          type: :number,
          format: :float,
          description: "Ingreso mensual del solicitante"
        },
        external_reference: %Schema{
          type: :string,
          nullable: true,
          description: "Identificador externo opcional del sistema cliente"
        }
      },
      example: %{
        "country" => "ES",
        "full_name" => "Juan Pérez",
        "document" => %{"dni" => "12345678Z"},
        "amount" => 5_000.0,
        "monthly_income" => 2_000.0,
        "external_reference" => "CLIENT-SYS-123"
      }
    }
  end
end

defmodule BravoMultipaisWeb.Schemas.CreditApplicationResponse do
  require OpenApiSpex
  alias OpenApiSpex.Schema

  @behaviour OpenApiSpex.Schema

  @impl true
  def schema do
    %Schema{
      title: "CreditApplicationResponse",
      type: :object,
      required: [:id, :country, :full_name, :status, :amount, :monthly_income, :inserted_at],
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        country: %Schema{type: :string},
        full_name: %Schema{type: :string},
        document: %Schema{
          type: :object,
          nullable: true,
          description: "Documento público (p.ej. dni / cod_fiscale / nif)",
          additionalProperties: true
        },
        status: %Schema{
          type: :string,
          enum: ["CREATED", "PENDING_RISK", "UNDER_REVIEW", "APPROVED", "REJECTED"]
        },
        risk_score: %Schema{
          type: :integer,
          nullable: true,
          description: "Score de riesgo cuando ya fue evaluado"
        },
        amount: %Schema{type: :number, format: :float},
        monthly_income: %Schema{type: :number, format: :float},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"},
        external_reference: %Schema{type: :string, nullable: true},
        bank_profile: %Schema{
          type: :object,
          nullable: true,
          description: "Perfil bancario público (datos sintetizados)",
          properties: %{
            external_id: %Schema{type: :string, nullable: true},
            total_debt: %Schema{type: :number, format: :float, nullable: true},
            avg_balance: %Schema{type: :number, format: :float, nullable: true},
            currency: %Schema{type: :string, nullable: true}
          }
        }
      }
    }
  end
end

defmodule BravoMultipaisWeb.Schemas.Error do
  require OpenApiSpex
  alias OpenApiSpex.Schema

  @behaviour OpenApiSpex.Schema

  @impl true
  def schema do
    %Schema{
      title: "Error",
      type: :object,
      required: [:error],
      properties: %{
        error: %Schema{type: :string},
        message: %Schema{type: :string, nullable: true}
      },
      example: %{"error" => "not_found", "message" => "Application not found"}
    }
  end
end
