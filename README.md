# Локальный отказоустойчивый контур мониторинга для Uptime Kuma

Тестовое задание Intern DevOps Safeboard 2026.

## Архитектура

Два независимых compose-слоя, связанные общей сетью `uptime-monitor-net`:

**Слой 1 — Приложение и БД** (`docker-compose.app.yml`)
- `uptime-mariadb` — MariaDB 11.4, volume `mariadb-data`
- `uptime-kuma` — Uptime Kuma 2.x, работает на MariaDB (не SQLite), volume `uptime-kuma-data`

**Слой 2 — Наблюдаемость** (`docker-compose.monitoring.yml`)
- `prometheus` — сбор метрик (порт 9090)
- `grafana` — визуализация (порт 3000)
- `node-exporter` — метрики хоста
- `cadvisor` — метрики контейнеров
- `blackbox-exporter` — доступность HTTP-сервисов
- `mysqld-exporter` — статус MariaDB

**Автоматизация** — Dagger-модуль на TypeScript (`dagger/`).

## Требования

- Linux / macOS / Windows 10+ (WSL2 + Docker Desktop)
- Docker Engine 24+ и Docker Compose v2
- Dagger CLI v0.21.11
- Node.js 18+ и npm (для TypeScript SDK)
- Go 1.23+ (не обязательно, но установлен)

## Подготовка окружения (Ubuntu)

```bash
# Docker
sudo apt update
sudo apt install -y docker.io docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker  # или перелогиниться

# Dagger CLI
curl -fsSL https://dl.dagger.io/dagger/install.sh | sudo BIN_DIR=/usr/local/bin sh

# Node.js + npm (для TypeScript SDK)
sudo apt install -y nodejs npm

## Запуск

### 1. Клонирование и настройка

```bash
git clone <repo> uptime-monitor
cd uptime-monitor
cp .env.example .env
# отредактируйте .env, задав надёжные пароли


```

### 2. Создание общей сети (один раз)

```bash
docker network create uptime-monitor-net
```

### 3. Установка зависимостей Dagger-модуля

```bash
cd dagger && npm install && cd ..
dagger develop
```

### 4. Запуск через Dagger

```bash
# Слой приложения
dagger call deploy-app --src=. --sock=/var/run/docker.sock --host-path=$(pwd)

# Слой мониторинга
dagger call deploy-monitoring --src=. --sock=/var/run/docker.sock --host-path=$(pwd)

# Настройка Grafana
dagger call configure-grafana --src=. --sock=/var/run/docker.sock --host-path=$(pwd)

# Бонус: всё одной командой
dagger call deploy-all --src=. --sock=/var/run/docker.sock --host-path=$(pwd)
```

### 5. Проверка работоспособности

| Сервис | URL | Доступ |
|---|---|---|
| Uptime Kuma | http://localhost:3001 | первичная настройка при первом входе |
| Grafana | http://localhost:3000 | `admin` / `GRAFANA_ADMIN_PASSWORD` из `.env` |
| Prometheus | http://localhost:9090 | без авторизации |

Все targets Prometheus: http://localhost:9090/targets — должны быть `UP`.
Импортированный дашборд: **Dashboards → Uptime Kuma Health**.

## Chaos Testing

```bash
dagger call chaos-test --src=. --sock=/var/run/docker.sock --host-path=$(pwd)
```

**Part A — видимость падения в Grafana:**

1. `probe_success` = 1 (сервис работает)
2. `docker pause uptime-kuma` → HTTP не отвечает
3. Ждём 20 секунд → `probe_success` = 0 (Grafana видит падение)
4. `docker unpause uptime-kuma` → сервис возвращается
5. Ждём 20 секунд → `probe_success` = 1 (Grafana видит восстановление)

**Part B — работа `restart: unless-stopped`:**

1. `docker exec uptime-kuma kill -9 1` — убиваем PID 1 изнутри (имитация аварии)
2. Docker видит завершение процесса → контейнер перезапускается за 1–2 секунды

**Почему `pause` для Part A и `kill -9 1` для Part B:**

- `docker kill` / `docker stop` — ручная остановка, `restart: unless-stopped` её не отменяет. Для проверки auto-restart нужен `kill -9 1`.
- `docker pause` замораживает cgroups — restart-policy не срабатывает, падение длится контролируемо 20 секунд, Prometheus (scrape_interval=15s) успевает записать `0`.

## Структура проекта

```
uptime-monitor/
├── .env                    # секреты (не коммитится)
├── .env.example            # шаблон без секретов
├── docker-compose.app.yml
├── docker-compose.monitoring.yml
├── dagger.json
├── dagger/
│   ├── src/index.ts        # Dagger-модуль на TypeScript
│   └── package.json
├── prometheus/
│   └── prometheus.yml
├── blackbox/
│   └── blackbox.yml
├── mysqld-exporter.cnf
├── mariadb/init/
│   └── 01-exporter-user.sql
├── scripts/
│   ├── deploy-app.sh
│   ├── deploy-monitoring.sh
│   ├── configure-grafana.sh
│   ├── chaos.sh
│   └── validate.sh
├── README.md
└── AI_REVIEW.md
```

## Остановка

```bash
docker compose -f docker-compose.monitoring.yml down
docker compose -f docker-compose.app.yml down
# с удалением данных: добавьте -v
```
