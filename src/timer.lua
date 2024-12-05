local uci = require "luci.model.uci".cursor()
local util = require "luci.util"
local uloop = require "uloop"
local sys  = require "luci.sys"

require "tsmjournal.util"


local timer = {}
timer.journal = nil
timer.dump = nil
timer.load = nil
timer.clear = nil

local dump_interval = tonumber((uci:get("tsmjournal", "interval", "dump")) or (24*60*60*1000)) -- interval by default in minutes
dump_interval = dump_interval * 60 * 1000

local load_delay = 1000 		-- Delay before load journal DB from flash to memory
								-- That's mean journal db will be loaded to memory in 1 sec after Tsmjournal service started

local clear_delay = 600 		-- Delay before clearing the Journal db from flash & memory

timer.interval = {
    dump = dump_interval,		-- Every "dump" interval the db is saved to the /etc/tsmjournal/journal.db/
    load = load_delay,			-- It's not an interval, but delay (see cpmment above)
    clear = clear_delay
}

function timer:init(journal)
	timer.journal = journal
	
	if_debug("timer", "INIT", "Interval", timer.interval.dump, "")

	-- Load journal from flash to memory
	timer.load:set(timer.interval.load)

	-- Run dumping process
	timer.dump:set(timer.interval.dump)
end

--[[ Dump journal db to flash ]]
function t_dump()
	timer.journal.state.is_dumping = true
	local ret = sys.exec("/usr/sbin/tsmjournal dump ui")
	local msg = {
		["journal"] = {
			["datetime"] = tostring(os.date("%Y-%m-%d %H:%M:%S", tonumber(os.date()))),
			["name"] = "Журнал событий сохранён на flash-память",
			["command"] = "tsmjournal dump",
			["source"] = "Journal (module)",
			["response"] = ret
		},
		["ruleid"] = "98_rule"
	}
    if_debug("websocket", "SEND", "", msg, "Send to UI journal")
	timer.journal:websocket_send(msg)

    timer.dump:set(timer.interval.dump)
    timer.journal.state.is_dumping = false
end
timer.dump = uloop.timer(t_dump)

--[[ Load journal db to memory ]]
function t_load()
	timer.journal.state.is_loading = true
	local ret = sys.exec("/usr/sbin/tsmjournal load ui")
	local msg = {
		["journal"] = {
			["datetime"] = tostring(os.date("%Y-%m-%d %H:%M:%S", tonumber(os.date()))),
			["name"] = "Журнал событий восстановлен после перезапуска",
			["command"] = "tsmjournal load",
			["source"] = "Journal (module)",
			["response"] = ret
		},
		["ruleid"] = "98_rule"
	}
    if_debug("websocket", "SEND", "", msg, "Send to UI journal")
	timer.journal:websocket_send(msg)
	timer.journal.state.is_loading = false
end
timer.load = uloop.timer(t_load)


--[[ Clear journal db from flash & memory ]]
function t_clear()
	timer.journal.state.is_clearing = true
	local ret = sys.exec("/usr/sbin/tsmjournal clear ui")
	local msg = {
		["journal"] = {
			["datetime"] = tostring(os.date("%Y-%m-%d %H:%M:%S", tonumber(os.date()))),
			["name"] = "Журнал событий очищен",
			["command"] = "tsmjournal clear",
			["source"] = "Journal (module)",
			["response"] = ret
		},
		["ruleid"] = "98_rule"
	}
    if_debug("websocket", "SEND", "", msg, "Send to UI journal")
	timer.journal:websocket_send(msg)
	timer.journal.state.is_clearing = false
end
timer.clear = uloop.timer(t_clear)


return timer
