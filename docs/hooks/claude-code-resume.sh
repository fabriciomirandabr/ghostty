#!/bin/sh
mode=$1
[ "$TERM_PROGRAM" = "ghostty" ] || exit 0
input=$(cat)
pid=$$
depth=0
tty=
while [ "$depth" -lt 12 ] && [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
    name=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
    case "$name" in
        "" | "?" | "??" | "-") ;;
        *)
            tty=$name
            break
            ;;
    esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    depth=$((depth + 1))
done
[ -n "$tty" ] && [ -w "/dev/$tty" ] || exit 0
case "$mode" in
    set)
        id=$(printf '%s' "$input" | tr -d '\n' | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        h='[0123456789abcdef]'
        case "$id" in
            $h$h$h$h$h$h$h$h-$h$h$h$h-$h$h$h$h-$h$h$h$h-$h$h$h$h$h$h$h$h$h$h$h$h) ;;
            *) exit 0 ;;
        esac
        printf '\033]7501;state=clear:id=resume:resume=claude/%s\033\\' "$id" 2>/dev/null >"/dev/$tty"
        ;;
    clear)
        printf '\033]7501;state=clear:id=resume:resume=\033\\' 2>/dev/null >"/dev/$tty"
        ;;
esac
exit 0
