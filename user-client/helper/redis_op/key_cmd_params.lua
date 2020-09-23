-- this scripte will fit for redis comand: command key param1 param2...
-- ARGV[1] is redis command name
-- #ARGV is the param (nums + 1)

local result

for i = #ARGV, 1, -1 do
  if i == 1 then
    result = redis.call(ARGV[1], KEYS[1])
    break
  end

  if i == 2 then
    result = redis.call(ARGV[1], KEYS[1], ARGV[2])
    break
  end

  if i == 3 then
    result = redis.call(ARGV[1], KEYS[1], ARGV[2], ARGV[3])
    break
  end

  if i == 4 then
    result = redis.call(ARGV[1], KEYS[1], ARGV[2], ARGV[3], ARGV[4])
    break
  end

  if i == 5 then
    result = redis.call(ARGV[1], KEYS[1], ARGV[2], ARGV[3], ARGV[4], ARGV[5])
    break
  end
end

return result
