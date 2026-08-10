-- The railgun's aiming cursor. One-shot.
--
--   "$ASEPRITE" -b --script-param ase=assets/sprites/src/rail_crosshair.aseprite \
--               --script-param png=assets/ui/rail_crosshair.png \
--               --script tools/aseprite/build_crosshair.lua
--
-- It is generated rather than drawn because a crosshair that is one pixel off
-- centre is a crosshair that aims one pixel off, and by eye that is invisible
-- while by use it is maddening. The first version was drawn with the ellipse
-- tool and came out with 36 pixels that did not mirror.
--
-- Everything here is a function of distance from an INTEGER centre on an ODD
-- canvas, so every shape is symmetric by construction: there is a true middle
-- pixel, and `hotspot` in data/weapons/railgun.tres points at it.

local p = app.params
local SIZE = 31
local C = 15 -- the middle pixel, on both axes

local GREEN = { r = 195, g = 255, b = 62, a = 255 } -- the energy off the indicator
local DIM = { r = 152, g = 250, b = 40, a = 255 }
local DARK = { r = 10, g = 26, b = 4, a = 255 } -- outline, so it reads on anything
local WHITE = { r = 255, g = 255, b = 255, a = 255 }

local spr = Sprite(SIZE, SIZE, ColorMode.RGB)
spr.cels[1].image = Image(SIZE, SIZE, ColorMode.RGB)
local img = spr.cels[1].image

local function put(x, y, c)
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE then return end
	img:drawPixel(x, y, app.pixelColor.rgba(c.r, c.g, c.b, c.a))
end

local function dist(x, y)
	local dx = x - C
	local dy = y - C
	return math.sqrt(dx * dx + dy * dy)
end

-- The ring, two pixels thick, and the dark ring either side of it.
for y = 0, SIZE - 1 do
	for x = 0, SIZE - 1 do
		local d = dist(x, y)
		if d >= 8.2 and d <= 10.2 then
			put(x, y, GREEN)
		elseif d > 7.2 and d < 11.4 then
			put(x, y, DARK)
		end
	end
end

-- Four ticks on the axes, outside the ring. Whole rows and columns through the
-- middle pixel, so they cannot be off centre.
for i = 12, 14 do
	for _, c in ipairs({ { C, C - i }, { C, C + i }, { C - i, C }, { C + i, C } }) do
		put(c[1], c[2], GREEN)
		-- The outline runs alongside each tick.
		if c[1] == C then
			put(c[1] - 1, c[2], DARK)
			put(c[1] + 1, c[2], DARK)
		else
			put(c[1], c[2] - 1, DARK)
			put(c[1], c[2] + 1, DARK)
		end
	end
end
-- and capped at both ends
for _, c in ipairs({ { C, C - 15 }, { C, C + 15 }, { C - 15, C }, { C + 15, C } }) do
	put(c[1], c[2], DARK)
end
for _, c in ipairs({ { C, C - 11 }, { C, C + 11 }, { C - 11, C }, { C + 11, C } }) do
	put(c[1], c[2], DARK)
end

-- Four inner pips and the middle pixel: what the eye actually lands on.
for _, c in ipairs({ { C, C - 4 }, { C, C + 4 }, { C - 4, C }, { C + 4, C } }) do
	put(c[1], c[2], DIM)
end
put(C, C, WHITE)

-- Prove it before it is written. A crosshair that fails this is worse than none.
local bad = 0
for y = 0, SIZE - 1 do
	for x = 0, SIZE - 1 do
		local a = img:getPixel(x, y)
		if a ~= img:getPixel(SIZE - 1 - x, y) then bad = bad + 1 end
		if a ~= img:getPixel(x, SIZE - 1 - y) then bad = bad + 1 end
	end
end
print(string.format("crosshair %dx%d, centre (%d,%d), mirror mismatches: %d",
	SIZE, SIZE, C, C, bad))
if bad > 0 then
	print("NOT SYMMETRIC — not written")
	return
end

if p.ase ~= nil then spr:saveAs(p.ase) end
if p.png ~= nil then spr:saveCopyAs(p.png) end
