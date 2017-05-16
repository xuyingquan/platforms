local request = require "ant.request"

local function requestFilter()
    return true
end

local function precise()
    if ngx.var.host ~= ngx.var.server_addr then
        return false
    end

    local host, uri = string.match(ngx.var.uri, "/([^/]+)(.*)")
    if not host or host == "" then
        return false
    end

    if uri == "" then
        uri = "/"
    end

    ngx.var.host = host
    ngx.req.set_uri(uri)
    ngx.req.set_header("X-Redirect-Twice", "yes")

    return true
end

local function httpsFilter()
    if ngx.var.scheme ~= "https" then
        return
    end

    if ngx.var.host ~= "xpic-st-test.vimage1.com" then
        ngx.exit(403)
    end
end

local function doAccess()
    local rules = {
        {
            request = "Host",
            key = {"ottvideost.hifuntv.com","pcvideost.titan.imgo.tv","pcdownst.titan.imgo.tv","pcvideost.titan.mgtv.com","pcdownst.titan.mgtv.com",
                   "ottvideoyd.hifuntv.com","pcvideoyd.titan.imgo.tv","pcdownyd.titan.imgo.tv","pcvideoyd.titan.mgtv.com","pcdownyd.titan.mgtv.com"},
            value = "mgtv_backend"
        },
    }

    httpsFilter()

    --  do precise
    precise()

    -- init request, set var label, set session id
    request.initRequest()

    -- do pre auth request
    requestFilter()

    -- do waf
    -- request.runWaf()

    -- do select upstream
    request.selectUpstream(rules)
end

doAccess()
