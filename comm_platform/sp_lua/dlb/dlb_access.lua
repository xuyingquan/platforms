local request = require "ant.request"

local function doAccess()
    -- init request, set var label, set session id
    request.initRequest()

    if request.isFirstNode() then
        ngx.req.set_header("Wheel-Real-Ip", ngx.var.http_x_remote_addr or ngx.var.remote_addr)
    end

    ngx.header["X-Request-Uri"] = ngx.var.request_uri

    -- set upstream to uce
    if ngx.req.get_method() == "PURGE" then
        request.getPurgeUpstream()
        return
    end

    -- do redirect
    request.antRedirect()

end

doAccess()
