
local frame = require "ant.frame"
local hc = require "ant.healthcheck"

local http_req = "GET /check HTTP/1.1\r\nHost: admin.shatacdn.com\r\nConnection: close\r\nUser-Agent: " .. frame.env.label .. "-" .. frame.product .. "\r\n\r\n"

local _M = {

    name = "uceBalancer",

    subNames = {"primaryServers", "backupServers"},

    servers = {
        primaryServers = {},
        backupServers  = {},
    },

    configs = {
        primaryServers = {
            check    = "http",
            interval = 2000,       -- ms
            http_req = http_req,
        },

        backupServers = {
            check    = "http",
            interval = 10000,     --ms
            http_req = http_req,
        },
    },
}

local primaryServers = {}
local backupServers  = {}

local function getUpstream()
    if _M.servers.primaryServers == primaryServers then
        return
    end

    local upstreams = frame.env.upstreams

    local i = 1
    local j = 1

    for k = 1, #upstreams, 1 do
        if upstreams[k].backup and upstreams[k].backup == true then
            if not backupServers[j] or not next(backupServers[j]) then
                backupServers[j] = {}
            end
            backupServers[j].host   = upstreams[k].ip
            backupServers[j].port   = upstreams[k].port
            backupServers[j].weight = upstreams[k].weight
            backupServers[j].down   = upstreams[k].down
            backupServers[j].https  = upstreams[k].https or false

            backupServers[j].maxFails = upstreams[k].max_fails or 5
            j = j + 1
        else
            if not primaryServers[i] or not next(primaryServers[i]) then
                primaryServers[i] = {}
            end
            primaryServers[i].host   = upstreams[k].ip
            primaryServers[i].port   = upstreams[k].port
            primaryServers[i].weight = upstreams[k].weight
            primaryServers[i].down   = upstreams[k].down
            primaryServers[i].https  = upstreams[k].https or false

            primaryServers[i].maxFails = upstreams[k].max_fails or 5
            i = i + 1
        end
    end

    _M.servers.primaryServers = primaryServers
    if i > 1 and primaryServers[1].https == true then
        _M.configs.primaryServers["check"] = "https"
    end

    _M.servers.backupServers  = backupServers
    if j > 1 and backupServers[1].https == true then
        _M.configs.backupServers["check"] = "https"
    end
end

function _M.run()

    getUpstream()

    if _M.servers == nil or next(_M.servers) == nil then
        return _M
    end

    for i = 1, #_M.subNames, 1 do
        local subName = _M.subNames[i]
        hc.set_check_upstream(_M.name, subName, _M.servers[subName], _M.configs[subName])
    end

    return _M
end

return _M
