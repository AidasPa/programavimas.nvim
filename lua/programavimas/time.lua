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

---@param epoch number
---@return integer year, integer month, integer day  In Vilnius
local function civil(epoch)
  local year, month, day = vilnius("%Y-%m-%d", epoch):match("^(%d+)-(%d+)-(%d+)$")
  return tonumber(year), tonumber(month), tonumber(day)
end

--- Days since 1970-01-01 of the Vilnius calendar day of a moment.
---@param epoch number
local function calendar_day(epoch) return days_from_civil(civil(epoch)) end

--- A day as the web writes it (i18n/formats.ts "dayMonth"): "Dec 1", "gruodžio 1 d."; with the
--- year when it isn't this year's, and the time when it isn't the end of the day
--- ("Dec 1, 08:00", "gruodžio 1 d. 08:00").
---@param epoch number
---@param now? number
function M.day(epoch, now)
  local i18n = require("programavimas.i18n")
  local year, month, day = civil(epoch)
  local this_year = civil(now or os.time())
  local date = i18n.t(year == this_year and "date.day" or "date.dayYear", {
    month = i18n.month(month),
    day = day,
    year = year,
  })
  local clock = M.clock(epoch)
  return clock == "23:59" and date or i18n.t("date.dayTime", { date = date, time = clock })
end

---@class programavimas.Due  A deadline in words
---@field text string    As the web's lists show it: "Today, 23:59", "In 3 days", "Dec 1", "Overdue · Nov 3"
---@field date string    The day: "Dec 1", "gruodžio 1 d. 08:00"
---@field later string?  How far off, to follow the date: "in 3 days", "in 4 weeks", "in 2 months"
---@field tone "danger"|"warning"|nil  Past; within a week (the web's red and orange)

--- A deadline as the web shows it (features/shared/due-date.tsx), counted in Vilnius calendar
--- days: today and tomorrow with the time, "In N days" within a week, else the date; and how
--- far off it is, for where there is room.
---@param due number
---@param now? number
---@return programavimas.Due
function M.due(due, now)
  local t = require("programavimas.i18n").t
  now = now or os.time()
  local date = M.day(due, now)
  if due < now then return { text = t("due.overdue", { date = date }), date = date, tone = "danger" } end
  local days = calendar_day(due) - calendar_day(now)
  if days == 0 then return { text = t("due.today", { time = M.clock(due) }), date = date, tone = "warning" } end
  if days == 1 then return { text = t("due.tomorrow", { time = M.clock(due) }), date = date, tone = "warning" } end
  local later
  if days < 14 then
    later = t("due.laterDays", { count = days })
  elseif days < 60 then
    later = t("due.laterWeeks", { count = math.floor(days / 7 + 0.5) })
  else
    later = t("due.laterMonths", { count = math.floor(days / 30.44 + 0.5) })
  end
  if days <= 7 then return { text = t("due.inDays", { count = days }), date = date, later = later, tone = "warning" } end
  return { text = date, date = date, later = later }
end

return M
