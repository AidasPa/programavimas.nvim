-- The API's RFC 3339 timestamps as epoch seconds, and dates shown in Lithuanian time
-- (Europe/Vilnius), as the web app and the VS Code extension show them whatever the computer's
-- time zone. Lua has no time zone database, so the offset follows the EU rule: UTC+2, and UTC+3
-- from 01:00 UTC on the last Sunday of March to 01:00 UTC on the last Sunday of October.

local M = {}

--- Days since 1970-01-01 of a civil date (Howard Hinnant's algorithm).
local function days_from_civil(y, m, d)
  y = m <= 2 and y - 1 or y
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

--- Epoch seconds of an RFC 3339 timestamp, or nil when it is not one.
---@param value string?
---@return number?
function M.parse(value)
  if type(value) ~= "string" then return nil end
  local y, mo, d, h, mi, s, rest = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d):(%d%d)(.*)$")
  if not y then return nil end
  local fraction = rest:match("^%.(%d+)") or ""
  rest = rest:sub(fraction == "" and 1 or #fraction + 2)
  local offset = 0
  if rest:upper() ~= "Z" then
    local sign, oh, om = rest:match("^([+-])(%d%d):?(%d%d)$")
    if not sign then return nil end
    offset = (tonumber(oh) * 60 + tonumber(om)) * 60 * (sign == "+" and 1 or -1)
  end
  local seconds = days_from_civil(tonumber(y), tonumber(mo), tonumber(d)) * 86400
    + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s)
  return seconds - offset + (fraction ~= "" and tonumber("0." .. fraction) or 0)
end

--- The day of the month of a month's last Sunday (March and October have 31 days).
local function last_sunday(year, month)
  local day = days_from_civil(year, month, 31)
  -- 1970-01-01 was a Thursday; 0 is Sunday.
  return 31 - (day + 4) % 7
end

--- Seconds east of UTC in Vilnius at that moment.
---@param epoch number
function M.vilnius_offset(epoch)
  local year = tonumber(os.date("!%Y", math.floor(epoch)))
  local summer = days_from_civil(year, 3, last_sunday(year, 3)) * 86400 + 3600
  local winter = days_from_civil(year, 10, last_sunday(year, 10)) * 86400 + 3600
  return (epoch >= summer and epoch < winter) and 3 * 3600 or 2 * 3600
end

---@param format string
---@param epoch number
local function vilnius(format, epoch)
  epoch = math.floor(epoch)
  return os.date("!" .. format, epoch + M.vilnius_offset(epoch))
end

---@param epoch number
function M.date_time(epoch) return vilnius("%Y-%m-%d %H:%M", epoch) end

---@param epoch number
function M.clock(epoch) return vilnius("%H:%M", epoch) end

--- "Today, 23:59", "Tomorrow, 08:00", "Due 2026-11-12 23:59", "Overdue · …".
---@param due number
---@param now? number
function M.due_label(due, now)
  local t = require("programavimas.i18n").t
  now = now or os.time()
  if due < now then return t("due.overdue", { date = M.date_time(due) }) end
  local today = vilnius("%Y-%m-%d", now)
  local tomorrow = vilnius("%Y-%m-%d", now + 86400)
  local day = vilnius("%Y-%m-%d", due)
  if day == today then return t("due.today", { time = M.clock(due) }) end
  if day == tomorrow then return t("due.tomorrow", { time = M.clock(due) }) end
  return t("due.on", { date = M.date_time(due) })
end

return M
