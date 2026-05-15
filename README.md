# prueba-soap

API Rails inicial configurada para correr solo con Docker.

## Requisitos

- Docker
- Docker Compose

No hace falta instalar Ruby, MySQL ni Redis en la maquina local.

## Stack

- Ruby 3.2.3
- Rails 7.2
- MySQL 8.0
- Redis 7
- Sidekiq 7
- Rails en modo API only

## Servicios

El archivo `docker-compose.yml` levanta:

- `web`: servidor Rails disponible en `http://localhost:3000`
- `db`: MySQL interno de Docker
- `redis`: Redis interno de Docker
- `sidekiq`: servicio base, sin workers de negocio definidos

La base usa el usuario `root` con password `root`.

## Levantar el proyecto

Construir las imagenes:

```bash
docker compose build
```

Crear la base de datos:

```bash
docker compose run web rails db:create
```

Levantar todos los servicios:

```bash
docker compose up
```

Verificar que Rails levanta:

```bash
docker compose ps
```

Tambien se puede consultar `http://localhost:3000`. En esta etapa no hay endpoints implementados, por lo que una respuesta `404` de Rails es esperada.

## Alcance actual

Este proyecto solo contiene infraestructura inicial:

- setup Rails API
- Docker
- MySQL
- Redis
- Sidekiq base
- configuracion inicial

Todavia no incluye:

- logica SOAP
- endpoints de negocio
- autenticacion
- Swagger/OpenAPI
- logica de negocio
- cache de aplicacion
- workers Sidekiq
- rate limiting
- logica async
- servicios VIES
- serializers
- frontend o dashboard

## Comandos utiles

Ejecutar comandos Rails:

```bash
docker compose run web rails --help
```

Abrir consola Rails:

```bash
docker compose run web rails console
```

Detener los servicios:

```bash
docker compose down
```

Detener servicios y borrar volumenes de datos:

```bash
docker compose down -v
```

## Notas

- MySQL y Redis no exponen puertos al host; solo se usan desde la red interna de Docker.
- El unico puerto expuesto para desarrollo es `3000`.
- Todavia no hay logica de negocio implementada.
