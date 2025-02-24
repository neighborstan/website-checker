#!/bin/bash

# === 🔹 Настройки ===
TELEGRAM_BOT_TOKEN="${{ secrets.TELEGRAM_BOT_TOKEN }}"
CHAT_ID="${{ secrets.CHAT_ID }}"
LOG_FILE="monitoring/site_monitor.log"
STATUS_FILE="monitoring/site_status.log"
IP_ADDRESS=$(curl -s4 ifconfig.me)  # Определяем IP-адрес GitHub Actions runner

# В этом массиве указываем домены БЕЗ https://
SITES=(
    "huter-gmbh.ru"
    "ecoflow-russia.com"
    "stels-rf.ru"
    "resanta24.ru"
    "hrobots.ru"
)

# === 📌 Проверяем, существует ли STATUS_FILE, если нет — создаём ===
if [ ! -f "$STATUS_FILE" ]; then
    touch "$STATUS_FILE"
    echo "$(date) - 🆕 Создан файл статусов: $STATUS_FILE" >> "$LOG_FILE"
fi

echo "$(date) - 🔄 Запуск проверки сайтов... (Сервер IP GitHub Actions: $IP_ADDRESS)" >> "$LOG_FILE"

for DOMAIN in "${SITES[@]}"; do
    # Формируем полный URL c https://
    FULL_URL="https://${DOMAIN}"

    echo "$(date) - 🔍 Проверка сайта: $FULL_URL" >> "$LOG_FILE"

    # Определяем IP-адрес хоста сайта
    SITE_IP=$(dig +short "$DOMAIN" | head -n 1)
    if [[ -z "$SITE_IP" ]]; then
        SITE_IP="Неизвестный IP"
    fi

    # Получаем HTTP-статус
    STATUS=$(/usr/bin/curl -o /dev/null -s -w "%{http_code}" "$FULL_URL" | tr -d '\n' | tr -d '\r')

    echo "$(date) - Код ответа от $FULL_URL ($SITE_IP): $STATUS" >> "$LOG_FILE"

    # Читаем предыдущий статус сайта (по умолчанию "UP")
    PREV_STATUS=$(grep "$DOMAIN" "$STATUS_FILE" | awk '{print $2}' || echo "UP")

    # === 🔥 Проверка доступности ===
    if [[ "$STATUS" -ne 200 && "$STATUS" -ne 301 && "$STATUS" -ne 302 ]]; then
        if [[ "$PREV_STATUS" != "DOWN" ]]; then
            # Формируем HTML-сообщение
            MESSAGE="⚠️ <b>Внимание!</b>%0A"
            MESSAGE+="❌ Сайт <a href=\"$FULL_URL\">$DOMAIN</a> недоступен (код: $STATUS)%0A"
            MESSAGE+="🌍 <b>IP сервера:</b> <code>$SITE_IP</code>%0A"
            MESSAGE+="🚀 <b>Мониторинг запущен с:</b> <code>$IP_ADDRESS</code>"

            echo "$(date) - ❌ Сайт $DOMAIN упал! Отправляем уведомление..." >> "$LOG_FILE"

            # === ✉️ Отправка сообщения в Telegram ===
            RESPONSE=$(/usr/bin/curl -s -X POST \
                "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
                -d "chat_id=$CHAT_ID" \
                -d "parse_mode=HTML" \
                -d "text=$MESSAGE" \
                -d "disable_web_page_preview=true" \
                2>&1
            )

            echo "$(date) - 📤 Ответ от Telegram API: $RESPONSE" >> "$LOG_FILE"

            # Обновляем статус сайта
            sed -i "/$DOMAIN/d" "$STATUS_FILE"
            echo "$DOMAIN DOWN" >> "$STATUS_FILE"
        fi
    else
        if [[ "$PREV_STATUS" == "DOWN" ]]; then
            MESSAGE="✅ <b>Восстановлено!</b>%0A"
            MESSAGE+="🎉 Сайт <a href=\"$FULL_URL\">$DOMAIN</a> снова работает (код: $STATUS)%0A"
            MESSAGE+="🌍 <b>IP сервера:</b> <code>$SITE_IP</code>%0A"
            MESSAGE+="🚀 <b>Мониторинг запущен с:</b> <code>$IP_ADDRESS</code>"

            echo "$(date) - ✅ Сайт $DOMAIN восстановился! Отправляем уведомление..." >> "$LOG_FILE"

            RESPONSE=$(/usr/bin/curl -s -X POST \
                "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
                -d "chat_id=$CHAT_ID" \
                -d "parse_mode=HTML" \
                -d "text=$MESSAGE" \
                -d "disable_web_page_preview=true" \
                2>&1
            )

            echo "$(date) - 📤 Ответ от Telegram API: $RESPONSE" >> "$LOG_FILE"
        fi

        sed -i "/$DOMAIN/d" "$STATUS_FILE"
        echo "$DOMAIN UP" >> "$STATUS_FILE"
        echo "$(date) - ✅ Сайт $DOMAIN доступен (код: $STATUS)" >> "$LOG_FILE"
    fi
done

# === 🗑 Очищаем лог, оставляя только последние 100 строк ===
tail -n 100 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"

echo "$(date) - ✅ Проверка завершена." >> "$LOG_FILE"
