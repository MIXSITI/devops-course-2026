# Конфигурация виртуальной машины devops-vm

Документ описывает фактическое состояние узла после практической работы № 5. По нему конфигурацию можно восстановить после отката на снимок `01-clean-install`.

## 1. Параметры машины

- Средство виртуализации: VirtualBox 7.2.20
- Имя: `devops-vm`
- Гостевая система: Ubuntu 26.04.1 LTS, Linux 7.0.0-38-generic, 64-bit
- Оперативная память: 2048 МБ
- Процессор: 2 ядра
- Диск: 25 ГБ, динамический VDI (`devops-vm.vdi`)
- Учётная запись установки: `mix`, пароль `student` (в методичке эта роль названа `student`)

OpenSSH server в исходном образе установлен не был. До снимка `01-clean-install` выполнены `apt-get update` и `apt-get install -y openssh-server`.

## 2. Сетевые интерфейсы

- Адаптер 1, NAT, интерфейс `enp0s3`: `10.0.2.15/24`. Нужен для исходящего доступа в интернет и репозитории пакетов. С хоста гость напрямую по этому адресу не доступен.
- Адаптер 2, Host-only (`VirtualBox Host-Only Ethernet Adapter`), интерфейс `enp0s8`: `192.168.56.101/24`. Адрес хоста в этом сегменте — `192.168.56.1`. Используется для доступа к службам гостя с хоста и по имени `devops.local`.

На адаптере Host-only включён DHCP: сервер `192.168.56.100`, пул с `192.168.56.101`.

## 3. Правило проброса портов

Правило NAT с именем `ssh`, протокол TCP:

- адрес хоста: `127.0.0.1`
- порт хоста: `2222`
- адрес гостя: не задан
- порт гостя: `2222`

До задания 2 порт гостя был `22`. После перевода `sshd` на порт 2222 правило изменено: гостевой порт `2222`.

На хосте в `C:\Windows\System32\drivers\etc\hosts` добавлена строка:

```
192.168.56.101   devops.local
```

## 4. Учётные записи

- `mix` (uid 1000), группы включают `sudo`. Пароль `student`. Вход по SSH запрещён директивой `AllowUsers devops`. Консольный вход в окне VirtualBox сохраняется.
- `devops` (uid 1001), полное имя DevOps, группы `devops`, `sudo`, `users`. Пароль `student` нужен для `sudo`. Домашний каталог `/home/devops`. Вход по SSH только ключом Ed25519.
- Закрытый ключ: `C:\Users\Svetlana\.ssh\devops_vm` (комментарий `devops-vm-key`, без парольной фразы). Открытый ключ лежит в `/home/devops/.ssh/authorized_keys`. Права: каталог `700`, файл `600`.
- Клиентский файл `C:\Users\Svetlana\.ssh\config`:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    User devops
    Port 2222
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Проверка: `ssh devops` и `ssh devops.local`. Пароль SSH не запрашивается.

Отпечаток ключа хоста Ed25519: `SHA256:vnq4tYqxQiM6zq7SXAIronDSc031B7G2rGGb9pB9mSM`.

## 5. Служба SSH

- Порт прослушивания: `2222` на `0.0.0.0` и `::`
- Файл дополнения: `/etc/ssh/sshd_config.d/99-hardening.conf`
- Эталонная копия основного файла: `/etc/ssh/sshd_config.backup`
- Основной `/etc/ssh/sshd_config` не изменялся. Конфликтующей директивы `PasswordAuthentication yes` в `sshd_config.d` нет: в основном файле соответствующая строка закомментирована.
- Сокетная активация отключена: `ssh.socket` — disabled/inactive, `ssh.service` — enabled/active. Иначе порт остаётся 22 из параметров юнита `ssh.socket`.

Директивы `/etc/ssh/sshd_config.d/99-hardening.conf`:

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Действующие значения подтверждены `sudo sshd -T`. После перезапуска `ss -tlnp` показывает `0.0.0.0:2222`.

До отключения пароля строка клиента была `Authentications that can continue: publickey,password`. После hardening — только `publickey`.

## 6. Правила межсетевого экрана

Политики по умолчанию (вывод `ufw status verbose`):

- incoming: deny
- outgoing: allow
- routed: deny

Правила, логирование `medium`:

- `80/tcp` ALLOW IN, комментарий HTTP
- `443/tcp` ALLOW IN, комментарий HTTPS
- `2222/tcp` LIMIT IN, комментарий `SSH rate-limited`

Правило LIMIT создано после `ufw enable`: сначала `ufw allow 2222/tcp`, затем `ufw delete allow 2222/tcp` и `ufw limit 2222/tcp`. Символическое имя `ssh` не использовалось: в `/etc/services` оно означает порт 22.

Порядок включения: разрешающее правило для 2222/tcp создаётся до `ufw enable`.

Проверка блокировки: `curl -m 3 http://192.168.56.101:8080` с хоста завершается таймаутом. В `/var/log/ufw.log` запись `[UFW BLOCK]` содержит `SRC=192.168.56.1`, `DST=192.168.56.101`, `PROTO=TCP`, `DPT=8080`. Файл журнал читается командой `grep -a`, потому что в нём встречаются байты, из-за которых обычный `grep` считает файл двоичным.

## 7. Снимки состояния

- `01-clean-install` — 5 октября 2026, 18:23 (UTC+3). Машина выключена после установки пакетов и запуска OpenSSH, до создания пользователя `devops`.
- `02-keys-configured` — 5 октября 2026, 18:27 (UTC+3). Пользователь `devops`, вход по ключу, парольная аутентификация ещё включена, SSH на порту 22.
- `03-ssh-hardened` — 5 октября 2026, 18:30 (UTC+3). SSH на порту 2222, вход root запрещён, пароль отключён, проброс NAT указывает на гостевой порт 2222. Межсетевой экран на этом снимке ещё не включён.

Полное доменное имя узла: `devops-vm.devops.local` (`hostnamectl set-hostname devops-vm`, в `/etc/hosts` строка `127.0.1.1 devops-vm.devops.local devops-vm`).

## Восстановление после снимка 01-clean-install

1. Запустить машину и войти как `mix` / `student` либо по `ssh -p 2222 mix@127.0.0.1`, пока действует проброс на гостевой порт 22. Если проброс уже указывает на 2222, вернуть гостевой порт 22.
2. Создать `devops`, задать пароль `student`, добавить в группу `sudo`.
3. Скопировать `~/.ssh/devops_vm.pub` в `/home/devops/.ssh/authorized_keys`, выставить права `700` и `600`.
4. Записать блоки `Host devops` и `Host devops.local` в клиентский `~/.ssh/config`.
5. Положить `/etc/ssh/sshd_config.d/99-hardening.conf` как в разделе 5, выполнить `sshd -t`.
6. `systemctl disable --now ssh.socket`, `systemctl enable --now ssh.service`, `systemctl restart ssh`. Убедиться, что слушается порт 2222.
7. Сменить гостевой порт правила NAT `ssh` с 22 на 2222.
8. Проверить `ssh devops`, отказ для `root` и отказ при `PubkeyAuthentication=no`.
9. Задать политики UFW, разрешить 2222, 80 и 443, выполнить `ufw enable`, заменить правило 2222 на `limit`, включить `ufw logging medium`.
10. Добавить `192.168.56.101 devops.local` в hosts хоста и строку FQDN в `/etc/hosts` гостя.

## 8. Веб-сервер

- Пакет: `nginx` 1.28.3 (Ubuntu). Профиль UFW `Nginx Full` не добавлялся: порты 80 и 443 уже разрешены правилами работы № 5.
- Активная конфигурация: `/etc/nginx/sites-available/devops-site`, ссылка `/etc/nginx/sites-enabled/devops-site`. Стандартный ресурс отключён: ссылка `/etc/nginx/sites-enabled/default` удалена, файл `/etc/nginx/sites-available/default` сохранён.
- Каталог ресурса: `/var/www/devops-site`, владелец `devops:devops`. Каталог `755`, файлы `644`. Эти права выставляет `rsync --chmod=D755,F644`.
- Сертификат: `/etc/ssl/certs/devops.crt`, права `644`, владелец `root`. Закрытый ключ: `/etc/ssl/private/devops.key`, права `600`, владелец `root`. Ключ за пределы `/etc/ssl/private` не копируется. Срок: выпущен 18 октября 2026, истекает 18 октября 2027. SAN: `DNS:devops.local`. Сертификат самоподписанный: subject и issuer равны `CN=devops.local`.
- Команда выпуска:

```
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

- HTTP на порту 80 отвечает `301` на `https://$host$request_uri`. HTTPS слушает 443, протоколы TLSv1.2 и TLSv1.3. Заголовок HSTS не используется.
- Доставка: `scripts/deploy.sh` из репозитория, одна SSH-сессия rsync (cwRsync и его ssh). Проверка после доставки: `curl --cacert ~/devops.crt https://devops.local`.
- В блоке HTTPS сохранён `location /app/`, добавленный для последующей работы с контейнером. Он не заменяет статический ресурс `devops.local`.

Снимок состояния после перевода ресурса на HTTPS: `04-nginx-https` (18 октября 2026, 17:55 UTC+3).

## 9. Контейнеризация

- Docker Engine установлен из официального репозитория `https://download.docker.com/linux/ubuntu` (suite `resolute`, компонент `stable`), не из пакета `docker.io`. Версия Engine: 29.9.1 (`5:29.9.1-1~ubuntu.26.04~resolute`). Docker Compose: v5.6.0.
- Группа `docker`: учётная запись `devops` (у неё уже есть `sudo`). Участник этой группы может смонтировать корень хоста в контейнер и тем самым получить права root, поэтому в группу не добавляют учётки без sudo.
- Проект на сервере: `/home/devops/app`. Файл секретов `/home/devops/app/.env`, права `600`, владелец `devops`. В репозитории его нет; шаблон — `app/.env.example`. Доставка: `rsync -avz --delete --exclude=.env`.
- Образ приложения: `devops-app:1.0`, процесс в контейнере — пользователь `app` (uid 999), не root.
- Публикация портов: приложение только `127.0.0.1:5000` → контейнер `5000`. Порт СУБД не публикуется, обращение по имени `db` в сети `app_backend`.
- Именованный том: `app_db_data`, смонтирован в `/var/lib/postgresql/data`. Образ СУБД `postgres:16-alpine`. `docker compose down` сохраняет том, `docker compose down -v` удаляет его.
- Обратный прокси: Nginx принимает HTTPS и передаёт `/app/` на `http://127.0.0.1:5000/`. Статический ресурс `devops.local` сохранён.

Снимок состояния: `05-docker-compose`.

## 10. Ansible

- Проект: каталог `ansible/` в репозитории `devops-course-2026`, ветка `feature/ansible`.
- Управляющий узел: Ubuntu 24.04 в WSL (`ansible-core` 2.16.3, `sshpass` 1.09). Репозиторий для запуска лежит в домашнем каталоге WSL, не на `/mnt/c`.
- Управляемый узел: `devops-vm`, снимок `01-clean-install`, Ubuntu Server 26.04.1, Host-only `192.168.56.101`.
- Первичный inventory `bootstrap.ini`: пользователь установки `mix` (в методичке эта роль названа `student`), порт 22, ключ `~/.ssh/devops_vm`. Пароль нужен только для первого `sudo`.
- Последующий inventory `prod.ini`: пользователь `devops`, тот же ключ, `sudo` без пароля.
- Роли: `base` (пакеты и Docker Engine из официального репозитория), `ssh` (учётная запись `devops`, ключ, `sudo`, hardening, UFW), `nginx` (обратный прокси на порт контейнера), `app` (загрузка образа и контейнер).
- Образ: `ghcr.io/mixsiti/devops-ci-app`. Тег — полный SHA `4181a531ac61c9e619b4d69fcbfc1ed130d13c74`, не `latest`.
- Контейнер `devops-ci-app` публикует `127.0.0.1:5000` на порт контейнера `5000`. Наружу открыты только 22/tcp и 80/tcp.
- Проверка здоровья: `http://127.0.0.1:5000/health` на VM и `http://192.168.56.101/health` с управляющего узла.
- Первый запуск: `ansible-playbook -i inventory/bootstrap.ini site.yml` из каталога `ansible/`. Повторный: `ansible-playbook site.yml`. Аудит без изменений: `ansible-playbook verify.yml`.
- В `ansible.cfg` включено `force_handlers = True`. На VM для модулей Docker установлен `python3-requests`.

