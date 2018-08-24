local BaseAPI = require("orange.plugins.base_api")
local common_api = require("orange.plugins.common_api")
local orange_db = require("orange.store.orange_db")
local dao = require("orange.store.dao")
local utils = require("orange.utils.utils")
local json = require("orange.utils.json")

local api = BaseAPI:new("ssl-api", 2)
local common_api_table = common_api("ssl")

-- get useable api from common api 
local useable_api = {
	"/ssl/enable",
	"/ssl/sync"
}
local useable_api_table = {}
for _, path in pairs(useable_api) do
	useable_api_table[path] = common_api_table[path]
end
api:merge_apis(useable_api_table)

api:get("/ssl/fetch_config",function (store)
	return function (req, res, next)
		local data = {}
        local enables ,err = dao.get_enable("ssl" ,store)
        if enables and type(enables) == "table" and #enables > 0 then
            data["ssl.enable"] = (enables[1].value == "1")
        else
            data["ssl.enable"] = false
        end

        local certs, err = store:query({
            sql = "select * from `ssl` where `type` = ?",
            params = {"cert"}
        })

        if err then
            ngx.log(ngx.ERR, "error to find certs from storage when fetching data of plugin[ssl], err:", err)
            return false
        end

        local certs_table = {}
        if certs and type(certs) == "table" and #certs > 0 then
	        for _ , cert in pairs(certs) do
                value = json.decode(cert.value)
                value["key_pem"] = "the key is hiden"
                value["cert_pem"] = "the cert is hiden"
	        	certs_table[cert.key] = value
	        end
	    end
        data["ssl.certs"] = certs_table

		return res:json({
			success = true,
			data = data,
			msg = "succeed to fetch config from store"
		})
	end
end)

api:get("/ssl/config",function (store)
	return function (req, res, next)
		local data = {}
        local enable = orange_db.get("ssl.enable") or false
        data["enable"] = enable

        local certs = orange_db.get_json("ssl.certs")
        for name, cert in pairs(certs) do
            cert["key_pem"] = "the key is hiden"
            cert["cert_pem"] = "the cert is hiden"
        end
        data["certs"] = certs

		return res:json({
			success = true,
			data = data
			})
	end
end)

api:get("/ssl/certs",function (store)
	return function (req, res, next)
        local certs = orange_db.get_json("ssl.certs")
        for name, cert in pairs(certs) do
            cert["key_pem"] = "the key is hiden"
            cert["cert_pem"] = "the cert is hiden"
        end
    	return res:json({
    		success = true,
    		data = certs
    		})
    end
end)

api:delete("/ssl/certs",function (store)
	return function (req, res, next)
		local cert_name = req.body.cert_name
		if not cert_name or cert_name == "" then
            return res:json({
                success = false,
                msg = "cert_name can not be null"
            })
        end

		local cert = dao.get_record("ssl" ,store ,"cert" ,cert_name)
		if not cert or not cert.value then
            return res:json({
                success = false,
                msg = "cert not found when deleting it"
            })
        end

        local delete_cert_result = dao.delete_record("ssl" ,store ,"cert" ,cert_name)
        if delete_cert_result then
        	local update_local_certs_result = dao.update_local_records("ssl", store, "cert", "certs")
        	if not update_local_certs_result then
        			return res:json({
                    success = false,
                    msg = "error to local certs when deleting cert"
                })
        	end
	    else
	    	return res:json({
	        	success = false,
	            msg = "error to delete cert"            	
	        })
	    end
    	return res:json({
        	success = true,
            msg = "succeed to delete cert"
        })
	end
end)

api:put("/ssl/certs",function (store)
	return function (req, res, next)
		local cert = req.body.cert
		cert = json.decode(cert)

        if not cert then
            return res:json({
                    success = false,
                    msg = "cert is not a standard json"
                })
        end
        
		cert.time = utils.now()

        local update_cert_result = dao.update_record("ssl" ,store, "cert", cert)
        if update_cert_result then
        	local update_local_certs_result = dao.update_local_records("ssl", store, "cert", "certs")
            if not update_local_certs_result then
                return res:json({
                    success = false,
                    msg = "error to local certs when updating cert"
                })
            end
        else
            return res:json({
            	success = false,
                msg = "error to update cert"            	
            })
        end

        return res:json({
        	success = true,
            msg = "succeed to update cert"
        })
	end
end)

api:post("/ssl/certs",function (store)
	return function (req, res, next)
		local cert = req.body.cert
		cert = json.decode(cert)

        if not cert then
            return res:json({
                    success = false,
                    msg = "cert is not a standard json"
                })
        end

		cert.time = utils.now()

		local create_cert_result = dao.create_record("ssl" ,store, "cert", cert)
		if create_cert_result then
			local update_local_certs_result = dao.update_local_records("ssl", store, "cert", "certs")
            if not update_local_certs_result then
                return res:json({
                    success = false,
                    msg = "error to local certs when creating cert"
                })
            end
        else
            return res:json({
            	success = false,
                msg = "error to create cert"            	
            })
		end

        return res:json({
        	success = true,
            msg = "succeed to create cert"
        })
	end
end)

return api
