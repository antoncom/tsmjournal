
local util = require "luci.util"
local ubus = require "ubus"
local uloop = require "uloop"
local sys  = require "luci.sys"
local uci = require "luci.model.uci".cursor()
local leveldb = require 'lualeveldb'
local json = require "cjson"

local timer = require "tsmjournal.timer"

require "tsmjournal.util"

local signal = require("posix.signal")
signal.signal(signal.SIGINT, function(signum)
  io.write("\n")
  print("-----------------------")
  print("Tsmjournal stopped.")
  print("-----------------------")
  io.write("\n")
  os.exit(128 + signum)
end)

local journal = {}
journal.state = {
	is_dumping = false,
	is_loading = false,
	is_clearing = false
}

journal.conn = ubus.connect()
if not journal.conn then
	error("Failed to connect to ubus from Tsmjournal!")
end

journal.pipeout_file = "/tmp/wspipeout.fifo"	    -- Gwsocket creates it
journal.pipein_file = "/tmp/wspipein.fifo"       -- Gwsocket creates it

local inmemory_db_path = uci:get("tsmjournal", "database", "inmemory")
local ondisk_db_path = uci:get("tsmjournal", "database", "ondisk")
journal.maxsize = tonumber((uci:get("tsmjournal", "database", "maxsize") or 25))

-- Load journal from flashdisk to memory
os.execute("/usr/sbin/tsmjournal load")

local opt = leveldb.options()
opt.createIfMissing = true
opt.errorIfExists = false

function journal:init(tmr_module)
	journal.timer = tmr_module
end

-- List all journal entries (opens and closes the database in the function)
function journal.list()
	local entries = {}
   	local db = leveldb.open(opt, inmemory_db_path)
    local iter = db:iterator()
    iter:seekToFirst()
   
    while iter:valid() do
        local key = iter:key()
        table.insert(entries, key)
        iter:next()
    end
    iter:del() -- Clean up iterator
   	leveldb.close(db)

    table.sort(entries, function(a, b)
    	return a < b
    end)

    return entries
end

function journal.remove_oldest()
	local oldest_key
    local entries = journal:list()
   	local size = #entries

   	if (size - journal.maxsize) > 0 then
	   	while (size - journal.maxsize) > 0 do
	   		entries = journal:list()
	   		size = #entries
		    oldest_key = entries[1]
		    if oldest_key then
		    	local db = leveldb.open(opt, inmemory_db_path)
		    	db:delete(oldest_key)
		    	leveldb.close(db)
		    end
		end
	end
end

--[[ Update Web UI, e.g. UIJournal.js.htm widget]]
function journal:websocket_send(msg)
    local shell_command = string.format("echo '%s' > %s", util.serialize_json(msg), journal.pipein_file)
    if_debug("exec", "SHELL", "", shell_command, "Gwsocket fifo")
	sys.process.exec({"/bin/sh", "-c", shell_command }, true, true, false)

end

function journal:make_ubus()
	local ubus_methods = {
		["tsmodem.journal"] = {
			send = {
				function(req, msg)
					local resp = {}
					if_debug("send", "UBUS", "CALL", msg, "")

					if not (journal.state.is_dumping or journal.state.is_loading or journal.state.is_clearing) then
						journal.remove_oldest()

						local key = os.time() -- .. "_" .. (msg["ruleid"] or "undefined")
						local success, err = pcall(function()
							local db = leveldb.open(opt, inmemory_db_path)
				            db:put(key, json.encode(msg))
			            	leveldb.close(db)
				        end)

				        if not success then
				                resp["response"] = "[journal]: Error storing data in LevelDB: " .. err
				        else
				        	    resp["response"] = "[journal]: Storing data in LevelDB: [OK]"
				        end

				        journal:websocket_send(msg)
				        
						journal.conn:reply(req, resp);
					else
						journal.conn:reply(req, {["response"] = "[journal]: Aborted due to dumping, or loading, or clearing right now."});
					end
				end, {id = ubus.INT32, msg = ubus.STRING }
			},
			clear = {
            function(req, msg)
				if_debug("send", "UBUS", "CALL", journal.timer, "Clear method is called.")
             
                journal.timer.clear:set(journal.timer.interval.clear)


                resp = {
                	["response"] = "[journal]: Clearing journal is in progress."
                }

                journal.conn:reply(req, resp);

            end, {id = ubus.INT32, msg = ubus.STRING }
        },
		}
	}
	journal.conn:add( ubus_methods )

end

-- Link sub-modules
journal:init(timer)
timer:init(journal)

uloop.init()
journal:make_ubus()
uloop.run()
