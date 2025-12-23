defmodule BravoMultipais.LogSanitizer do
  @moduledoc """
  Utilidades para enmascarar PII en logs (documentos, etc).
  """

  # ── Documentos ───────────────────────────────────────────────

  # Sin documento
  def mask_document(nil), do: nil

  # Documento como string plano, ej. "12345678Z"
  def mask_document(doc) when is_binary(doc) do
    size = String.length(doc)

    cond do
      size <= 4 ->
        String.duplicate("*", size)

      true ->
        # ocultamos todo menos los últimos 4 caracteres
        {prefix, suffix} = String.split_at(doc, size - 4)
        String.duplicate("*", String.length(prefix)) <> suffix
    end
  end

  # Documento como mapa (ej: %{"dni" => "12345678Z", "raw" => "12345678Z"})
  def mask_document(%{} = doc) do
    doc
    |> Enum.into(%{}, fn {k, v} ->
      cond do
        is_binary(v) ->
          {k, mask_document(v)}

        is_map(v) ->
          # por si anidas otro map dentro
          {k, mask_document(v)}

        true ->
          {k, v}
      end
    end)
  end

  # Cualquier otra cosa rara: la devolvemos tal cual para no romper
  def mask_document(other), do: other
end
