local io = require("io")
local lfs = require("lfs")
local cjson = require "cjson.safe"
local restyMd5 = require "resty.md5"
local restyString = require "resty.string"
local redis = require "resty.redis"

local version = "ContEx 5.2.0"

local _M = {}

local new_timer = ngx.timer.at
local updateConfigRate = 5

local function loadEnvJson (envJson)
    local file = io.open(envJson, "r")
    if not file then
        ngx.log(ngx.CRIT, "Open " .. envJson .." faild !!")
        return nil
    end

    local jsonText = file:read("*a")
    file:close()
    if not jsonText then
        ngx.log(ngx.CRIT, "Read " .. envJson .." faild !!")
        return nil
    end

    return cjson.decode(jsonText)
end

local function loadEnvListen (path)
    local file = io.open(path, "r")
    if not file then
        return {}
    end

    local listen = {}
    for line in file:lines() do
        addr = string.match(line, "listen%s+(%S+).-;")
        if addr then
            if string.match(addr, "%d+") == addr then
                addr = "127.0.0.1:" .. addr
            end
            table.insert(listen, addr)
        end
    end

    file:close()
    return listen
end

local function parseHealthChackConfig(conf, hcu)
    local type = string.match(conf, "type=(%S+)")
    if type then hcu.type = type end

    local shm = string.match(conf, "shm=(%S+)")
    if shm then hcu.shm = shm end

    local check = string.match(conf, "check=(%S+)")
    if check then hcu.check = check end

    local interval = string.match(conf, "interval=(%d+)")
    if interval then hcu.interval = tonumber(interval) end

    local timeout = string.match(conf, "timeout=(%d+)")
    if timeout then hcu.timeout = tonumber(timeout) end

    local fall = string.match(conf, "fall=(%d+)")
    if fall then hcu.fall = tonumber(fall) end

    local rise = string.match(conf, "rise=(%d+)")
    if rise then hcu.rise = tonumber(rise) end

    local concurrency = string.match(conf, "concurrency=(%d+)")
    if concurrency then hcu.concurrency = tonumber(concurrency) end
end

local function loadUpstreams (filename)
    if not _M.upstreams then _M.upstreams = {} end
    local file = io.open(filename, "r")
    if not file then
        return false
    end

    local hcDefault = {
        check       = "on",
        shm         = "healthcheck",
        interval    = 3000,
        timeout     = 1000,
        fall        = 3,
        rise        = 2,
        concurrency = 10,
        type        = "http",
    }

    local inupstream = false
    local hcLocal = {}

    -- locad upstream name
    for line in file:lines() do
        if string.match(line, "^%s-#") then
            local conf = string.match(line, "^%s-#!%s-(.+)%s-")
            if conf then
                if inupstream then
                    parseHealthChackConfig(conf, hcLocal)
                else
                    parseHealthChackConfig(conf, hcDefault)
                end
            end
        else
            local uname = string.match(line, "%s-upstream%s+(.+)%s+{")
            if uname then
                hcLocal.name = uname
                inupstream = true
            else
                local uend = string.match(line, "}")
                if uend then
                    table.insert(_M.upstreams, {
                        name        = hcLocal.name,
                        check       = hcLocal.check or hcDefault.check,
                        shm         = hcLocal.shm or hcDefault.shm,
                        interval    = hcLocal.interval or hcDefault.interval,
                        timeout     = hcLocal.timeout or hcDefault.timeout,
                        fall        = hcLocal.fall or hcDefault.fall,
                        rise        = hcLocal.rise or hcDefault.rise,
                        concurrency = hcLocal.concurrency or hcDefault.concurrency,
                        type        = hcLocal.type or hcDefault.type,
                    })
                    inupstream = false
                    hcLocal = {}
                end
            end
        end
    end

    file:close()
    return true
end

function _M.initFrame()
    local prefix, product = string.match(ngx.config.prefix(), "(.+)/+(.+)")
    if not (prefix and product) then
        ngx.log(ngx.CRIT, "Parse " .. ngx.config.prefix() .." faild !!")
        return false
    end
    local envJson = prefix .. "/env/env.json"

    -- drop end of '/'
    local len = string.find(product, "/+")
    if len then
       product = string.sub(product, 0, len - 1)
    end

    _M.version = version
    _M.product = string.upper(product)
    _M.envJson = envJson

    _M.plugin = {}

    _M.prefix = prefix

    -- load platm
    _M.env = loadEnvJson(envJson)
    if not _M.env then
        ngx.log(ngx.CRIT, "Load " .. envJson .." faild !!")
        return false
    end

    -- init listen config
    _M.listen = {}

    -- load product listen
    _M.listen.lbf = loadEnvListen(prefix .. "/../default_platform/env/lbf.listen")
    _M.listen.uce = loadEnvListen(prefix .. "/../default_platform/env/uce.listen")

    _M.listen.hsm = loadEnvListen(prefix .. "/env/hsm.listen")
    _M.listen.pg = loadEnvListen(prefix .. "/../default_platform/env/pg.listen")

    -- load upstreams
    loadUpstreams(prefix .. "/env/" .. string.lower(product) .. "_upstreams.conf")
    return true
end

function _M.getLabel()
    if _M.env == nil or _M.env.label == nil then
        return "label-unset"
    end

    return _M.env.label .. "-" .. _M.product
end

function _M.getNode()
    if _M.env == nil or _M.env.node == nil then
        return "node-unset"
    end

    return _M.env.node
end

function _M.getSessionID()

    local md5 = restyMd5:new()
    if not md5 then
        ngx.log(ngx.ERR, "failed to create md5 object")
        return nil
    end

    local ok = md5:update(_M.env.label)
    if not ok then
        ngx.log(ngx.ERR, "failed to update")
        return nil
    end

    ok = md5:update(tostring(math.random()))
    if not ok then
        ngx.log(ngx.ERR, "failed to update")
        return nil
    end

    ok = md5:update(tostring(ngx.worker.pid()))
    if not ok then
        ngx.log(ngx.ERR, "failed to update")
        return nil
    end

    ok = md5:update(ngx.var.connection)
    if not ok then
        ngx.log(ngx.ERR, "failed to update")
        return nil
    end

    local digest = md5:final()
    return restyString.to_hex(digest)
end

local function initHealthCheck()
    local hc = require "resty.upstream.healthcheck"

    for i = 1, #_M.upstreams do
        local u = _M.upstreams[i]
        if u.check == "on" then
            local ok, err = hc.spawn_checker {
                shm = u.shm, -- defined by "lua_shared_dict"
                upstream = u.name, -- defined by "upstream"
                type = u.type,
                http_req = "GET /check HTTP/1.1\r\nHost: admin.shatacdn.com\r\nConnection: close\r\nUser-Agent: " .. _M.env.label .. "-" .. _M.product .. "\r\n\r\n",
                -- raw HTTP request for checking
                interval = u.interval,  -- run the check cycle every 2 sec
                timeout = u.timeout,  -- 1 sec is the timeout for network operations
                fall = u.fall,-- # of successive failures before turning a peer down
                rise = u.rise,-- # of successive successes before turning a peer up
                valid_statuses = {200,},  -- a list valid HTTP status code
                concurrency = u.concurrency,  -- concurrency level for test requests
            }

            if not ok then
                ngx.log(ngx.ERR, "upstream ", u.name, " ", err)
                return
            end
        end
    end
end

local function backConfig(valueTable, filename)
    local pathName = ngx.config.prefix() .. "/conf/" .. filename

    local file, err = io.open(pathName, "w+")
    if not file then ngx.log(ngx.ERR, err) return false end

    local value = ""
    if valueTable ~= ngx.null then
        value = cjson.encode(valueTable)
    end

    file:write(value)

    file:close()
end

local function getBakConfig(filename)
    local pathName = ngx.config.prefix() .. "/conf/" .. filename

    local file, err = io.open(pathName, "r")
    if not file then ngx.log(ngx.ERR, err) return nil end

    local value = file:read("*a")
    file:close()

    local valueTable = cjson.decode(value)

    return valueTable
end

----------------------------------------------------------------------
--                                                                  --
-- function name : getFromRedis                                     --
-- return value  :                                                  --
--                  0 : success get config from redis.              --
--                 -1 : failed, connect or auth failed.             --
--                 -2 : failed, nothing has changed in redis.       --
--                 -3 : failed, get failed from redis.              --
--                                                                  --
----------------------------------------------------------------------
local function getFromRedis()
    local red = redis:new()
    red:set_timeout(3000)

    local ok, err = red:connect(_M.env.redis.ip, _M.env.redis.port)
    if not ok then
        ngx.log(ngx.CRIT, "redis failed to connect : ", err)
        red:close()
        return -1, nil, nil
    end

    if _M.env.redis.auth then
        local ok, err = red:auth(_M.env.redis.auth)
        if not ok then
            ngx.log(ngx.CRIT, "redis failed to authenticate : ", err)
            red:close()
            return -1, nil, nil
        end
    end

    local dict = ngx.shared.platconfig

    local v1 = red:get("version")
    local v2 = dict:get("version")
    if v2 ~= nil and v2 ~= "" and v1 == v2 then red:close() return -2, nil, nil end

    dict:set("version", v1)

    local hosts, err = red:hgetall("hosts")
    if not hosts then
        ngx.log(ngx.CRIT, " get from redis failed : ", err)
        red:close()
        return -3, nil, nil
    end

    local platforms, err = red:hgetall("platforms")
    if not platforms then
        ngx.log(ngx.CRIT, " get from redis failed : ", err)
        red:close()
        return -3, nil, nil
    end

    red:close()

    return 0, hosts, platforms

end

local function updateConfig()

    local dict = ngx.shared.platconfig

    local hostsBakFileName     = "hosts.json"
    local platformsBakFileName = "platforms.json"

    local status, hosts, platforms = getFromRedis()

    if status == -1 then
        local v2 = dict:get("version")
        if v2 == nil or v2 == "" then
            hosts = getBakConfig(hostsBakFileName)
            platforms = getBakConfig(platformsBakFileName)
            dict:set("version", true)
        end
    elseif status == -2  then
        return true
    elseif status == -3 then
        return false
    end

    if hosts == nil or hosts == "" or platforms == nil or platforms == "" then
        return false
    end

    -- delete config from shared dict
    local hostsBak = getBakConfig(hostsBakFileName)
    local flag
    if hostsBak ~= nil and hostsBak ~= "" then
        for i = 1, #hostsBak, 2 do
            flag = 0
            if hosts ~= ngx.null then
                for j = 1, #hosts, 2 do
                    if hostsBak[i] == hosts[j] then flag = 1 break end
                end
            end
            if flag == 0 then dict:delete(hostsBak[i]) end
        end
    end

    -- backup config to file
    backConfig(hosts, hostsBakFileName)
    backConfig(platforms, platformsBakFileName)

    if hosts == ngx.null or platforms == ngx.null then
        return true
    end

    -- update shared dict config from redis
    for i = 1, #hosts, 2 do
        for j = 1, #platforms, 2 do
            if hosts[i+1] == platforms[j] then
                local ok, err = dict:set(hosts[i], platforms[j+1])
                if not ok then ngx.log(ngx.CRIT, err) end
            end
        end
    end

end

local function get_lock(dict)

    -- choose a worker process to update config
    local key = "worker"
    local ok, err = dict:add(key, true, updateConfigRate - 0.001)

    if not ok then
        if err == "exists" then
            return nil
        end
        ngx.log(ngx.ERR, "dict failed to add key \"", key, "\" : ", err)
        return nil
    end
    return true

end

local function updateConfigHandle()

    local dict = ngx.shared.platconfig

    if not get_lock(dict) then
        new_timer(updateConfigRate, updateConfigHandle)
        return true
    end

    updateConfig()

    new_timer(updateConfigRate, updateConfigHandle)

end

function _M.getConfig(key)

    if not key then
        ngx.log(ngx.ERR, "wrong parameter, key : ", key)
        return nil
    end

    local dict = ngx.shared.platconfig
    local configString, err = dict:get(key)
    if configString == nil or configString == "" then
        return nil
    end

    local config = cjson.decode(configString)
    local location = nil
    for i=1, #(config.location) do
        if string.match(ngx.var.uri, config.location[i].key) then
            if location == nil or config.location[i].nice > location.nice then
                location = config.location[i]
            end
        end
    end

    if location ~= nil then
        config.location = location
        return config
    else
        return nil
    end
end

local function getPluFileTime(plname)

    local fileName = string.gsub(plname, "%.", "/")
    fileName = _M.prefix .. "/lualib/" .. fileName .. ".lua"

    local attr = lfs.attributes(fileName)

    if attr then
        return attr.modification
    end

    return nil

end

local function safeRequire(plname)

    local ok, plugin = pcall(require, plname)
    if not ok then
        ngx.log(ngx.CRIT, plugin)
        return nil
    end

    return plugin

end

local function pluginRequire(plname)

    local loaded      = "loaded"
    local requireTime = "requireTime"
    local fileTime    = "fileTime"

    local frequency   = 5

    local timeNow = ngx.time()

    if not _M.plugin[plname] then
        _M.plugin[plname]                = {}

        _M.plugin[plname][requireTime]   = timeNow
        _M.plugin[plname][fileTime]      = getPluFileTime(plname)
        _M.plugin[plname][loaded]        = safeRequire(plname)

    elseif _M.plugin[plname][requireTime] + frequency <= timeNow then

        local fileLastTime = getPluFileTime(plname)

        if _M.plugin[plname][fileTime] and fileLastTime and fileLastTime > _M.plugin[plname][fileTime] then
            package.loaded[plname] = nil

            _M.plugin[plname][loaded]        = safeRequire(plname)
            _M.plugin[plname][fileTime]      = fileLastTime
        end

        _M.plugin[plname][requireTime]   = timeNow
    end

    return _M.plugin[plname][loaded]

end

function _M.doPlugIn(request, plname)
    if plname == nil or plname == "" then
        return false
    end

    local plugin = pluginRequire("plugin." .. plname)
    if not plugin then return false end

    local ok, ret = pcall(plugin.run, request)
    if not ok then
        ngx.log(ngx.CRIT, ret)
        return false
    end

    return true, ret
end

local function initHealthCheckTwo()
    local hc = require "ant.healthcheck"
    local ok, err = hc.init(1)
    if not ok then
        ngx.log(ngx.ERR, "healthCheck init is failed :" .. err)
    end

    -- set default plugin upstreams
    _M.doPlugIn(request, "comm.uceBalancer")
end

function _M.initWorker()
    --[[
    -- update shared dict config from redis in hsm
    if _M.product == "HSM" or _M.product == "PG" then
        new_timer(0, updateConfigHandle)
    end
    --]]

    -- init health check
    if _M.product == "UCE" then
        initHealthCheckTwo()
    else
        initHealthCheck()
    end

    -- do others
end

function _M.initAntControlor(ctx)
    local purge = require "ant.purge"
    purge.run(ctx)
end

function frame()
    math.randomseed(tostring(ngx.time()):reverse():sub(1, 6))
    math.random()
    return _M
end

return frame()

