defmodule BravoMultipais.LogSanitizer do
  @moduledoc """
  Utilidades para sanear datos sensibles antes de loguearlos.

  Por ahora sólo enmascaramos documentos (DNI, NIF, CF, etc.).
  """

  @type document_input :: nil | String.t() | map()
  @type document_output :: nil | String.t() | map()

  @spec mask_document(document_input) :: document_output
  def mask_document(nil), do: nil

  # Caso: string plano "12345678Z"
  def mask_document(doc) when is_binary(doc) do
    mask_binary(doc)
  end

  # Caso: mapa con claves de documento (dni, nif, codice_fiscale, raw)
  def mask_document(%{} = doc) do
    key =
      Enum.find(["dni", "nif", "codice_fiscale", "raw"], fn k ->
        Map.has_key?(doc, k) or Map.has_key?(doc, String.to_atom(k))
      end)

    case key do
      nil ->
        doc

      k ->
        value =
          Map.get(doc, k) ||
            Map.get(doc, String.to_atom(k))

        masked = mask_binary(value || "")

        doc
        |> put_if_present(k, masked)
        |> put_if_present(String.to_atom(k), masked)
    end
  end

  # Cualquier otra cosa, la devolvemos tal cual
  def mask_document(other), do: other

  # ── Helpers internos ─────────────────────────

  defp mask_binary(bin) when is_binary(bin) do
    len = String.length(bin)

    if len <= 4 do
      String.duplicate("*", len)
    else
      # dejamos los últimos 4 caracteres visibles
      {prefix, suffix} = String.split_at(bin, len - 4)
      String.duplicate("*", String.length(prefix)) <> suffix
    end
  end

  defp put_if_present(map, key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)
end
