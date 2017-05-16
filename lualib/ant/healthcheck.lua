

local stream_sock = ngx.socket.tcp
local log = ngx.log
local ERR = ngx.ERR
local INFO = ngx.INFO
local WARN = ngx.WARN
local DEBUG = ngx.DEBUG
local str_find = string.find
local sub = string.sub
local re_find = ngx.re.find
local new_timer = ngx.timer.at
local time = ngx.now
local shared = ngx.shared
local debug_mode = ngx.config.debug
local concat = table.concat
local tonumber = tonumber
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local ceil = math.ceil
local spawn = ngx.thread.spawn
local wait = ngx.thread.wait
local pcall = pcall
local MAX = 2 ^ 46

local _M = {}
local balancerList = {}
local upstream_checker_statuses = {}
local servers_page = {}
local precise = 1
local nextTime = MAX

local ok, new_tab = pcall(require, "table.new")
if not ok or type(new_tab) ~= "function" then
    new_tab = function (narr, nrec) return {} end
end

local function info(...)
    log(INFO, "healthcheck: ", ...)
end

local function warn(...)
    log(WARN, "healthcheck: ", ...)
end

local function errlog(...)
    log(ERR, "healthcheck: ", ...)
end

local function debug(...)
    -- print("debug mode: ", debug_mode)
    if debug_mode then
        log(DEBUG, "healthcheck: ", ...)
    end
end

local function gen_peer_key(prefix, u, id)
    return prefix .. u .. id
end

local function get_balancerList()
    local up = {}
    local index = 1
    for k, _ in pairs(servers_page) do
        up[index] = k
        index = index + 1
    end
    return up
end

local function get_lock(ctx)
    local dict = ctx.dict
    local key = "l:" .. ctx.upstream

    local ok, err = dict:add(key, true, ctx.interval - 0.001)
    if not ok then
        if err == "exists" then
            return nil
        end
        errlog("failed to add key \"", key, "\": ", err)
        return nil
    end
    return true
end

local function clean_dict(ctx)
    local u = ctx.upstream
    local dict = ctx.dict

    local key = "v:" .. u
    local ok, err = dict:set(key, 0)
    if not ok then
        return nil, "clean_dict failed: " .. key .. "err:" .. err
    end

    local n = #ctx.servers
    for index = 1, n do
        key = gen_peer_key("d:", u, index - 1)
        ok, err = dict:set(key, nil)
        if not ok then
            return nil, "clean_dict failed: " .. key .. "err:" .. err
        end

        key = gen_peer_key("ok", u, index - 1)
        ok, err = dict:set(key, 0)
        if not ok then
            return nil, "clean_dict failed: " .. key .. "err:" .. err
        end

        key = gen_peer_key("nok", u, index - 1)
        ok, err = dict:set(key, 0)
        if not ok then
            return nil, "clean_dict failed: " .. key .. "err:" .. err
        end
    end
end

local function clean_balancer(name, flag)
    local balancer = balancerList[name .. flag]
    
    if not (balancer.servers == nil or next(balancer.servers)) then
        clean_dict(balancer)
        servers_page[name][flag] = {}
        balancer.servers = {}
    end

    balancer.nextTime = MAX
    balancer.lastTime = time()
end

local function check_ctx(name, id, servers, opts, time)
    if not servers then
        return
    end
    peers = servers

    if not opts then
        opts = {}
    end

    local type = opts.check
    if not type then
        type = "http"
    elseif type ~= "off" and type ~= "https" then
        type = "http"
    end

    local timeout = opts.timeout
    if not timeout then
        timeout = 1000
    end

    local concur = opts.concurrency
    if not concur then
        concur = 10
    end

    local interval = opts.interval
    if not interval then
        interval = 3 * precise
    else
        interval = interval / 1000
        if interval < precise then
            interval = precise
        end
    end

    local fall = opts.fall
    if not fall then
        fall = 3
    end

    local rise = opts.rise
    if not rise then
        rise = 3
    end

    local shm = opts.shm
    if not shm then
        shm = "healthcheck"
    end

    local dict = shared[shm]
    if not dict then
        return nil, "dict :" .. shm .. " is nil "
    end

    local http_req = opts.http_req
    if not http_req then
        http_req = "GET /check HTTP/1.1\r\nHost: admin.shatacdn.com\r\nConnection: close\r\nUser-Agent: HealthCheck\r\n\r\n"
    end

    local valid_statuses = opts.valid_statuses
    local statuses
    if not valid_statuses then
        valid_statuses = {200,}
    end
    statuses = new_tab(0, #valid_statuses)
    for _, status in ipairs(valid_statuses) do
        statuses[status] = true
    end

    local upstream = name .. id
    local nextTime
    local version = 0
    if balancerList[upstream] then
        nextTime = balancerList[upstream].nextTime
        version = balancerList[upstream].version
    end

    local ctx = {
        upstream    = upstream,
        http_req    = http_req,
        servers     = peers,
        timeout     = timeout,
        interval    = interval,
        fall        = fall,
        rise        = rise,
        concurrency = concur,
        dict        = dict,
        type        = type,
        version     = version,
        statuses    = statuses,
        lastTime    = time,
        nextTime    = nextTime,
    }

    return ctx
end

function _M.set_check_upstream(name, flag, servers, opts)
    if not name or not flag then
        return nil, "name or flag is nil"
    end

    local t = time()
    if balancerList[name .. flag] and balancerList[name .. flag].lastTime + 3 > t then
        return
    end

    local ctx, err = check_ctx(name, flag, servers, opts, t)
    if not ctx then
        if err then
            return nil, err
        end

        clean_balancer(name, flag)
        return true
    end
    
    balancerList[name .. flag] = ctx

    local ctx_t = t + ctx.interval
    if not ctx.nextTime or ctx.nextTime > ctx_t then
        ctx.nextTime = ctx_t
    end

    if nextTime > ctx.nextTime then
        nextTime = ctx.nextTime
    end

    if not servers_page[name] then
        servers_page[name] = {}
    end
    servers_page[name][flag] = servers or {}

    return true
end

function _M.update_peer_down_status(name, flag, id)
    if not name or not flag or not id then
        return nil, "args are err"
    end
        
    local u = name .. flag
    if not balancerList[u] then
        return nil, "balancerList: " .. u .. " is nil"
    end
    local ctx = balancerList[u]

    local peer = ctx.servers[id]
    if not peer then
        return nil, "peer is nil"
    end

    local dict = ctx.dict
    local key = gen_peer_key("d:", u, id - 1)
    local down = false
    local flag = true
    local res, err = dict:get(key)

    if not res then
        if err then
            return nil, "dict :" .. key .. " :".. err
        end
        if res == nil then
           flag = false
        end
    else
        down = true
    end

    if flag and ((peer.down and not down) or (not peer.down and down)) then
        peer.down = down
    end

    return true
end

function _M.set_peer_down(name, flag, id, value)
    if not name or not flag or not id or ( type(value) ~= "nil" and type(value) ~= "boolean" ) then
        return nil, "args are err"
    end

    local u = name .. flag
    if not balancerList[u] then
        return nil, "balancerList: " .. u .. " is nil"
    end

    local ctx = balancerList[u]
    local dict = ctx.dict
    local peer = ctx.servers[id]
    if not peer then
        return nil, "balancerList.servers id: " .. "id" .. " is nil"
    end
    peer.down = value

    if not ctx.new_version then
        ctx.new_version = true
    end

    local key = gen_peer_key("d:", u, id - 1)
    local ok, err = dict:set(key, value)
    if not ok then
        errlog("failed to set peer down state: ", err)
        return nil, "failed to set peer down state: " .. err
    end
    return true
end

local function set_peer_down_globally(ctx, id, value)
    local u = ctx.upstream
    local dict = ctx.dict
    local peer = ctx.servers[id + 1]
    if value == nil then
        value = false
    end
    peer.down = value

    if not ctx.new_version then
        ctx.new_version = true
    end

    local key = gen_peer_key("d:", u, id)
    local ok, err = dict:set(key, value)
    if not ok then
        errlog("failed to set peer down state: ", err)
    end
end

local function peer_fail(ctx, id, peer)
    debug("peer ", peer.name, " was checked to be not ok")

    local u = ctx.upstream
    local dict = ctx.dict

    local key = gen_peer_key("nok:", u, id)
    local fails, err = dict:get(key)
    if not fails then
        if err then
            errlog("failed to get peer nok key: ", err)
            return
        end
        fails = 1

        -- below may have a race condition, but it is fine for our
        -- purpose here.
        local ok, err = dict:set(key, 1)
        if not ok then
            errlog("failed to set peer nok key: ", err)
        end
    else
        fails = fails + 1
        local ok, err = dict:incr(key, 1)
        if not ok then
            errlog("failed to incr peer nok key: ", err)
        end
    end

    if fails == 1 then
        key = gen_peer_key("ok:", u, id)
        local succ, err = dict:get(key)
        if not succ or succ == 0 then
            if err then
                errlog("failed to get peer ok key: ", err)
                return
            end
        else
            local ok, err = dict:set(key, 0)
            if not ok then
                errlog("failed to set peer ok key: ", err)
            end
        end
    end

    if not peer.down and fails >= ctx.fall then
        warn("peer ", peer.name, " is turned down after ", fails,
            " failure(s)")
        peer.down = true
        set_peer_down_globally(ctx, id, true)
    end
end

local function peer_ok(ctx, id, peer)

    local u = ctx.upstream
    local dict = ctx.dict

    local key = gen_peer_key("ok:", u, id)
    local succ, err = dict:get(key)
    if not succ then
        if err then
            errlog("failed to get peer ok key: ", err)
            return
        end
        succ = 1

        -- below may have a race condition, but it is fine for our
        -- purpose here.
        local ok, err = dict:set(key, 1)
        if not ok then
            errlog("failed to set peer ok key: ", err)
        end
    else
        succ = succ + 1
        local ok, err = dict:incr(key, 1)
        if not ok then
            errlog("failed to incr peer ok key: ", err)
        end
    end

    if succ == 1 then
        key = gen_peer_key("nok:", u, id)
        local fails, err = dict:get(key)
        if not fails or fails == 0 then
            if err then
                errlog("failed to get peer nok key: ", err)
                return
            end
        else
            local ok, err = dict:set(key, 0)
            if not ok then
                errlog("failed to set peer nok key: ", err)
            end
        end
    end

    if peer.down and succ >= ctx.rise then
        warn("peer ", peer.name, " is turned up after ", succ,
            " success(es)")
        peer.down = false
        set_peer_down_globally(ctx, id, false)
    end
end

local function peer_error(ctx, id, peer, ...)
    if not peer.down then
        errlog(...)
    end
    peer_fail(ctx, id, peer)
end

local function check_peer(ctx, id, peer)
    if not peer then
        return
    end

    local ok, err
    local statuses = ctx.statuses
    local http_req = ctx.http_req
    local sock, err = stream_sock()
    if not sock then
        errlog("failed to create stream socket: ", err)
        return
    end

    sock:settimeout(ctx.timeout)
    ok, err = sock:connect(peer.host, peer.port)
    if not ok then
        if not peer.down then
            errlog("failed to connect to " ..  peer.host .. ":" .. peer.port, ": ", err)
        end
        return peer_fail(ctx, id, peer)
    end

    if peer.https == true or (peer.https == nil and ctx.type == "https") then
        ok,err = sock:sslhandshake()
        if not ok then
            if not peer.down then
                errlog("failed to ssl_connect to " .. peer.host .. ":" .. peer.port, ": ", err)
            end
            return peer_fail(ctx, id, peer)
        end
    end

    local bytes, err = sock:send(http_req)
    if not bytes then
        return peer_error(ctx, id, peer,
          "failed to send request to " .. peer.host .. ":" .. peer.port, ": ", err)
    end

    local status_line, err = sock:receive()
    if not status_line then
        peer_error(ctx, id, peer,
           "failed to receive status line from ".. peer.host .. ":" .. peer.port, ": ", err)
        if err == "timeout" then
            sock:close()  -- timeout errors do not close the socket.
        end
        return
    end

    if statuses then
        local from, to, err = re_find(status_line,
          [[^HTTP/\d+\.\d+\s+(\d+)]],
          "joi", nil, 1)
        if not from then
            peer_error(ctx, id, peer,
               "bad status line from " ..  peer.host .. ":" .. peer.port, ": ",
               status_line)
            sock:close()
            return
        end

        local status = tonumber(sub(status_line, from, to))
        if not statuses[status] then
            peer_error(ctx, id, peer, "bad status code from "
                .. peer.host .. ":" .. peer.port , ": ", status)
            sock:close()
            return
        end
    end

    peer_ok(ctx, id, peer)
    sock:close()
end

local function check_peer_range(ctx, from, to, peers)
    for i = from, to do
        check_peer(ctx, i - 1 , peers[i])
    end
end

local function check_peers(ctx, peers)
    if not peers then
        return
    end
    local n = #peers
    if n == 0 then
        return
    end

    upstream_checker_statuses[ctx.upstream] = true    

    local concur = ctx.concurrency
    if concur <= 1 then
        for i = 1, n do
            check_peer(ctx, i - 1, peers[i])
        end
    else
        local threads
        local nthr

        if n <= concur then
            nthr = n - 1
            threads = new_tab(nthr, 0)
            for i = 1, nthr do

                if debug_mode then
                    debug("spawn a thread checking ", " peer ", i - 1)
                end

                threads[i] = spawn(check_peer, ctx, i - 1, peers[i])
            end
            -- use the current "light thread" to run the last task
            if debug_mode then
                debug("check " and "backup" or "primary", " peer ",
                  n - 1)
            end
            check_peer(ctx, n - 1, peers[n])

        else
            local group_size = ceil(n / concur)
            local nthr = ceil(n / group_size) - 1

            threads = new_tab(nthr, 0)
            local from = 1
            local rest = n
            for i = 1, nthr do
                local to
                if rest >= group_size then
                    rest = rest - group_size
                    to = from + group_size - 1
                else
                    rest = 0
                    to = from + rest - 1
                end

                if debug_mode then
                    debug("spawn a thread checking ", " peers ",
                      from - 1, " to ", to - 1)
                end

                threads[i] = spawn(check_peer_range, ctx, from, to, peers)
                from = from + group_size
                if rest == 0 then
                    break
                end
            end
            if rest > 0 then
                local to = from + rest - 1

                if debug_mode then
                    debug("check " and "backup" or "primary",
                      " peers ", from - 1, " to ", to - 1)
                end

                check_peer_range(ctx, from, to, peers)
            end
        end

        if nthr and nthr > 0 then
            for i = 1, nthr do
                local t = threads[i]
                if t then
                    wait(t)
                end
            end
        end
    end
end

local function upgrade_peers_version(ctx)
    local peers = ctx.servers
    local u = ctx.upstream
    local dict = ctx.dict
    local n = #peers
    for i = 1, n, 1 do
        local peer = peers[i]
        local id = i - 1
        local key = gen_peer_key("d:", u, id)
        local down = false
        local flag = true
        local res, err = dict:get(key)
        if not res then
            if err then
                errlog("failed to get peer down state: ", err)
            end
            if res == nil then
                flag = false
            end
        else
            down = true
        end
        if flag and ((peer.down and not down) or (not peer.down and down)) then
            peer.down = down
        end
    end
end

local function check_peers_updates(ctx)
    local dict = ctx.dict
    local u = ctx.upstream
    local key = "v:" .. u
    local ver, err = dict:get(key)
    if not ver then
        if err then
            errlog("failed to get peers version: ", err)
            return
        end

        if ctx.version > 0 then
            ctx.new_version = true
        end
    elseif ctx.version < ver then
        upgrade_peers_version(ctx)
        ctx.version = ver
    elseif ctx.version > ver then
        return
    end

    return true
end

local function do_check(ctx)
    if not check_peers_updates(ctx) then
        return
    end
    
    if ctx.type == "off" then
        if ctx.new_version then
            local key = "v:" .. ctx.upstream
            local dict = ctx.dict

            local new_ver, err = dict:incr(key, 1, 0)
            if not new_ver then
                errlog("failed to publish new peers version: ", err)
            end

            ctx.version = new_ver
            ctx.new_version = nil
        end
        return
    end

    if get_lock(ctx) then
        check_peers(ctx, ctx.servers, false)
    end

    if ctx.new_version then
        local key = "v:" .. ctx.upstream
        local dict = ctx.dict

        debug("publishing peers version ", ctx.version + 1)

        local new_ver, err = dict:incr(key, 1, 0)
        if not new_ver then
            errlog("failed to publish new peers version: ", err)
        end

        ctx.version = new_ver
        ctx.new_version = nil
    end
end

local function check(premature)
    if premature then
        return
    end

    local t = time()
    if nextTime <= t then
        nextTime = MAX
        for k, v in pairs(balancerList) do
            if v.nextTime <= t then
                local ok, err = pcall(do_check, v)
                if not ok then
                    errlog("failed to run healthcheck cycle: ", err)
                end

                v.nextTime = t + v.interval
            end
            if nextTime > v.nextTime then
                nextTime = v.nextTime
            end
        end
    end

    local ok, err = new_timer(precise, check)
    if not ok then
        return nil, "failed to create timer: " .. err
    end
end

function _M.init(pre)
    if not pre or pre < 0.02 then
        pre = 0.02
    end
    precise = pre

    local ok, err = new_timer(0, check)
    if not ok then
        return nil, "failed to create timer: " .. err
    end

    return true
end

local function gen_peers_status_info(peers, bits, idx)
    local npeers = #peers
    for i = 1, npeers do
        local peer = peers[i]
        bits[idx] = "        "
        bits[idx + 1] = peer.host .. ":" .. peer.port
        if peer.down then
            bits[idx + 2] = " DOWN\n"
        else
            bits[idx + 2] = " UP\n"
        end
        idx = idx + 3
    end
    return idx
end

function _M.status_page()
    local us = get_balancerList()
    if not us then
        return "failed to get upstream names:"
    end

    local n = #us
    local bits = new_tab(20 * n, 0)
    local idx = 1

    for i = 1, n do
        if i > 1 then
            bits[idx] = "\n"
            idx = idx + 1
        end
        local u = us[i]
        bits[idx] = "Upstream "
        bits[idx + 1] = u .. "\n"
        idx = idx + 2

        for k, v in pairs(servers_page[u]) do
            bits[idx] = k
            idx = idx + 1

            local ncheckers = upstream_checker_statuses[u..k]
            if not ncheckers then
                bits[idx] = "    (NO checkers)"
                idx = idx + 1
            end

            bits[idx] = "\n"
            idx = idx + 1
            local peers = v
            idx = gen_peers_status_info(peers, bits, idx)
        end
    end
    return concat(bits)
end


return _M
