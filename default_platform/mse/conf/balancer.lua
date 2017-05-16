local frame = require "ant.frame"
local balancer = require "ngx.balancer"
local add_timer = ngx.timer.at

function mseTrigerDownload(premature, uri, headers, addr, port)
    local reqline = "GET " .. uri .. " HTTP/1.1\r\n"

    headers["X-Triger-Download"] = "true"
    headers["Connection"] = "close"
    headers["X-Session-Id"] = headers["X-Session-Id"] .. ".mse"

    for k, v in pairs(headers) do
        if type(v) == "table" then
            v = v[1]
        end
        reqline = reqline .. k .. ": " .. v .. "\r\n"
    end
    reqline = reqline .. "\r\n"

    local sock, err = ngx.socket.tcp()
    if not sock then
        ngx.log(ngx.ERR, "MSE triger download socket error")
        return false
    end

    sock:settimeout(20000)
    ok, err = sock:connect(addr, port)
    if not ok then
        sock:close()
        ngx.log(ngx.ERR, "MSE triger download connect error !!")
        return false
    end

    local bytes, err = sock:send(reqline)
    if not bytes then
        sock:close()
        ngx.log(ngx.ERR, "MSE triger download send error !!")
        return false
    end

    while (true) do
        local data, err = sock:receive(8192)
        if not data then
            break
        end
    end

    sock:close()
    return true;
end

function addTrigerList()
   if not ngx.var.http_x_cache_key then
       return
    end

    local dict = ngx.shared.trigerdownload
    local key = ngx.encode_base64(ngx.md5_bin(ngx.var.http_x_cache_key .. (ngx.var.http_range or "")))

    if not dict:add(key, 1, 5) then
        return
    end

    add_timer(2, mseTrigerDownload, ngx.var.request_uri, ngx.req.get_headers(0, true), ngx.var.server_addr, ngx.var.server_port)
end

function mseBalancer()
    if ngx.var.http_x_triger_download ~= "true" then
        -- add timer for triger download
        addTrigerList()
        return ngx.exit(502)
    end

    local saddr, sport = string.match(ngx.req.get_headers()["X-Forwarded-Cache"] or "", "(%d+%.%d+%.%d+%.%d+):(%d+)%)$")
    if not saddr or not sport then
        return ngx.exit(502)
    end

    local ok, err = balancer.set_current_peer(saddr, sport)
    if not ok then
        ngx.log(ngx.ERR, "failed to set the current peer: ", err)
        return ngx.exit(502)
    end
end

return mseBalancer()

