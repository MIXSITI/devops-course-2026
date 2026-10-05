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

OpenSSH server в исходном образе установлен не был. До снимка `01-clean-install` выполнены `apt-get update` и `apt-get install -y openssh-server`. Обновлений пакетов сверх этого не было (`0 upgraded`).

## 2. Сетевые интерфейсы

- Адаптер 1, NAT, интерфейс `enp0s3`: `10.0.2.15/24`. Нужен для исходящего доступа в интернет и репозитории пакетов. С хоста гость напрямую по этому адресу не доступен.
- Адаптер 2, Host-only (`VirtualBox Host-Only Ethernet Adapter`), интерфейс `enp0s8`: `192.168.56.101/24`. Адрес хоста в этом сегменте — `192.168.56.1`. Используется для доступа к службам гостя из браузера и по имени `devops.local`.

## 3. Правило проброса портов

Правило NAT с именем `ssh`, протокол TCP:

- адрес хоста: `127.0.0.1`
- порт хоста: `2222`
- адрес гостя: не задан
- порт гостя: `2222`

До задания 2 порт гостя был `22`. После перевода `sshd` на порт 2222 правило изменено командой `VBoxManage controlvm devops-vm natpf1`.

На хосте в `C:\Windows\System32\drivers\etc\hosts` добавлена строка:

```
192.168.56.101   devops.local
```

## 4. Учётные записи

- `mix` (uid 1000), группы включают `sudo`. Пароль `student`. Вход по SSH запрещён директивой `AllowUsers devops`. Консольный вход в окне VirtualBox сохраняется. Аутентификация, пока SSH ещё слушал порт 22, была парольной.
- `devops` (uid 1001), полное имя DevOps, группы `devops sudo users`. Пароль `student` нужен для `sudo`. Домашний каталог `/home/devops`. Вход по SSH только ключом Ed25519.
- Закрытый ключ хоста: `C:\Users\Svetlana\.ssh\devops_vm` (комментарий `devops-vm-key`, без парольной фразы). Открытый ключ лежит в `/home/devops/.ssh/authorized_keys`. Права: каталог `700`, файл `600`.
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

Проверка: `ssh devops` и `ssh -p 2222 devops@devops.local`. Пароль SSH не запрашивается.

Отпечаток ключа хоста Ed25519, сверенный до первого доверия: `SHA256:vnq4tYqxQiM6zq7SXAIronDSc031B7G2rGGb9pB9mSM`.

## 5. Служба SSH

- Порт прослушивания: `2222` на `0.0.0.0` и `::`
- Файл дополнения: `/etc/ssh/sshd_config.d/99-hardening.conf`
- Эталонная копия основного файла: `/etc/ssh/sshd_config.backup`
- Основной `/etc/ssh/sshd_config` не изменялся. Каталог `sshd_config.d` до работы был пуст, конфликтующей директивы `PasswordAuthentication yes` не было.
- Сокетная активация отключена: `systemctl disable --now ssh.socket`, служба включена как `ssh.service`. Иначе порт остаётся 22 из unit-файла `ssh.socket`.

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

Действующие значения подтверждены `sudo sshd -T`, а не чтением файла. После перезапуска `ss -tlnp` показывает `0.0.0.0:2222`.

До hardening строка клиента была `Authentications that can continue: publickey,password`. После — только `publickey`.

## 6. Правила межсетевого экрана

Политики по умолчанию:

- incoming: deny
- outgoing: allow
- routed: disabled

Правила (логирование `medium`):

- `80/tcp` ALLOW IN, комментарий HTTP
- `443/tcp` ALLOW IN, комментарий HTTPS
- `2222/tcp` LIMIT IN, комментарий `SSH rate-limited`

Правило LIMIT создано после `ufw enable`: сначала был `ufw allow 2222/tcp`, затем `ufw delete allow 2222/tcp` и `ufw limit 2222/tcp`. Символическое имя `ssh` не использовалось: в `/etc/services` оно означает порт 22.

Порядок включения обязателен: разрешающее правило для 2222/tcp создаётся до `ufw enable`.

Проверка блокировки: `curl -m 3 http://192.168.56.101:8080` с хоста завершается таймаутом. В `/var/log/ufw.log` запись `[UFW BLOCK]` содержит `SRC=192.168.56.1`, `DST=192.168.56.101`, `PROTO=TCP`, `DPT=8080`.

## 7. Снимки состояния

- `01-clean-install` — 5 октября 2026, 18:23 (UTC+3). Машина выключена после установки пакетов и запуска OpenSSH, до создания пользователя `devops`.
- `02-keys-configured` — 5 октября 2026, 18:27 (UTC+3). Пользователь `devops`, вход по ключу, парольная аутентификация ещё включена, SSH на порту 22.
- `03-ssh-hardened` — 5 октября 2026, 18:30 (UTC+3). SSH на порту 2222, вход root запрещён, пароль отключён, проброс NAT указывает на гостевой порт 2222. Межсетевой экран на этом снимке ещё не включён.

Полное доменное имя узла: `devops-vm.devops.local` (`hostnamectl set-hostname devops-vm`, в `/etc/hosts` строка `127.0.1.1 devops-vm.devops.local devops-vm`).

## Восстановление после снимка 01-clean-install

1. Запустить машину и войти как `mix` / `student` либо по `ssh -p 2222 mix@127.0.0.1`, пока действует проброс на гостевой порт 22. Если проброс уже указывает на 2222, вернуть гостевой порт 22.
2. Создать `devops`, задать пароль `student`, добавить в группу `sudo`.
3. Скопировать `~/.ssh/devops_vm.pub` в `/home/devops/.ssh/authorized_keys`, выставить права `700` и `600`.
4. Записать блок `Host devops` в клиентский `~/.ssh/config`.
5. Положить `/etc/ssh/sshd_config.d/99-hardening.conf` как в разделе 5, выполнить `sshd -t`.
6. `systemctl disable --now ssh.socket`, `systemctl enable --now ssh.service`, `systemctl restart ssh`. Убедиться, что слушается порт 2222.
7. Сменить гостевой порт правила NAT `ssh` с 22 на 2222.
8. Проверить `ssh devops`, отказ для `root` и отказ при `PubkeyAuthentication=no`.
9. Задать политики UFW, разрешить 2222, 80 и 443, выполнить `ufw enable`, заменить правило 2222 на `limit`, включить `ufw logging medium`.
10. Добавить `192.168.56.101 devops.local` в hosts хоста и строку FQDN в `/etc/hosts` гостя.
