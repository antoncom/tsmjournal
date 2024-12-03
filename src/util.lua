local uci = require "luci.model.uci".cursor()
local util = require "luci.util"

function if_debug(ubus_method, protocol, request_or_response, value, comment)
	local is_debug = (uci:get("tsmjournal", "debug", "enable") == "1") and true
	local val = ""

	if (is_debug) then
		if (value and type(value) == "table") then
			val = util.serialize_json(value)
		elseif (value and type(value) == "string") then
			val = value:gsub("%c", " ")
		else
			val = tostring(value)
		end
		print(protocol .. ":" .. ubus_method, request_or_response,"", val,"","", comment)
	end
end