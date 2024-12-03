
local util = require "luci.util"
local ubus = require "ubus"
local uloop = require "uloop"
local sys  = require "luci.sys"
local uci = require "luci.model.uci".cursor()
local leveldb = require 'lualeveldb'
local json = require "cjson"

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


local tsmjournal = {}

tsmjournal.conn = ubus.connect()
if not tsmjournal.conn then
	error("Failed to connect to ubus from Tsmjournal!")
end

tsmjournal.pipeout_file = "/tmp/wspipeout.fifo"	    -- Gwsocket creates it
tsmjournal.pipein_file = "/tmp/wspipein.fifo"       -- Gwsocket creates it

local inmemory_db_path = uci:get("tsmjournal", "database", "inmemory")
local ondisk_db_path = uci:get("tsmjournal", "database", "ondisk")
tsmjournal.maxsize = tonumber(uci:get("tsmjournal", "database", "maxsize")) or 25

local opt = leveldb.options()
opt.createIfMissing = true
opt.errorIfExists = false


-- List all journal entries (opens and closes the database in the function)
function tsmjournal.list()
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

function tsmjournal.remove_oldest()
	local oldest_key
    local entries = tsmjournal:list()
   	local size = #entries

   	if (size - tsmjournal.maxsize) > 0 then
	   	while (size - tsmjournal.maxsize) > 0 do
	   		entries = tsmjournal:list()
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

function tsmjournal:make_ubus()
	local ubus_methods = {
		["tsmodem.journal"] = {
			send = {
				function(req, msg)
					local resp = {}
					print("----------")
					if_debug("send", "UBUS", "CALL", msg, "")
					tsmjournal.remove_oldest()

					local key = os.time() -- .. "_" .. (msg["ruleid"] or "undefined")
					local success, err = pcall(function()
						local db = leveldb.open(opt, inmemory_db_path)
			            db:put(key, json.encode(msg))
		            	leveldb.close(db)
			        end)

			        if not success then
			                resp["response"] = "[tsmjournal]: Error storing data in LevelDB: " .. err
			        else
			        	    resp["response"] = "[tsmjournal]: Storing data in LevelDB: [OK]"
			        end

			        --[[ Update Web UI, e.g. UIJournal.js.htm widget]]
			        local shell_command = string.format("echo '%s' > %s", util.serialize_json(msg), tsmjournal.pipein_file)
			        if_debug("exec", "SHELL", "", shell_command, "Gwsocket fifo")
   					sys.process.exec({"/bin/sh", "-c", shell_command }, true, true, false)

					tsmjournal.conn:reply(req, resp);
				end, {id = ubus.INT32, msg = ubus.STRING }
			},
		}
	}
	tsmjournal.conn:add( ubus_methods )

end

uloop.init()
tsmjournal:make_ubus()
uloop.run()
