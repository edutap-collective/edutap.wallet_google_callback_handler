# syntax=docker/dockerfile:1
# Two stages: the build installs the package, the runtime image carries only the
# result. Plain `pip install` on purpose -- `uv` belongs in the development
# environment, not in a container image.
# ONE PLACE FOR THE PYTHON VERSION. Both stages and the copied path below are
# derived from this argument, because they have to agree: `pip install` puts the
# package under the interpreter's own directory, and the runtime stage copies
# from exactly there.
#
# Keeping them in separate literals is what broke the build of
# edutap.webhook_heidi on 2026-09-13: Renovate raised the `FROM python:` lines
# -- correctly, that is its job -- while the hard-coded
# `/usr/local/lib/python3.13/site-packages` in the COPY stayed behind, and the
# build failed with `failed to compute cache key: ... not found`. It failed at
# the next build, not at the merge.
#
# This file had the same shape and would have broken the same way at the next
# version bump. Nothing was wrong with it today -- that is exactly what made it
# worth changing.
#
# renovate: datasource=docker depName=python versioning=docker
ARG PYTHON_VERSION=3.14

FROM python:${PYTHON_VERSION}-slim AS build
WORKDIR /app
COPY pyproject.toml README.md ./
COPY src ./src
# `.` and not `.[kafka]`: aiokafka is an ordinary dependency now. The extra
# promised a choice this package never offered, since `main` imports `kafka`,
# which imports `aiokafka` at module level.
RUN pip install --no-cache-dir .

FROM python:${PYTHON_VERSION}-slim
# An ARG declared before the first FROM is outside every build stage; naming
# it again here brings it into this one. Without this line the substitution
# below would silently expand to an empty string.
ARG PYTHON_VERSION
# The interpreter of the base image is 3.14, so this is where `pip install` put
# the package in the build stage. Changing the base image tag means changing
# these two paths with it.
COPY --from=build /usr/local/lib/python${PYTHON_VERSION}/site-packages /usr/local/lib/python${PYTHON_VERSION}/site-packages
COPY --from=build /usr/local/bin /usr/local/bin

# 8086 is the port the stack routes to; the deployment overrides it either way.
ARG HTTP_PORT=8086
ENV HTTP_PORT=${HTTP_PORT}

RUN useradd --create-home --uid 10001 app
WORKDIR /app
USER app
EXPOSE ${HTTP_PORT}

# `--proxy-headers` because Traefik terminates TLS in front of this and the
# service has to see the original scheme and host.
CMD ["sh", "-c", "uvicorn edutap.wallet_google_callback_handler.main:app --proxy-headers --host 0.0.0.0 --port $HTTP_PORT --access-log"]
