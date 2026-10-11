# Домашнее задание №2 — развёртывание YARN и публикация веб-интерфейсов

Цель работы — развернуть менеджер ресурсов YARN поверх HDFS-кластера из [домашнего задания №1](../homework1/README.md) и опубликовать веб-интерфейсы основных и вспомогательных демонов кластера для внешнего использования.

В рамках задания:

- развёрнуты **ResourceManager** (главный демон YARN, распределяет ресурсы кластера) и три **NodeManager** (запускают контейнеры с задачами на узлах);
- развёрнут вспомогательный демон **MapReduce JobHistory Server**, который хранит историю выполненных задач MapReduce и их логи;
- настроен запуск задач MapReduce в YARN;
- веб-интерфейсы всех демонов кластера (HDFS и YARN) опубликованы на edge-ноде через **nginx** с доступом по паролю и только на чтение; снаружи они открываются через SSH-туннель по адресам `localhost` (подробнее — в разделе «Опубликованные веб-интерфейсы»).

Развёртывание автоматизировано набором Bash-скриптов, которые продолжают скрипты первого задания: используют тот же `config.env`, общие функции из `lib.sh`, тот же подход с шаблонами конфигов и службами `systemd`. Все шаги можно безопасно запускать повторно.

## Архитектура

| Хост          | IP          | Роли из ДЗ №1                               | Роли из ДЗ №2 |
|---------------|-------------|---------------------------------------------|---------------|
| `team-24-en`  | 10.24.0.10  | edge-нода, HDFS-клиент                      | клиент YARN, **nginx** (публикация веб-интерфейсов) |
| `team-24-nn`  | 10.24.0.11  | NameNode, Secondary NameNode, DataNode      | **ResourceManager**, **NodeManager**, **JobHistory Server** |
| `team-24-00`  | 10.24.0.12  | DataNode                                    | **NodeManager** |
| `team-24-01`  | 10.24.0.13  | DataNode                                    | **NodeManager** |

Почему так:

- **NodeManager стоит на каждом узле с DataNode.** Так YARN может запускать задачи на тех же машинах, где лежат блоки данных, и не гонять данные по сети (принцип «вычисления ближе к данным»).
- **ResourceManager и JobHistory Server — на `team-24-nn`.** Отдельных машин под них у нас нет: курс выделил четыре ВМ, а edge-нода служит точкой входа. Поэтому управляющие демоны собраны на одной машине с NameNode, как и Secondary NameNode в первом задании.
- **nginx — на edge-ноде.** Только у неё есть внешний IP, внутренние узлы из интернета недоступны. nginx работает как обратный прокси: принимает запрос на внешний адрес и пересылает его нужному демону во внутренней сети.

```mermaid
flowchart TB
    user([Браузер]) -->|"SSH-туннель → localhost:порт"| nginx
    subgraph en[team-24-en — edge-нода]
        nginx[nginx<br/>basic auth, только чтение]
        client[клиент HDFS и YARN]
    end
    subgraph nn[team-24-nn]
        NN[NameNode :9870]
        SNN[Secondary NameNode :9868]
        RM[ResourceManager :8088]
        JHS[JobHistory Server :19888]
        NM0[NodeManager :8042]
        DN0[DataNode :9864]
    end
    subgraph n00[team-24-00]
        NM1[NodeManager :8042]
        DN1[DataNode :9864]
    end
    subgraph n01[team-24-01]
        NM2[NodeManager :8042]
        DN2[DataNode :9864]
    end
    nginx --> NN & SNN & RM & JHS & NM0 & DN0 & NM1 & DN1 & NM2 & DN2
    NM1 -. heartbeat .-> RM
    NM2 -. heartbeat .-> RM
    client -->|задачи MapReduce| RM
```

## Опубликованные веб-интерфейсы

Каждый интерфейс опубликован nginx на своём порту edge-ноды. Для основных демонов порт совпадает с их стандартным портом. Однотипные демоны на разных узлах (NodeManager, DataNode) слушают один и тот же порт, поэтому на edge-ноде им выделены соседние порты.

Облачная платформа курса пропускает к edge-ноде извне только SSH (порт 22), а входящие подключения на остальные порты блокирует на уровне сети:

```
$ nc -vz -G 5 2.59.83.107 22
Connection to 2.59.83.107 port 22 [tcp/ssh] succeeded!
$ nc -vz -G 5 2.59.83.107 8088
nc: connectx to 2.59.83.107 port 8088 (tcp) failed: Operation timed out
```

Поэтому к nginx подключаемся через SSH-туннель и открываем интерфейсы по адресам `localhost` — такой способ доступа подтверждён преподавателем. Запросы при этом всё равно проходят через nginx — с паролем и ограничением «только чтение». Если порты на стороне платформы откроют, те же интерфейсы станут доступны напрямую по адресу `http://2.59.83.107:<порт>` без изменений в скриптах.

| Демон | Тип | Адрес (через SSH-туннель) | Куда проксирует nginx |
|---|---|---|---|
| NameNode | основной (HDFS) | http://localhost:9870 | `team-24-nn:9870` |
| ResourceManager | основной (YARN) | http://localhost:8088 | `team-24-nn:8088` |
| Secondary NameNode | вспомогательный | http://localhost:9868 | `team-24-nn:9868` |
| JobHistory Server | вспомогательный | http://localhost:19888 | `team-24-nn:19888` |
| NodeManager на `team-24-nn` | рабочий | http://localhost:8042 | `team-24-nn:8042` |
| NodeManager на `team-24-00` | рабочий | http://localhost:8043 | `team-24-00:8042` |
| NodeManager на `team-24-01` | рабочий | http://localhost:8044 | `team-24-01:8042` |
| DataNode на `team-24-nn` | рабочий | http://localhost:9864 | `team-24-nn:9864` |
| DataNode на `team-24-00` | рабочий | http://localhost:9865 | `team-24-00:9864` |
| DataNode на `team-24-01` | рабочий | http://localhost:9866 | `team-24-01:9864` |

Список задаётся переменной `WEB_UI` в `config.env`, по нему автоматически генерируется конфиг nginx.

Ограничение: страницы Hadoop содержат ссылки на внутренние имена узлов (например, ссылка на NodeManager в интерфейсе ResourceManager ведёт на `team-24-00:8042`). Из браузера такие ссылки не откроются — нужно перейти по соответствующему адресу из таблицы.

### Безопасность

Веб-интерфейс и REST API ResourceManager без защиты позволяют любому запустить на кластере произвольный код, и открытые в интернет кластеры Hadoop регулярно взламывают боты-майнеры. Поэтому публикация сделана с двумя ограничениями:

- **вход по логину и паролю** (HTTP basic auth). Логин задаётся в `config.env` (`team24`), пароль генерируется случайно при первом запуске и хранится на edge-ноде в `homework2/.secrets/web-password` (в git не попадает);
- **только чтение**: nginx пропускает лишь запросы GET и HEAD, а любые изменяющие запросы (POST, PUT, DELETE) отклоняет с кодом 403. Смотреть интерфейсы можно, отправить задачу через REST API — нет.

## Структура

```
homework2/
├── README.md                  # эта инструкция
├── config.env                 # параметры YARN и публикации (дополняет ../homework1/config.env)
├── deploy.sh                  # развёртывание одной командой
├── .gitignore                 # build/ и .secrets/ не попадают в git
├── remote/
│   └── node-yarn.sh           # действия, которые выполняются на каждом узле
├── scripts/
│   ├── lib.sh                 # общие функции (подключает lib.sh первого задания)
│   ├── 00-check.sh            # проверка готовности кластера
│   ├── 01-configure.sh        # генерация и раскладка конфигов YARN и MapReduce
│   ├── 02-start.sh            # запуск ResourceManager, NodeManager и JobHistory Server
│   ├── 03-publish.sh          # публикация веб-интерфейсов через nginx
│   ├── 04-verify.sh           # проверка YARN, тестовая задача и проверка веб-интерфейсов
│   ├── stop.sh                # остановка YARN
│   └── destroy.sh             # удаление YARN и публикации
└── templates/
    ├── yarn-site.xml          # шаблон: ResourceManager, NodeManager, ресурсы, логи
    ├── mapred-site.xml        # шаблон: MapReduce в YARN, память задач, JobHistory Server
    ├── hadoop-yarn@.service   # шаблон службы systemd для ResourceManager и NodeManager
    └── hadoop-mapred@.service # шаблон службы systemd для JobHistory Server
```

При запуске создаются служебные каталоги `build/` (сгенерированные конфиги) и `.secrets/` (пароль от веб-интерфейсов).

## Как запустить

### Что нужно заранее

- Развёрнутый и работающий HDFS-кластер из первого задания (`homework1/deploy.sh`). Второе задание использует его скрипты и `config.env`, поэтому папки `homework1` и `homework2` должны лежать рядом.
- Всё то же, что и для первого задания: доступ к edge-ноде, SSH-ключ `team_internal` на edge-ноде, `sudo` без пароля на всех узлах.
- Доступ из edge-ноды в интернет для установки nginx через `apt` (если nginx ещё не установлен).

### 1. Подключиться к edge-ноде и обновить репозиторий

```bash
ssh team@2.59.83.107
cd PlatformsOfData
git pull
cd homework2
```

### 2. Запустить развёртывание

```bash
./deploy.sh
```

Скрипт выполняет шаги `00`–`04` по порядку. Это занимает 2–5 минут, большую часть времени — тестовая задача MapReduce.

### 3. Проверить результат

При успешном развёртывании в конце вывода появится строка:

```
OK YARN работает: ResourceManager, 3 NodeManager и JobHistory Server, тестовая задача выполнена, веб-интерфейсы опубликованы
```

и список адресов веб-интерфейсов. Пароль для входа можно посмотреть на edge-ноде:

```bash
cat ~/PlatformsOfData/homework2/.secrets/web-password
```

Если вместо итоговой строки появилось `FAIL`, в выводе будет указано, какая проверка не прошла. После устранения причины `deploy.sh` можно запустить повторно.

### 4. Открыть веб-интерфейсы

На своём компьютере, в новом окне терминала, поднимите SSH-туннель сразу ко всем опубликованным портам:

```bash
ssh -N \
  -L 9870:localhost:9870 -L 9868:localhost:9868 \
  -L 8088:localhost:8088 -L 19888:localhost:19888 \
  -L 8042:localhost:8042 -L 8043:localhost:8043 -L 8044:localhost:8044 \
  -L 9864:localhost:9864 -L 9865:localhost:9865 -L 9866:localhost:9866 \
  team@2.59.83.107
```

Команда ничего не выводит и «висит» — это значит, что туннель открыт. `localhost` во второй половине каждого `-L` означает саму edge-ноду, то есть туннель ведёт именно к nginx, а не в обход него.

Не закрывая это окно, откройте в браузере, например, http://localhost:8088 (ResourceManager), введите логин `team24` и пароль. На странице **Nodes** должны быть три узла в состоянии **RUNNING**, а в списке приложений — тестовая задача `QuasiMonteCarlo` со статусом **SUCCEEDED**. Та же задача видна в JobHistory Server: http://localhost:19888.

Чтобы закрыть туннель, нажмите `Ctrl + C` в этом окне терминала.

### 5. Запустить свою задачу (по желанию)

С edge-ноды от имени пользователя `hadoop`:

```bash
# вычисление числа Pi методом Монте-Карло
sudo -u hadoop /opt/hadoop/bin/yarn jar \
    /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.4.1.jar pi 3 1000

# список узлов YARN
sudo -u hadoop /opt/hadoop/bin/yarn node -list
```

### Остановка и удаление

На edge-ноде из папки `homework2`:

```bash
# остановить YARN (HDFS и nginx продолжат работать)
./scripts/stop.sh

# запустить YARN снова
./scripts/02-start.sh

# удалить YARN и публикацию веб-интерфейсов (HDFS не затрагивается)
./scripts/destroy.sh
```

## Описание файлов

### `config.env` — параметры

Параметры, относящиеся только к YARN: на каких узлах работают ResourceManager, NodeManager и JobHistory Server, их порты, сколько памяти и ядер каждый NodeManager отдаёт под контейнеры, сколько памяти получают контейнеры задач MapReduce, а также логин и список публикуемых веб-интерфейсов. Всё остальное (узлы, пути, пользователь `hadoop`, версии) берётся из `config.env` первого задания, чтобы не дублировать настройки.

Памяти под контейнеры выделено 2 ГБ на узел. Это значение должно быть заметно меньше объёма RAM узла, ведь на `team-24-nn` ещё работают NameNode, Secondary NameNode, DataNode, ResourceManager и JobHistory Server. Скрипт `00-check.sh` предупредит, если памяти может не хватить.

### `remote/node-yarn.sh` — действия на узле

Аналог `node.sh` из первого задания, но для YARN. Содержит действия, которые выполняются на узлах от имени администратора: размещение конфигурации (`configure`), запуск и остановка демонов (`start`, `stop`), проверка состояния (`status`), проверка логов (`logs`) и удаление (`purge`). Роль узла определяется по `config.env`: на `team-24-nn` — ResourceManager, NodeManager и JobHistory Server, на `team-24-00` и `team-24-01` — NodeManager, edge-нода — клиент.

### `lib.sh` — общая библиотека

Подключает `lib.sh` первого задания, поэтому все его функции (выполнение команд на узлах по SSH, копирование файлов, вывод сообщений, метрики NameNode, ожидание порта) доступны и здесь. Дополнительно содержит:

- загрузку `config.env` второго задания;
- сборку и отправку на узлы скрипта `node-yarn.sh` и запуск на узле нужного действия (`build_yarn_node_script`, `push_yarn`, `yarn_do`);
- генерацию конфигов YARN из шаблонов (`render_yarn_configs`) и конфига nginx по списку `WEB_UI` (`render_nginx_conf`);
- генерацию и хранение пароля к веб-интерфейсам (`web_password`);
- выполнение команд `yarn` от имени пользователя `hadoop` (`yarn_cmd`) и получение метрик ResourceManager через JMX (`rm_metric`).

### `00-check.sh` — проверка готовности

Проверяет, что HDFS из первого задания работает (все три DataNode живы), Hadoop установлен на всех узлах, на edge-ноде есть `sudo` без пароля и нужные утилиты. Выводит таблицу с ролями YARN и объёмом памяти каждого узла и предупреждает, если NodeManager отдаёт под контейнеры больше 60% памяти узла. Также проверяет, что контейнеры задач MapReduce помещаются в память NodeManager.

### `01-configure.sh` — конфигурация

Генерирует на edge-ноде из шаблонов в папке `templates` файлы `yarn-site.xml`, `mapred-site.xml` и шаблоны служб `systemd`, подставляя значения из обоих `config.env`. Затем копирует их на все узлы, включая edge-ноду (с неё отправляются задачи, поэтому клиенту тоже нужны конфиги), и запускает на каждом узле действие `configure`. Оно раскладывает конфиги в каталог Hadoop, устанавливает службы `systemd`, создаёт рабочие каталоги контейнеров и включает автозапуск только тех демонов, которые назначены этому узлу.

Главное в конфигах:

- `yarn-site.xml` — адрес ResourceManager; сервис `mapreduce_shuffle` на NodeManager, через который reduce-задачи забирают результаты map-задач; ресурсы узла под контейнеры; сбор логов контейнеров в HDFS после завершения задачи (их потом показывает JobHistory Server);
- `mapred-site.xml` — запуск MapReduce в YARN (`mapreduce.framework.name=yarn`); переменная `HADOOP_MAPRED_HOME` для контейнеров (без неё задачи падают с ошибкой «Could not find or load main class MRAppMaster»); память контейнеров; адрес JobHistory Server.

### `02-start.sh` — запуск

Создаёт в HDFS каталоги, нужные задачам MapReduce (`/tmp` с правами на запись для всех и `/user/hadoop`), и запускает демоны по порядку, после каждого шага убеждаясь, что он действительно заработал:

1. **ResourceManager** — скрипт ждёт, пока он откроет порты для клиентов и веб-интерфейса;
2. **NodeManager** на трёх узлах — скрипт ждёт, пока все три зарегистрируются в ResourceManager (проверяется через его метрики);
3. **JobHistory Server** — скрипт ждёт, пока он откроет порт веб-интерфейса.

### `03-publish.sh` — публикация веб-интерфейсов

Устанавливает nginx на edge-ноду (если его нет), генерирует конфиг с отдельным `server` на каждый веб-интерфейс из `WEB_UI`, создаёт файл с логином и паролем, проверяет конфиг командой `nginx -t` и перезапускает nginx. Если на edge-ноде включён файрвол `ufw`, открывает в нём нужные порты. В конце выводит список опубликованных портов и демонов, на которые они ведут.

### `04-verify.sh` — проверка

Проверяет в пять этапов:

1. **демоны на узлах** — запущены все назначенные службы, процессы видны в `jps`;
2. **состояние по данным ResourceManager** (JMX): три активных NodeManager, ноль потерянных, нездоровых и выведенных из эксплуатации; выводится `yarn node -list`;
3. **тестовая задача MapReduce** — вычисление числа Pi из стандартных примеров Hadoop. Проверяется, что задача завершилась в YARN со статусом `SUCCEEDED` и появилась в JobHistory Server;
4. **веб-интерфейсы через nginx** — каждый из десяти адресов отвечает кодом 200; без пароля nginx отвечает 401, а на изменяющий запрос к REST API ResourceManager — 403;
5. **логи демонов YARN** — нет записей уровня FATAL (записи ERROR выводятся как предупреждение).

Скрипт выполняет все проверки до конца, помечает непройденные строкой `FAIL` и в этом случае завершается с ошибкой.

### `stop.sh` — остановка

Останавливает демоны в обратном порядке: JobHistory Server → NodeManager → ResourceManager. HDFS и nginx продолжают работать, запустить YARN снова можно через `02-start.sh`.

### `destroy.sh` — удаление

Удаляет всё, что добавило второе задание: службы и конфиги YARN, рабочие каталоги и логи YARN на всех узлах, конфиг nginx и файл с паролем на edge-ноде. HDFS из первого задания не затрагивается, nginx остаётся установленным. Скрипт просит подтверждение (ввести идентификатор кластера) или запускается с флагом `--yes`.

## Проверка работы

После развёртывания скрипт `04-verify.sh` прошёл все проверки:

```
 OK Active NodeManagers = 3
 OK Final-State application_1791735894567_0001 = SUCCEEDED
 OK задача job_1791735894567_0001 в JobHistory = SUCCEEDED
 OK resourcemanager :8088 = 200          (и ещё 9 веб-интерфейсов)
 OK без пароля на :8088 = 401
 OK POST к REST API на :8088 = 403
 OK YARN работает: ResourceManager, 3 NodeManager и JobHistory Server, тестовая задача выполнена, веб-интерфейсы опубликованы
```

Затем мы открыли опубликованные веб-интерфейсы через SSH-туннель и nginx.

### ResourceManager: узлы кластера

Страница **Nodes** (http://localhost:8088/cluster/nodes). В кластере 3 активных узла (`Active Nodes = 3`), потерянных, нездоровых и выведенных из эксплуатации нет. Все три NodeManager — на `team-24-nn`, `team-24-00` и `team-24-01` — в состоянии **RUNNING**, каждый отдаёт под контейнеры 2 ГБ памяти и 2 ядра, всего в кластере 6 ГБ и 6 ядер. Максимальный размер контейнера (2048 МБ, 2 ядра) совпадает с настройками из `config.env`.

<img width="2682" height="970" alt="image" src="https://github.com/user-attachments/assets/4e61b00b-17a6-4211-9a60-1985e4a8b4e3" />

### ResourceManager: приложения

Страница **Applications** (http://localhost:8088/cluster/apps). Тестовая задача `QuasiMonteCarlo` (вычисление числа Pi) типа `MAPREDUCE`, запущенная скриптом проверки от пользователя `hadoop`, выполнилась в YARN: состояние **FINISHED**, итоговый статус **SUCCEEDED**.

<img width="2556" height="770" alt="image" src="https://github.com/user-attachments/assets/acc75dd0-9102-4d31-8d26-015142a59123" />

### JobHistory Server: история задач

Вспомогательный демон JobHistory Server (http://localhost:19888/jobhistory) сохранил историю той же задачи `job_1791735894567_0001`: статус **SUCCEEDED**, выполнены 3 из 3 map-задач и 1 из 1 reduce-задачи, время выполнения — 24 секунды. Значит, MapReduce полностью работает в YARN, включая этап shuffle между map и reduce.

<img width="2668" height="552" alt="image" src="https://github.com/user-attachments/assets/fe57246c-4ef4-451d-ba0e-b9556cb0b3e2" />

### NameNode: DataNode

Вкладка **Datanodes** NameNode (http://localhost:9870/dfshealth.html#tab-datanode) показывает, что через nginx опубликован и интерфейс HDFS: все три DataNode в состоянии **In service**. В HDFS появились блоки — это файлы, которые записала тестовая задача (её входные данные и история для JobHistory Server).

<img width="1660" height="1364" alt="image" src="https://github.com/user-attachments/assets/a31c35ae-956a-4be0-8649-8ffdb252c0b1" />

### NodeManager на узле team-24-00

Страница NodeManager на `team-24-00` (http://localhost:8043). Узел здоров (`NodeHealthyStatus = true`), под контейнеры выделено 2 ГБ физической памяти и 2 ядра, проверка виртуальной памяти отключена (`Vmem enforcement enabled = false`) — всё как в `yarn-site.xml`. Версия Hadoop — 3.4.1.

<img width="2196" height="538" alt="image" src="https://github.com/user-attachments/assets/c6a80dcf-09e2-4110-b51d-8c3e9a10d5c4" />

Выводы тестов при развертывании YARN:

<img width="749" height="683" alt="image" src="https://github.com/user-attachments/assets/be74f2f8-7608-4cf8-abf8-f439be7c1e65" />

<img width="694" height="708" alt="image" src="https://github.com/user-attachments/assets/9546fb4c-9aec-4044-a5b9-d0afaeac36ca" />

<img width="888" height="483" alt="image" src="https://github.com/user-attachments/assets/ae8ec02f-6f05-4849-b42a-5f1cdc24c3e8" />
