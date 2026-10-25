# Бонусное ДЗ

[Полный лог](terminal.log) 

- Prometheus: http://localhost:9091, 
- алерты: http://localhost:9091/alerts. 
Поставил 9091, на 9090 уже ДЗ 3.


## 1. Образ

### 1.1. Запуск без root

Поставил `USER app`, чтобы не от root. Проверка:

```bash
docker run --rm --entrypoint id bonus-url-probe
```

```text
uid=1000(app) gid=1000(app) groups=1000(app)
```

### 1.2. Образ меньше 100 МБ

Взял Alpine, он небольшой. Собрал и посмотрел размер:

```bash
docker build --progress=plain -t bonus-url-probe .
docker images bonus-url-probe
```

```text
IMAGE                    ID             DISK USAGE   CONTENT SIZE   EXTRA
bonus-url-probe:latest   d2f2918d6f9f       94.6MB         26.5MB   U
```
94,6 МБ, меньше 100 МБ.

### 1.3. Настройки отдельно

В образе скрипт и расписание. URL подключил файлом, таймаут через окружение:

```yaml
environment:
  PROBE_TIMEOUT: "6"
  PROBE_OUTPUT_DIR: /textfile
volumes:
  - ./url-probe:/config:ro
  - textfile:/textfile
```

## 2. Запуск по расписанию

### 2.1. Проверка каждую минуту

Запуск через Supercronic, раз в минуту:

```cron
* * * * * python3 /app/probe.py /config/urls.txt
```

Посмотрел лог:

```bash
docker compose logs -f url-probe
```

```text
url-probe-1  | time="2026-10-25T11:14:00Z" level=info msg=starting iteration=0 job.command="python3 /app/probe.py /config/urls.txt" job.position=0 job.schedule="* * * * *"
url-probe-1  | time="2026-10-25T11:15:00Z" level=info msg=starting iteration=1 job.command="python3 /app/probe.py /config/urls.txt" job.position=0 job.schedule="* * * * *"
```

Запуски в 11:14 и 11:15, разница минута.

### 2.2. Логи

```text
url-probe-1  | time="2026-10-25T11:14:00Z" level=info msg="OK   200  0.014s http://test-site/" channel=stderr iteration=0 job.command="python3 /app/probe.py /config/urls.txt" job.position=0 job.schedule="* * * * *"
url-probe-1  | time="2026-10-25T11:14:00Z" level=info msg="FAIL 404  0.001s http://test-site/no-such-page" channel=stderr iteration=0 job.command="python3 /app/probe.py /config/urls.txt" job.position=0 job.schedule="* * * * *"
url-probe-1  | time="2026-10-25T11:14:05Z" level=info msg="FAIL   0  5.005s http://no-such-host.invalid" channel=stderr iteration=0 job.command="python3 /app/probe.py /config/urls.txt" job.position=0 job.schedule="* * * * *"
url-probe-1  | time="2026-10-25T11:14:11Z" level=info msg="FAIL   0  6.010s http://10.255.255.1" channel=stderr iteration=0 job.command="python3 /app/probe.py /config/urls.txt" job.position=0 job.schedule="* * * * *"
```

Есть OK и FAIL. Скрипт вернул 1, потому что часть адресов не работает. 

### 2.3. Таймаут

Сначала поставил 2 секунды:

```bash
docker compose exec url-probe printenv PROBE_TIMEOUT
```
Ответ: 2


В логе:

```text
url-probe-1  | time="2026-10-25T11:10:07Z" level=info msg="FAIL   0  2.004s http://10.255.255.1" channel=stderr iteration=0 job.command="python3 /app/probe.py /config/urls.txt" job.position=0 job.schedule="* * * * *"
```

```bash
nano compose.yaml
docker compose up -d url-probe
docker compose exec url-probe printenv PROBE_TIMEOUT
```

Ответ: 6

Поменял на 6, без пересборки. В логе:

```text
url-probe-1  | time="2026-10-25T11:14:11Z" level=info msg="FAIL   0  6.010s http://10.255.255.1" channel=stderr iteration=0 job.command="python3 /app/probe.py /config/urls.txt" job.position=0 job.schedule="* * * * *"
```

Было 2 секунды, стало 6.

### 2.4. Добавил URL

Время старта до изменения:

```bash
docker inspect --format '{{.State.StartedAt}}' bonus-url-probe-1
```

```text
2026-10-25T11:13:57.467326997Z
```

Добавил адрес:

```bash
echo 'http://test-site/index.html' >> url-probe/urls.txt
docker compose logs --tail=12 url-probe
```

```text
url-probe-1  | time="2026-10-25T11:24:11Z" level=info msg="OK   200  0.006s http://test-site/index.html" channel=stderr iteration=10 job.command="python3 /app/probe.py /config/urls.txt" job.position=0 job.schedule="* * * * *"
```

Ещё раз той же командой:

```text
2026-10-25T11:13:57.467326997Z
```

Новый адрес проверяется, время старта то же. Файл подключён через volume, перезапуск не нужен.

### 2.5. Сбой

Поставил `restart: unless-stopped`, чтобы сам запускался после сбоя.

До сбоя:

```bash
docker inspect --format '{{.HostConfig.RestartPolicy.Name}} {{.RestartCount}} {{.State.Status}}' bonus-url-probe-1
```

```text
unless-stopped 0 running
```

Завершил планировщик:

```bash
docker compose exec url-probe pkill -9 supercronic
```

Ещё раз проверл состояние:

```text
unless-stopped 1 running
```

Сам запустился, теперь перезапусков 1.

## 3. Мониторинг

### 3.1. Запуск и метрики

Метрики идут в файл в общем томе. Его читает Node Exporter, оттуда забирает Prometheus.

Запустил всё:

```bash
docker compose up -d
docker compose ps
```

```text
NAME                    IMAGE                       COMMAND                  SERVICE         CREATED          STATUS          PORTS
bonus-node-exporter-1   prom/node-exporter:v1.9.1   "/bin/node_exporter …"   node-exporter   4 seconds ago    Up 4 seconds    9100/tcp
bonus-prometheus-1      prom/prometheus:v3.5.0      "/bin/prometheus --c…"   prometheus      4 seconds ago    Up 4 seconds    127.0.0.1:9091->9090/tcp
bonus-test-site-1       nginx:alpine                "/docker-entrypoint.…"   test-site       20 minutes ago   Up 20 minutes   80/tcp
bonus-url-probe-1       bonus-url-probe             "/usr/local/bin/supe…"   url-probe       13 minutes ago   Up 12 minutes
```

`test-site` — Nginx, его буду останавливать для проверки.

Проверил метрики:

```bash
curl -s 'http://localhost:9091/api/v1/query?query=probe_success' | python3 -m json.tool
```

Из ответа:

```text
{"metric":{"__name__":"probe_success","instance":"node-exporter:9100","job":"node","url":"http://10.255.255.1"},"value":[1792927898.725,"0"]}
{"metric":{"__name__":"probe_success","instance":"node-exporter:9100","job":"node","url":"http://no-such-host.invalid"},"value":[1792927898.725,"0"]}
{"metric":{"__name__":"probe_success","instance":"node-exporter:9100","job":"node","url":"http://test-site/"},"value":[1792927898.725,"1"]}
{"metric":{"__name__":"probe_success","instance":"node-exporter:9100","job":"node","url":"http://test-site/index.html"},"value":[1792927898.725,"1"]}
{"metric":{"__name__":"probe_success","instance":"node-exporter:9100","job":"node","url":"http://test-site/no-such-page"},"value":[1792927898.725,"0"]}
```

Рабочие страницы — 1. Страница 404, несуществующий домен и адрес с таймаутом — 0.

### 3.2. Алерт

Добавил правило: если проверка не проходит минуту, срабатывает алерт.

```yaml
groups:
  - name: url-probe
    rules:
      - alert: URLDown
        expr: probe_success == 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "URL недоступен: {{ $labels.url }}"
```

Проверил правило:

```bash
docker compose exec prometheus promtool check rules /etc/prometheus/rules.yml
```

```text
Checking /etc/prometheus/rules.yml
  SUCCESS: 1 rules found
```

Остановил сайт и посмотрел алерты:

```bash
docker compose stop test-site
curl -s http://localhost:9091/api/v1/alerts | python3 -m json.tool
```

Сначала pending (часть ответа):

```text
"url": "http://test-site/"
"state": "pending"
"activeAt": "2026-10-25T11:33:37.658669594Z"
```

Подождал, повторил запрос. Уже firing:

```text
"url": "http://test-site/"
"state": "firing"
"activeAt": "2026-10-25T11:33:37.658669594Z"
```

Скриншот:

![Алерт firing](screenshots/alert%20firing.png)

Запустил сайт обратно:

```bash
docker compose start test-site
```

Подождал и снова посмотрел:

```bash
curl -s http://localhost:9091/api/v1/alerts | python3 -m json.tool
```

Из ответа — остались только эти адреса:

```text
"url": "http://test-site/no-such-page"
"state": "firing"

"url": "http://10.255.255.1"
"state": "firing"

"url": "http://no-such-host.invalid"
"state": "firing"
```

Для `/` и `/index.html` алерты пропали. Проверил метрики:

```bash
curl -s 'http://localhost:9091/api/v1/query?query=probe_success' | python3 -m json.tool
```

Эти две страницы в ответе:

```text
{"metric":{"__name__":"probe_success","instance":"node-exporter:9100","job":"node","url":"http://test-site/"},"value":[1792928339.69,"1"]}
{"metric":{"__name__":"probe_success","instance":"node-exporter:9100","job":"node","url":"http://test-site/index.html"},"value":[1792928339.69,"1"]}
```

У обеих опять значние 1. Остальные три адреса специально нерабочие.

## Ответы на вопросы

1 **Почему textfile подходит для url-probe, а audit-svc лучше отдавать /metrics?**

Скрипт сделал проверку и завершился. Результат остался в файле, Node Exporter его читает между запусками. А `audit-svc` работает постоянно и может сам отдавать `/metrics`.

2 **Что будет, если планировщик перестанет запускать проверки, но контейнер останется жив?**

`probe_success` будет со старым результатом. `up` останется 1, пока Node Exporter отвечает, даже если проверки больше не идут.

Можно смотреть, давно ли была проверка:

time() - probe_last_run_timestamp_seconds > 120


Больше 120 секунд — результат уже старый. Если метрика вообще пропала, можно проверить через `absent(probe_last_run_timestamp_seconds)`. Такой алерт отдельно не делал.

