--[[
struct hint_header_t
{
    int32_t hint_version;
    int32_t pmt_pid;
    int32_t pcr_pid;
    int32_t video_pid;
    int32_t audio_pid;
    int16_t video_stream_type;
    int16_t audio_stream_type;
    int32_t avg_bitrate;
    int32_t hint_num;
};

struct hint_header_new_t : public hint_header_t
{
    //new add
    int32_t status;//0:not completed, 1:completed
    uint32_t update_time;
};

struct hint_item_old_t
{
    int32_t pts;    //ms
    int64_t offset;
    int32_t pak_count;
};

hint_header_t: 32bytes
00000000  05 00 00 00 00 10 00 00  00 01 00 00 00 01 00 00  |................|
00000010  01 01 00 00 1b 00 0f 00  35 fc 31 00 6e 00 00 00  |........5.1.n...|

hint_header_new_t: 8bytes
00000020  33 18 05 00 80 38 05 08 

hint_item_old_t[0]: 16bytes + 5bytes(unknow padding)
                                   00 00 00 00 34 02 00 00  |3....8......4...|
00000030  00 00 00 00 3c 01 00 00  00 cb 05 00 00 fd 0e 00  |....<...........|
00000040  00 

hint_item_old_t[1]: 16bytes + 5bytes(unknow padding)
             f0 db 15 00 00 00 00  00 c0 01 00 00 00 c8 14  |................|
00000050  00 00 e5 28 00 00 e0 dc  27 00 00 00 00 00 c2 00  |...(....'.......|
00000060  00 00 00 b0 2e 00 00 9e  4a 00 00 b8 21 4a 00 00  |........J...!J..|
00000070  00 00 00 63 01 00 00 00  69 50 00 00 14 62 00 00  |...c....iP...b..|
00000080  90 9a 6e 00 00 00 00 00  5f 01 00 00 00 df 67 00  |..n....._.....g.|
00000090  00 ff 6c 00 00 3c 00 7a  00 00 00 00 00 2a 01 00  |..l..<.z.....*..|
000000a0  00 00 ca 72 00 00 14 7f  00 00 00 0b 88 00 00 00  |...r............|
000000b0  00 00 f6 01 00 00 00 df  84 00 00 df 9d 00 00 f0  |................|
000000c0  fc c2 00 00 00 00 00 2b  01 00 00 00 aa a3 00 00  |.......+........|
000000d0  10 a4 00 00 30 6e c6 00  00 00 00 00 16 01 00 00  |....0n..........|
000000e0  00 db a9 00 00 d5 a6 00  00 64 d3 c8 00 00 00 00  |.........d......|
000000f0  00 e5 00 00 00 00 a0 ac  00 00 e5 b9 00 00 94 fc  |................|


]]--

local _M = {}

function _M.timeToOffset(hint, time)
    local io = require "io"
    local file = io.open(hint, "rb")
    if not file then
        return false
    end

    -- read binary file to number
    local function readbin(file, size)
        local block = file:read(size)
        if not block then return nil end

        local num = 0
        for i=size, 1, -1 do 
            num = (num * 256) + string.byte(block, i)
        end

        return num
    end

    -- seek to hint_num
    file:seek("set", 28)
    hint_num  = readbin(file, 4)

    -- skip header, seek to item
    file:seek("set", 40)

    local last_pts = 0
    local last_offset = 0

    for i = 1, hint_num do
        local pts = readbin(file, 4)
        local offset = readbin(file, 8)

        if pts == nil or offset == nil then 
            return nil
        end

        -- select a nearest offset
        if pts >= time then
            if pts - time > time - last_pts then 
                return last_offset
            else
                return offset
            end
        end

        -- record last pts and offset
        last_pts = pts
        last_offset = offset

        -- drop pak_count and padding
        file:seek("cur", 9)
    end

    file:close()

    -- outof file size
    return nil
end

return _M

