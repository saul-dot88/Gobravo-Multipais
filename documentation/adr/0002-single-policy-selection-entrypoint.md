# ADR-0002: Un único punto de selección de Policy (eliminar doble fuente de verdad)

## Estado
Propuesto (para pulir el MVP)

## Contexto
El sistema aplica reglas por país (ES/IT/PT) mediante módulos de Policy.

Actualmente existen dos mecanismos para seleccionar la policy:
- `BravoMultipais.Policies.policy_for/1` (entrypoint “oficial”, levanta `ArgumentError` con mensaje claro si el país no está soportado)
- `BravoMultipais.Policies.Factory.policy_for/1` (selector alterno; ante país no soportado puede producir `FunctionClauseError`)

Estos dos caminos se usan en distintas partes:
- creación (`CreditApplications.Commands`) usa `Policies.policy_for/1`
- evaluación de riesgo (`Jobs.EvaluateRisk`) usa `Policies.Factory.policy_for/1`

Esto genera:
- Ambigüedad: “¿cuál es la forma correcta?”
- Fallos diferentes según el camino (ArgumentError vs FunctionClauseError)
- Mayor costo mental al extender países o depurar incidentes

## Decisión
Establecer **un solo entrypoint** para selección de policies:
- `BravoMultipais.Policies` será la única fuente de verdad.

Acciones derivadas:
1) Toda selección de policy se realizará mediante `BravoMultipais.Policies.policy_for/1`.
2) `BravoMultipais.Policies.Factory` se mantendrá solo como wrapper (deprecado) o se eliminará en un paso posterior:
   - `def policy_for(country), do: BravoMultipais.Policies.policy_for(country)`
3) `Jobs.EvaluateRisk` usará el mismo mecanismo que `Commands`.

## Consecuencias

### Positivas
- Ownership: una sola verdad para “qué países soportamos”.
- Goodwill: errores consistentes y con mensajes útiles.
- Agency: agregar un país implica modificar un único lugar y reduce riesgo de olvidos.
- Operación: menos retries inútiles por errores distintos en runtime.

### Negativas / trade-offs
- Cambia el modo de fallo en algunos caminos (de `FunctionClauseError` a `ArgumentError`).
- Requiere actualizar tests/referencias si existieran (en este repo solo se usa en `Jobs.EvaluateRisk`).

## Alternativas consideradas
1) Mantener ambos mecanismos y “documentar cuál usar”
   - Rechazada: la duplicación se presta a regresiones y confusión.
2) Hacer que Factory sea la oficial y Policies sea wrapper
   - Rechazada: `Policies` ya actúa como entrypoint y su error es más legible.

## Plan de implementación (alto nivel)
1) Cambiar `Jobs.EvaluateRisk` para usar `Policies.policy_for/1`.
2) Convertir `Policies.Factory` en wrapper deprecado (o eliminarlo en un PR posterior).
3) Asegurar que país no soportado falla de forma consistente.