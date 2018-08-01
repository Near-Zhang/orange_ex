local stat = require("orange.plugins.stat.stat")

local API = {}

API["/stat/status"] = {
    GET = function(store)
	    return function(req, res, next)
		    local stat_result = stat.stat()

		    local result = {
		        success = true,
		        data = stat_result
		    }

		    res:json(result)
		end
	end
}

API["/stat/clear"] = {
	POST = function (store)
		return function (req, res, next)
			local clear_result = pcall(stat.clear)
			local result = {
					success = true,
		        	data = "seccess to clear status"	        
				}
			if not clear_result then
				result = {
					success = false,
		        	data = "failed to clear status"	        
				}
			end

			res:json(result)
		end
	end
}


return API