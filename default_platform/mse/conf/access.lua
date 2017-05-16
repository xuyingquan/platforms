
local header = {
    "http_x_channel",
    "http_x_session_id",
    "http_x_cache_key",
    "http_x_cache_division",
    "http_x_forwarded_cache",
}

local function headerCheck()

    -- skip for cache off
    if ngx.var.http_x_proxy_cache == "off" then
        ngx.exit(502)
    end

    for i = 1, #header, 1 do
        if not ngx.var[header[i]] or ngx.var[header[i]] == "" then
            ngx.log(ngx.ERR, "Illegal Request.")
            ngx.exit(502)
        end
    end
end

headerCheck()
