# ─────────────────────────────────────────────
# Stage 1: Build (compilar deps, assets y release)
# ─────────────────────────────────────────────
FROM elixir:1.16-alpine AS build

# Sistema base para compilar
RUN apk add --no-cache build-base git curl

ENV MIX_ENV=prod \
    LANG=C.UTF-8

WORKDIR /app

# Instalar Hex y Rebar (gestores de paquetes de Elixir/Erlang)
RUN mix local.hex --force && \
    mix local.rebar --force

# Copiamos archivos de definición de deps primero para caché
COPY mix.exs mix.lock ./
COPY config config

# Descargar y compilar dependencias sólo para prod
RUN mix deps.get --only prod && \
    mix deps.compile

# Copiar el resto del proyecto
COPY lib lib
COPY priv priv
# Si tienes assets/ con esbuild/tailwind
COPY assets assets

# Compilar assets (Phoenix 1.7: mix assets.deploy)
RUN mix assets.deploy

# Compilar el proyecto
RUN mix compile

# Generar el release (en _build/prod/rel/bravo_multipais)
RUN mix release

# ─────────────────────────────────────────────
# Stage 2: Runtime (imagen ligera)
# ─────────────────────────────────────────────
FROM alpine:3.19 AS app

# Dependencias mínimas para ejecutarse
RUN apk add --no-cache openssl ncurses-libs

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    SHELL=/bin/sh

WORKDIR /app

# Copiamos el release ya construido
COPY --from=build /app/_build/prod/rel/bravo_multipais ./

# Puerto interno del contenedor (debe coincidir con PORT en K8s)
EXPOSE 4000

# Importante:
# PHX_SERVER=true lo pasamos vía ENV (ConfigMap) para que el release arranque el endpoint.
# Comando para iniciar el release
CMD ["bin/bravo_multipais", "start"]