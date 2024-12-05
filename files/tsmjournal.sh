#!/bin/sh

INITFILE=/etc/init.d/tsmjournal
SERVICE_PID_FILE=/var/run/tsmjournal.pid

INMEMORY=$(uci get tsmjournal.database.inmemory)
ONDISK=$(uci get tsmjournal.database.ondisk)

APP=$0
CMD=$1
UI=$2
usage() {
    echo "Usage: $APP [ COMMAND ] [/ui]"
    echo
    echo "Commands are:"
    echo "    start/stop"
    echo "    load      Load journal from disk to memory"
    echo "    dump      Dump journal from memory to disk"
    echo "    clear     Clear both: memory & disk"
    echo "    help      Show this and exit"
    echo
    echo "    load/dump/clear ui   Return status/error used in UIJournal.js.htm"
}

callinit() {
    [ -x $INITFILE ] || {
        echo "No init file '$INITFILE'"
        return
    }
    exec $INITFILE $1
    RETVAL=$?
}

run() {
    uci set tsmjournal.debug.enable='0'
    uci commit

    sleep 1
    exec /usr/bin/lua /usr/lib/lua/tsmjournal/app.lua
    RETVAL=$?
}

dump() {
	# Если нет директории для хранения на диске - создать
	# Если нет директории для хранения в памяти - создать
	ERR="$(mkdir -p ${INMEMORY} 2>&1)"
	ERR="$ERR $(mkdir -p ${ONDISK} 2>&1)"
	ERR="$ERR $(cp -rf ${INMEMORY}/* ${ONDISK} 2>&1)"

    size=${#ERR}
    # Если нет ошибки и параметр "ui" не передан в командной строке
    if [ $size -lt 3 ] && [ -z $UI ]; then
	    echo "[tsmjournal] INMEMORY folder created: ${INMEMORY}"
        echo "[tsmjournal] ONDISK folder created: ${ONDISK}"
        echo "[tsmjournal] Journal dumpped to disk: ${ONDISK}"
    else
        # Если ошибка и параметр "ui" не передан в командной строке
        if [ $size -gt 5 ] && [ -z $UI ]; then
            echo $ERR
        fi
        # Если ошибка и параметр "ui" передан в командной строке
        if [ $size -gt 5 ] && [ -n $UI ]; then
            echo "[ERROR] $ERR"
        fi
        # Если нет ошибки и парметр "ui" передан в командной строке
        if [ $size -lt 5 ] && [ -n $UI ]; then
            echo "[OK]"
        fi
    fi
}

load() {
    # Если нет директории для хранения на диске - создать
    # Если нет директории для хранения в памяти - создать
    ERR="$(mkdir -p ${INMEMORY} 2>&1)"
    ERR="$ERR $(mkdir -p ${ONDISK} 2>&1)"
    ERR=$ERR $(cp -rf ${ONDISK}/* ${INMEMORY} 2>&1)

    size=${#ERR}
    # Если нет ошибки и параметр "ui" не передан в командной строке
    if [ $size -lt 5 ] && [ -z $UI ]; then
        echo "[tsmjournal] INMEMORY folder created: ${INMEMORY}"
        echo "[tsmjournal] ONDISK folder created: ${ONDISK}"
        echo "[tsmjournal] Journal loaded to memory: ${INMEMORY}"
    else
        # Если ошибка и параметр "ui" не передан в командной строке
        if [ $size -gt 5 ] && [ -z $UI ]; then
            echo $ERR
        fi
        # Если ошибка и параметр "ui" передан в командной строке
        if [ $size -gt 5 ] && [ -n $UI ]; then
            echo "[ERROR] $ERR"
        fi
        # Если нет ошибки и парметр "ui" передан в командной строке
        if [ $size -lt 5 ] && [ -n $UI ]; then
            echo "[OK]"
        fi
    fi
}

clear() {
    # Если нет директории для хранения на диске - создать
    # Если нет директории для хранения в памяти - создать
    ERR="$(mkdir -p ${INMEMORY} 2>&1)"
    ERR="$ERR $(mkdir -p ${ONDISK} 2>&1)"
    ERR="$ERR $(rm -rf ${INMEMORY}/* 2>&1)"
    ERR="$ERR $(rm -rf ${ONDISK}/* 2>&1)"

    size=${#ERR}
    # Если нет ошибки и параметр "ui" не передан в командной строке
    if [ $size -lt 5 ] && [ -z $UI ]; then
        echo "[tsmjournal] Journal cleared on disk: ${ONDISK}"
        echo "[tsmjournal] Journal cleared in memory: ${INMEMORY}"
    else
        # Если ошибка и параметр "ui" не передан в командной строке
        if [ $size -gt 5 ] && [ -z $UI ]; then
            echo $ERR
        fi
        # Если ошибка и параметр "ui" передан в командной строке
        if [ $size -gt 5 ] && [ -n $UI ]; then
            echo "[ERROR] $ERR"
        fi
        # Если нет ошибки и парметр "ui" передан в командной строке
        if [ $size -lt 5 ] && [ -n $UI ]; then
            echo "[OK]"
        fi
    fi
}

debug() {
    tsmjournal stop
    uci set tsmjournal.debug.enable='1'
    uci commit

    sleep 1
    exec /usr/bin/lua /usr/lib/lua/tsmjournal/app.lua
    RETVAL=$?
}


doexit() {
    exit $RETVAL
}

[ -n "$INCLUDE_ONLY" ] && return

CMD="$1"
[ -z $CMD ] && {
    run
    doexit
}
shift
# See how we were called.
case "$CMD" in
    start|stop|restart|reload)
        callinit $CMD
        ;;
    debug)
        debug
        ;;
    load)
        load
        ;;
    dump)
        dump
        ;;
    clear)
        clear
        ;;
    *help|*?)
        usage $0
        ;;
    *)
        RETVAL=1
        usage $0
        ;;
esac

doexit() {
    exit $RETVAL
}

doexit