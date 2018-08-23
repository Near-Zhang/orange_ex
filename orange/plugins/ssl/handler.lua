
local BasePlugin = require("orange.plugins.base_handler")
local orange_db = require("orange.store.orange_db")
local ssl = require("ngx.ssl")


function cert_config(h, v)
	if v.log == true then
		ngx.log(ngx.INFO, "[SSL][Match-Cert-Host] cert_host:",h)
	end

	local cert_pem = v.cert_pem
	local cert_der, err = ssl.parse_pem_cert(cert_pem)
	if not cert_der then
		ngx.log(ngx.ERR, "[SSL][Error-Parse-Cert] cert_host:",h)
		return
	end

	local ok, err = ssl.set_cert(cert_der)
	if not ok then
		ngx.log(ngx.ERR, "[SSL][Error-Set-Cert] cert_host:",h)
		return 
	end

	local key_pem = v.key_pem
	local key_der, err = ssl.parse_pem_priv_key(key_pem)
	if not key_der then
		ngx.log(ngx.ERR, "[SSL][Error-Parse-Key] cert_host:",h)
		return
	end

	local ok, err = ssl.set_priv_key(key_der)
	if not ok then
		ngx.log(ngx.ERR, "[SSL][Error-Set-Key] cert_host:",h)
		return
	end

	if v.log == true then
		ngx.log(ngx.INFO, "[SSL][Success-SSL-Config] cert_host:",h)
	end

	return true
end


local SSLHandler = BasePlugin:extend()
SSLHandler.PRIORITY = 2000

function SSLHandler:new(store)
    SSLHandler.super.new(self, "SSL-plugin")
    self.store = store
end

function SSLHandler:certify()
	SSLHandler.super.certify(self)

	local enable = orange_db.get("ssl.enable")
    local certs = orange_db.get_json("ssl.certs")
    
    if not enable or enable ~= true or not certs then
        return
    end

    local sni_host,err = ssl.server_name()

    for h, v in pairs(certs) do
    	if h ~= "default" then
    		if sni_host then
	    		local ok ,err = ngx.re.match(sni_host,h)

		    	if ok then
		    		cert_config(h, v)
		    		return
		    	else
					if v.log == true then
						ngx.log(ngx.INFO, "[SSL][Not-Match-Cert-Host] cert_host:",h)
					end
		    	end
		    else
		    	if v.log == true then
						ngx.log(ngx.INFO, "[SSL][No-SNI-Host] using default cert")
				end
				break
			end
	    end
    end

    cert_config("default", certs["default"])

end

return SSLHandler
