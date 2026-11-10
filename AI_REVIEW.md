# AI REVIEW

## Использованные инструменты

- **Claude (Anthropic)** — основной ассистент для архитектуры, кода Dagger-модуля, compose-файлов и shell-скриптов.
- **ChatGPT** — точечные вопросы по Dagger API и Grafana API.

AI использовался для:
- генерации каркаса Dagger-модуля (Go → TypeScript после серии ошибок)
- compose-файлов для обоих слоёв
- конфигурации Prometheus (scrape jobs, relabel)
- JSON-дашборда Grafana
- shell-скриптов в `scripts/`
- диагностики ошибок по логам

**Вся финальная проверка, отладка и работа с реальным окружением — выполнены вручную.**

---

## 3–5 примеров, где AI ошибся

### 1. `dag.Host()` в Go SDK — несовместимая версия

**Что предложил AI:** использовать `dag.Host().UnixSocket(...)` и `dag.Host().Directory(...)` в Go-модуле.

**Что пошло не так:** Dagger v0.21.11 при кодогенерации подтянул **pre-release SDK** `dagger.io/dagger v1.0.0-beta.15`, в котором `Host()` отсутствует. Ошибка компиляции: `dag.Host undefined (type *dagger.Client has no field or method Host)`. Фиксация версии через `engineVersion` и `sdk.version` в `dagger.json` игнорировалась.

**Как обнаружили:** `go build ./...` в `dagger/` упал с указанной ошибкой.

**Как исправили:** перешли на **TypeScript SDK**, где `dag.host()` стабильно доступен (на тот момент считали, что это решит проблему — см. п. 2).

---

### 2. `dag.host()` недоступен в модулях — архитектурное ограничение

**Что предложил AI:** использовать `dag.host().directory(...)` и `dag.host().unixSocket(...)` внутри TypeScript-модуля.

**Что пошло не так:** `dag.host is not a function`. В Dagger-модулях, в отличие от standalone-скриптов, **нет доступа к хосту** — это архитектурное ограничение.

**Как обнаружили:** ошибка при `dagger call deploy-app`.

**Как исправили:** передаём `Directory` и `Socket` **как аргументы функции**:
```bash
dagger call deploy-app --src=. --sock=/var/run/docker.sock

```

---

### 3. Bind-mount `/workspace` не работает с хостовым Docker daemon

**Что предложил AI:** монтировать проект в `/workspace` и выполнять `docker compose` оттуда.

**Что пошло не так:** `docker compose` резолвит `./prometheus/prometheus.yml` в `/workspace/prometheus/prometheus.yml` **внутри контейнера Dagger**. Docker daemon на хосте получает этот путь, но на хосте `/workspace` не существует. Ошибка:
```
mount src=/workspace/prometheus/prometheus.yml ... not a directory
```

**Как обнаружили:** `deploy-monitoring` упал с `OCI runtime create failed: mount src=/workspace/...`.

**Как исправили:** передаём **абсолютный путь проекта на хосте** параметром `--host-path=$(pwd)` и монтируем по тому же пути внутри контейнера (`withMountedDirectory(hostPath, src)`).

---

### 4. `docker kill` не запускает `restart: unless-stopped`

**Что предложил AI:** остановить контейнер через `docker kill uptime-kuma` и проверить, что restart-policy его поднимет.

**Что пошло не так:** `docker kill` и `docker stop` — **ручные** остановки. `restart: unless-stopped` их не отменяет (контейнер остаётся `Exited`).

**Как обнаружили:** после `docker kill` контейнер не поднялся, `probe_success` остался `0`.

**Как исправили:** используем `docker exec uptime-kuma kill -9 1` — убиваем PID 1 изнутри. Docker трактует это как аварию и применяет restart-policy.

---

### 5. `docker pause` слишком быстро исчезает для Prometheus

**Что предложил AI:** `docker kill` для проверки видимости падения в Grafana.

**Что пошло не так:** restart-policy перезапускает контейнер за 1 секунду, а Prometheus скрейпит раз в 15 секунд — метрика `probe_success` физически не успевает стать `0`.

**Как обнаружили:** `DURING OUTAGE` показывал `1` вместо `0`.

**Как исправили:** разделили тест на две части — `docker pause` (контейнер заморожен, не перезапускается, падение длится 20 секунд) и `docker exec ... kill -9 1` (проверка auto-restart).

---

### 6. Экранирование shell-команд внутри TypeScript-шаблонов

**Что предложил AI:** встроить shell-скрипты с регулярками и JSON напрямую в `index.ts` через template literals.

**Что пошло не так:** многослойное экранирование (Python → TypeScript → shell → grep/curl) привело к:
- потере `\[` в `grep -oE '"value":\[[^]]*\]'` (стало `[^]]*]` — регулярка сломалась)
- конфликту двойных кавычек в `echo "BEFORE: $(...)"` — внешние `"` закрывались кавычками из JSON-запроса
- `mktemp` + `docker run -v` не работал из Dagger-контейнера: файл создавался в файловой системе контейнера, а `-v` искал его на хосте

**Как обнаружили:** серия `exit code: 1` без внятных сообщений, пустые `BEFORE/DURING/AFTER`, ошибки `curl: option -d: error encountered when reading a file`.

**Как исправили:** **вынесли всю shell-логику в отдельные файлы** `scripts/*.sh` и вызываем их из Dagger через `withExec(["sh", "scripts/chaos.sh"])`. Это:
- тестируется независимо (`sh scripts/chaos.sh` работает на хосте без Dagger)
- не требует экранирования
- читаемо и сопровождаемо

---

### 7. `mktemp` + `docker run -v` не работает из Dagger

**Что предложил AI:** создать временный файл с JSON-дашбордом через `mktemp` и передать его в `docker run -v`.

**Что пошло не так:** `mktemp` создаёт файл в `/tmp` **внутри Dagger-контейнера**. Docker daemon на хосте получает путь `/tmp/tmp.XYZ` и ищет его **на хосте**, где его нет.

**Как обнаружили:** `curl: option -d: error encountered when reading a file`.

**Как исправили:** передаём JSON через **stdin** (`docker run -i ... -d @-`), без каких-либо файлов и mount'ов.

---

### 8. Точечные правки `index.ts` через `python3` + regex

**Что предложил AI:** заменять методы в `index.ts` через `re.sub()` с паттернами.

**Что пошло не так:** после серии замен файл оказался в **смешанном состоянии** — часть методов обновлена, часть нет, лишние фрагменты после закрывающей `}`. `npx tsc` выдал десятки ошибок `TS1434`. Dagger же просто показывал `exit code: 1` без вывода.

**Как обнаружили:** `npx tsc --noEmit` показал реальные ошибки компиляции, которые Dagger не отображает.

**Как исправили:** **перезаписываем файл целиком** через `cat > ... <<'EOF'` и всегда проверяем `npx tsc --noEmit` перед `dagger call`. Точечные regex-правки кода — плохая практика.

