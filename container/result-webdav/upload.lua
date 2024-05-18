-- upload.lua
--==========================================
-- File upload
--==========================================
--
-- Import module
local upload = require "resty.upload"
local cjson = require "cjson"

-- Define the structure of the reply
-- Basic structure
local function response(status,msg,data)
    local res = {}
    res["status"] = status
    res["msg"] = msg
    res["data"] = data
    local jsonData = cjson.encode(res)
    return jsonData
end

-- Default successful response
local function success()
    return response(0,"success",nil)
end
-- Default with data response for success upload
local function successWithData(data)
    return response(0,"success",data)
end

-- aborted response
local function failed( msg )
    return response(-1,msg,nil)
end

local chunk_size = 4096
-- Get requested form
local form, err = upload:new(chunk_size)
if not form then
    ngx.log(ngx.ERR, "failed to new upload: ", err)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    ngx.say(failed("No files were obtained"))
end
form:set_timeout(30000)

-- Define string split Split attribute
string.split = function(s, p)
    local rt= {}
    string.gsub(s, '[^'..p..']+', function(w) table.insert(rt, w) end )
    return rt
end
-- Before and after defining support strings trim attribute
string.trim = function(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- The root path where the file is saved
-- local saveRootPath = ngx.var.store_dir
local uri = ngx.var.request_uri
-- local saveRootPath = string.match("/srv/"..uri, "%g*/")
local saveRootPath = string.match("/srv/"..uri, "%g*/")

-- for some cases, the path for the uploaded files do not exist
-- just create it
os.execute("mkdir -p "..saveRootPath)

-- Saved file object
local fileToSave
-- Identifies whether the file was saved successfully
local ret_save = false
-- Actual received file name
-- Actual saved file name
local filename

-- tmp saved file name before fully uploaded
local t_filename

-- execute user's user name and user home
local run_user = ngx.var.run_user
local user_home = ngx.var.user_home

-- filename with path
local p_filename
-- tmp filename  with path
local p_t_filename
-- tag for file if it is a rpm
local is_rpm = false
-- tag for rpm if it is signed successfully
local sign_suc = false

-- Start processing data
while true do
    -- Read data
    local typ, res, err = form:read()
    if not typ then
        ngx.say(failed(err))
        return
    end
    -- Start reading http header
    if typ == "header" then
        -- Resolve the file name uploaded this time
        local key = res[1]
        local value = res[2]
        if key == "Content-Disposition" then
            -- Resolve the file name uploaded this time
            -- form-data; name="keyName"; filename="xxx.xx"
            local kvlist = string.split(value, ';')
            for _, kv in ipairs(kvlist) do
                local seg = string.trim(kv)
                if seg:find("filename") then
                    local kvfile = string.split(seg, "=")
                    -- Actual file name
                    filename = string.sub(kvfile[2], 2, -2)
                    if filename then
                        t_filename = filename .. ".tmp"
                        -- open(establish)file
                        fileToSave = io.open(saveRootPath .."/" .. t_filename, "w+")
                        if not fileToSave then
                            -- ngx.say("failed to open file ", filename)
                            ngx.say(failed("fail to open file"))
                            return
                        end
                        break
                    end
                end
            end
        end
    elseif typ == "body" then
        -- Start reading http body
        if fileToSave then
            -- Write file contents
            fileToSave:write(res)
        end
    elseif typ == "part_end" then
        -- File write finished, close the file
        if fileToSave then
            fileToSave:close()
            fileToSave = nil
        end

        ret_save = true
        p_filename = saveRootPath.."/"..filename
	p_t_filename = saveRootPath.."/"..t_filename
        local r_status = false
        local r_exit
        local r_code
        local retries = 0

        p_filename = string.trim(p_filename)
        p_t_filename = string.trim(p_t_filename)
        os.rename(p_t_filename, p_filename)
    elseif typ == "eof" then
        break
    else
        ngx.log(ngx.INFO, "do other things")
    end
end

if ret_save then
    local uploadData = {}
    uploadData["file"] = rawFileName
    ngx.say(successWithData(uploadData))
else
    os.execute("rm -f "..p_filename)
    ngx.say(failed("System exception"))
end
