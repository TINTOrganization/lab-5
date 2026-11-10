#!/bin/sh
# Uso:  sh attacks.sh sin-waf    |    sh attacks.sh con-waf
if [ "$1" = "sin-waf" ]; then API=localhost:5000; WS=localhost:8000/ws
else API=localhost:8080/api; WS=localhost:8080/ws; fi

c() { curl -s -o /dev/null -w "%{http_code}" --max-time 2 "$@"; }
ws() { c -G "$WS" --data-urlencode "user=$1" -H "Connection: Upgrade" -H "Upgrade: websocket" \
       -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ=="; }
SQLI="' UNION SELECT name, secret FROM users--"
XSS='<img src=x onerror=alert(1)>'

echo "1. Búsqueda normal ...... $(c -G $API/messages --data-urlencode q=hola)"
echo "2. SQL injection ........ $(c -G $API/messages --data-urlencode "q=$SQLI")"
echo "   devolvió: $(curl -s -G $API/messages --data-urlencode "q=$SQLI" | tr -d "\n" | head -c 100)"
echo "3. XSS guardado ......... $(c $API/messages -H 'Content-Type: application/json' -d "{\"text\":\"$XSS\"}")"
echo "4. Escáner sqlmap ....... $(c -A sqlmap/1.8 $API/messages)"
echo "5. WebSocket normal ..... $(ws ana)"
echo "6. WebSocket con XSS .... $(ws "$XSS")"
echo "7. Puerto 5000 directo .. $(c localhost:5000/messages)"
echo "8. $(curl -s -D - -o /dev/null $API/messages | grep -i '^server')"
