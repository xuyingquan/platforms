local request = require "ant.request"

local function doUserAgent()
    if ngx.var.host == "vodpc-bj.wasu.cn" and ngx.var.http_user_agent ~= nil then
        valua = {"ziva", "Android", "Lavf", "iPad", "iPhone"}
        for i = 1, #valua do
            local s , e = string.find(ngx.var.http_user_agent, valua[i])
            if s ~= nil and e ~= nil then
                ngx.exit(403)
            end
        end
    else
        return true
    end
end

local function doAccess()
    -- init request, set var label, set session id
    request.initRequest()

    ngx.header["X-Request-Uri"] = ngx.var.request_uri

    -- set upstream to uce
    if ngx.req.get_method() == "PURGE" then
        request.getPurgeUpstream()
        return
    end

    -- do auth user agent
    doUserAgent()

    -- do redirect
    request.antRedirect()

    -- do auth request
    request.authRequest()

end

doAccess()

