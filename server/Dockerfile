# The Lumina Marketplace API, built from the repository root so the shared
# package is in the build context:
#   docker compose up --build        (MARKETPLACE_JWT_SECRET from .env)
FROM dart:stable
WORKDIR /src
COPY shared/ shared/
COPY server/ server/
WORKDIR /src/server
# The repository is a pub workspace whose web member needs Flutter, so the
# image resolves server + shared on their own (without `resolution: workspace`).
# `dart build cli` runs package:sqlite3's build hook (a verified SQLite with
# FTS5) and bundles the executable with its native library.
RUN sed -i '/^resolution: workspace/d' pubspec.yaml ../shared/pubspec.yaml && dart pub get && dart build cli --target bin/server.dart -o /app \
 && cp openapi.yaml /app/bundle/bin/ && cp -r seed /app/bundle/bin/seed
ENV MARKETPLACE_HOST=0.0.0.0 MARKETPLACE_PORT=8787 MARKETPLACE_DATA_DIR=/data
WORKDIR /app/bundle/bin
EXPOSE 8787
ENTRYPOINT ["/app/bundle/bin/server"]
