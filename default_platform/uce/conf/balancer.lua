local frame = require "ant.frame"
local request = require "ant.request"
local balancer = require "ant.balancer"

local function setUpstreamRR()

    local ok, upstream = frame.doPlugIn(request, "comm.uceBalancer")
    if not ok or not upstream then return ngx.exit(502) end

    local host, port, https = balancer.getUpstreamPeer(upstream)

    if not host or host =="" or not port or port == "" then
        return ngx.exit(502)
    end

    local tryTimes = 3

    balancer.set_more_tries(tryTimes)

    local ok, err = balancer.set_current_peer(host, port, https)
    if not ok then
        ngx.log(ngx.ERR, "failed to set the current peer: ", err)
        return ngx.exit(502)
    end

end

local function uceBalancer()

    local mse_ip, mse_port = request.getMse()
    if mse_ip == "" then
        mse_ip = nil
    end

    if ngx.req.get_method() == "PURGE" then
        if not mse_ip then
            return ngx.exit(200)
        end
    else
        local name, status = balancer.get_last_failure()
        if not mse_ip or ngx.var.http_x_triger_download == "true" or name then
            return setUpstreamRR()
        else
            balancer.set_more_tries(1)
        end
    end

    --  set default to mse
    local ok, err = balancer.set_current_peer(mse_ip, mse_port)
    if not ok then
        ngx.log(ngx.ERR, "failed to set the current peer: ", err)
        return ngx.exit(502)
    end
end

return uceBalancer()

