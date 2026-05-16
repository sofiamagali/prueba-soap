# prueba-soap

API Rails para validar VAT numbers contra VIES usando SOAP manual, MySQL, Redis y Sidekiq.

## Stack

- Ruby 3.2.3
- Rails 7.2 en modo API only
- MySQL 8.0
- Redis 7
- Sidekiq 7
- Docker Compose

## Levantar el proyecto

```bash
docker compose build
docker compose run --rm web bin/rails db:prepare
docker compose up
```

La API queda disponible en:

```text
http://localhost:3000
```

Servicios principales:

- `web`: Rails API
- `db`: MySQL
- `redis`: Redis para Sidekiq
- `sidekiq`: procesamiento async de validaciones VAT

## Endpoints

### Crear validacion

```bash
curl -X POST http://localhost:3000/api/v1/vat_validations \
  -H "Content-Type: application/json" \
  -d '{"country_code":"IE","vat_number":"6388047V"}'
```

Respuestas esperadas:

- `201 Created`: VIES respondio antes de 3 segundos y se guarda `status: completed`.
- `202 Accepted`: VIES tuvo un error transitorio o supero 3 segundos, se guarda `status: pending` y se encola Sidekiq.
- `422 Unprocessable Content`: parametros locales invalidos o VIES respondio `INVALID_INPUT`.

Si existe una validacion `completed` para el mismo `country_code` + `vat_number` en las ultimas 24 horas, responde desde cache con `cached: true` y no llama a VIES.

### Ver una validacion

```bash
curl http://localhost:3000/api/v1/vat_validations/1
```

### Listar validaciones

```bash
curl "http://localhost:3000/api/v1/vat_validations?page=1&per_page=10"
```

Filtros disponibles:

- `country_code`
- `valid`: acepta solo `true`, `false`, `1`, `0`
- `date_from`
- `date_to`
- `page`
- `per_page`

Ejemplo:

```bash
curl "http://localhost:3000/api/v1/vat_validations?country_code=IE&valid=true&page=1&per_page=10"
```

### Estadisticas

```bash
curl http://localhost:3000/api/v1/vat_validations/stats
```

Devuelve:

- `total_validations`
- `completed_validations`
- `pending_validations`
- `failed_validations`
- `valid_percentage`
- `invalid_percentage`
- `top_countries`

Los porcentajes de validas/invalidas se calculan solo sobre validaciones `completed`.

## Async con Sidekiq

Cuando VIES tiene un error transitorio o tarda mas de 3 segundos:

1. La API crea una validacion `pending`.
2. Responde `202 Accepted`.
3. Encola `VatValidationWorker`.
4. Sidekiq vuelve a llamar a VIES.
5. El registro pasa a `completed` si VIES responde bien o a `failed` si vuelve a fallar.

El fault `INVALID_INPUT` de VIES se considera un error de validacion del request y responde `422`; no se persiste ni se encola.

## Circuit breaker

La integracion con VIES incluye un circuit breaker simple para evitar seguir llamando a un servicio externo cuando esta degradado.

- Se abre despues de 5 errores transitorios consecutivos (`SERVICE_UNAVAILABLE`, `MS_UNAVAILABLE`, `TIMEOUT`, `SERVER_BUSY` o timeouts de red).
- Permanece abierto durante 5 minutos.
- Mientras esta abierto, las nuevas validaciones se guardan como `pending`, responden `202 Accepted` y se procesan luego con Sidekiq.
- `INVALID_INPUT` no cuenta como fallo del circuito porque representa un error del request, no una caida de VIES.

Ver logs:

```bash
docker compose logs -f sidekiq
```

## Tests

```bash
docker compose run --rm web bin/rails test
```

Verificar autoloading:

```bash
docker compose run --rm web bin/rails zeitwerk:check
```

## Bruno

La coleccion Bruno esta en:

```text
bruno/vat-validations
```

Incluye requests para create, cache, errores, show, index, filtros, stats y `INVALID_INPUT` de VIES. Los casos async dependen de errores transitorios o timeouts reales de VIES.

## Notas tecnicas

- La integracion SOAP esta implementada manualmente con `Net::HTTP` y `Nokogiri`; no se usan gems SOAP.
- La cache de 24 horas se resuelve consultando registros `completed` persistidos.
- El circuit breaker usa `Rails.cache` para mantener la implementacion liviana y suficiente para el alcance de la prueba.
- Sidekiq usa `retry: false` para evitar reintentos infinitos en esta prueba.
- MySQL y Redis solo se exponen dentro de la red Docker.
