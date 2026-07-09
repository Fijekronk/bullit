extends Node
## Autoload «NetConfig»: переносит выбор из меню (ник, роль, режим, IP) в
## сцену NetGame. Сеть v1 — простая передача без матчмейкинга.

var mode := "host"          # host / client / training
var join_ip := "127.0.0.1"
var port := 9050
var nick := "player"
var role := "field"         # field / goalie (выбор до старта раунда)
