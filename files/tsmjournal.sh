#!/bin/sh

INITFILE=/etc/init.d/tsmjournal
SERVICE_PID_FILE=/var/run/tsmjournal.pid

APP=$0
CMD=$1
usage() {
    echo "Usage: $APP [ COMMAND ]"
    echo
    echo "Commands are:"
    echo "    start/stop/enable/disable - as usual"
    echo "    load      Load journal from disk to memory"
    echo "    drop      Drop journal from memory to disk"
    echo "    clear     Clear both: memory & disk"
    echo "    help      Show this and exit"
    echo
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

drop() {
	# Если нет директории для хранения на диске - создать
	# Если нет директории для хранения в памяти - создать

	# Записать в cron-файл настройки из UCI tsmjournal
	# Перезапустить cron с новыми настойками

	INMEMORY=$(uci get tsmjournal.database.inmemory)
	ONDISK=$(uci get tsmjournal.database.ondisk)

	SCHED=$(uci get tsmjournal.droptodisk.crontab)
	JOB="cp -rf ${INMEMORY} ${ONDISK}"

	CRON="${SCHED} ${JOB}"

	mkdir -p ${INMEMORY}
	mkdir -p ${ONDISK}

	echo "[tsmjournal] INMEMORY folder created: ${INMEMORY}"
	echo "[tsmjournal] ONDISK folder created: ${ONDISK}"

	# cp -rf ${INMEMORY} ${ONDISK}
	cp -rf /var/spool/tsmjournal/journal.db/* /etc/tsmjournal/journal.db/
	echo "[tsmjournal] Journal dropped to disk: ${ONDISK}"

	echo "$CRON" > /etc/crontabs/root
	/etc/init.d/cron restart &> /dev/null
	echo "[tsmjournal] Journal crontabbed like this: ${CRON}" 
}

load() {
	# Если нет директории для хранения на диске - создать
	# Если нет директории для хранения в памяти - создать

	# При запуске сервиса tsmodem скопировать содержимое диска в память

	INMEMORY=$(uci get tsmjournal.database.inmemory)
	ONDISK=$(uci get tsmjournal.database.ondisk)
	JOB="cp -rf ${ONDISK} ${INMEMORY}"

	mkdir -p ${INMEMORY}
	mkdir -p ${ONDISK}

	echo "[tsmjournal] INMEMORY folder created: ${INMEMORY}"
	echo "[tsmjournal] ONDISK folder created: ${ONDISK}"

	cp -rf /etc/tsmjournal/journal.db/* /var/spool/tsmjournal/journal.db/
	echo "[tsmjournal] Journal loaded to memory: ${INMEMORY}"

	echo "$CRON" > /etc/crontabs/root
	/etc/init.d/cron restart &> /dev/null
	echo "[tsmjournal] Journal crontabbed like this: ${CRON}" 
}

clear() {
	INMEMORY=$(uci get tsmjournal.database.inmemory)
	ONDISK=$(uci get tsmjournal.database.ondisk)
	JOB1="rm -rf ${ONDISK}"
	JOB1="rm -rf ${INMEMORY}"

	mkdir -p ${INMEMORY}
	mkdir -p ${ONDISK}

	rm -rf ${ONDISK}
	echo "[tsmjournal] Journal cleared on disk: ${ONDISK}"

	rm -rf ${INMEMORY}
	echo "[tsmjournal] Journal cleared in memory: ${INMEMORY}"
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
    drop)
        drop
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