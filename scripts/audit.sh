#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}
echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] Служба SSH"
check "Вход от имени root запрещён"        "no"  "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no"  "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
port="$(sudo sshd -T | awk '/^port /{print $2; exit}')"
if [[ -n "$port" && "$port" != "22" ]]; then
    check "Порт SSH отличен от 22" "$port" "$port"
else
    check "Порт SSH отличен от 22" "не 22" "${port:-пусто}"
fi
check "Лимит попыток аутентификации равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2; exit}')"
echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
policy="$(sudo ufw status verbose | awk '/^Default:/{print $2; exit}')"
check "Политика входящего трафика — deny" "deny" "$policy"
echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
nginx_rc=0
sudo nginx -t >/dev/null 2>&1 || nginx_rc=$?
check "Конфигурация nginx корректна" "0" "$nginx_rc"
cert_rc=0
sudo openssl x509 -checkend $((30*24*60*60)) -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1 || cert_rc=$?
check "Сертификат действует ещё не менее 30 дней" "0" "$cert_rc"
ww="$(find /var/www/devops-site -perm -o+w | wc -l)"
ww="${ww//[[:space:]]/}"
keymode="$(sudo stat -c '%a' /etc/ssl/private/devops.key)"
if [[ "$ww" == "0" && "$keymode" == "600" ]]; then
    perms="ok"
else
    perms="files=$ww key=$keymode"
fi
check "Нет файлов с записью для всех, права ключа 600" "ok" "$perms"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
