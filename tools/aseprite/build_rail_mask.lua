-- First draft of the railgun indicator's ORDER MASK. One-shot.
--
--   "$ASEPRITE" -b --script-param src=assets/ui/rail_indicator.png \
--               --script-param ase=assets/sprites/src/rail_indicator_mask.aseprite \
--               --script-param png=assets/ui/rail_indicator_mask.png \
--               --script tools/aseprite/build_rail_mask.lua
--
-- WHAT THE MASK MEANS, because the shader is short and this is the whole idea:
--
--   black (0)  this pixel is not energy. Draw it exactly as painted, always —
--              the whole body of the gun, the metal, the pink detailing.
--   1..255     this pixel IS an energy cell, and the VALUE IS ITS PLACE IN THE
--              FILL ORDER. 1 lights first, 255 lights last. The shader lights a
--              cell when its value is at or below the `fill` uniform.
--
-- That is why there are no per-charge frames. Six charges is `fill = n / 6`;
-- an ult draining continuously is the same uniform tweened from 1 to 0. Nothing
-- about the art has to know which of those is happening.
--
-- This script only guesses. It finds the green by hue and orders it left to
-- right — one strip along the whole gun, from the butt of the stock to the
-- muzzle. Open the .aseprite it writes and repaint it to say something else:
-- light the receiver before the barrel, group the cells into six blocks,
-- whatever reads best. Nothing in code needs to change when you do.
--
-- WHAT A COLUMN'S PLACE IN THE ORDER IS, because there are three defensible
-- answers and the first two are wrong:
--
--   by pixel count   a column's share of the scale is its share of the energy
--                    PIXELS. This is what the first version did, and it made
--                    the sparse end of the gun vanish from the gauge: the bar
--                    on the stock is 26 of 539 energy pixels, so it lit inside
--                    the first 5% of the scale and then sat there, lit, for the
--                    whole rest of the climb. The owner's word for it was that
--                    it "stays unused".
--   by raw x         even in screen space, but then the fill stalls: 16% of the
--                    scale falls in the two stretches of gun that carry no
--                    green at all, and during those the widget does not move.
--   by energy column what this does. A column's place is how many columns that
--                    HAVE energy on them stand to its left, so the lit fraction
--                    of the strip equals `fill` exactly, every sixth of the
--                    scale lights the same length of gun, and nothing stalls.

local p = app.params
local spr = app.open(p.src)
if spr == nil then
	print("cannot open " .. tostring(p.src))
	return
end

app.command.ChangePixelFormat { format = "rgb" }
app.command.FlattenLayers { visibleOnly = false }

local w, h = spr.width, spr.height
local cel = spr.cels[1]
local src = Image(w, h, ColorMode.RGB)
if cel ~= nil then
	src:drawImage(cel.image, cel.position)
end

-- Green enough to be energy rather than a grey-green shadow on the metal.
-- Tuned against the drawing's actual palette: it takes #C3FF3E, #98FA28 and the
-- darker #327222 / #175902 shading of the same cells, and leaves #43644A and
-- #546459 (desaturated body greens) and every grey alone.
local function is_energy(r, g, b, a)
	if a == 0 then return false end
	return g > 60 and g > r * 1.25 and g > b * 1.5
end

-- Pass one: how many energy pixels stand in each column, and how many columns
-- carry any at all.
local per_column = {}
local total = 0
local lit_columns = 0
for x = 0, w - 1 do
	per_column[x] = 0
end
for y = 0, h - 1 do
	for x = 0, w - 1 do
		local c = src:getPixel(x, y)
		if is_energy(app.pixelColor.rgbaR(c), app.pixelColor.rgbaG(c),
				app.pixelColor.rgbaB(c), app.pixelColor.rgbaA(c)) then
			per_column[x] = per_column[x] + 1
			total = total + 1
		end
	end
end
for x = 0, w - 1 do
	if per_column[x] > 0 then lit_columns = lit_columns + 1 end
end

if total == 0 then
	print("no energy pixels found — check is_energy() against the palette")
	return
end

-- Pass two: a column's place in the order is how many energy-carrying columns
-- stand to its LEFT. Strictly to the left, so the leftmost is 1 and the whole
-- strip is lit before the scale runs out.
local rank = {}
local seen = 0
for x = 0, w - 1 do
	rank[x] = 1 + math.floor(254.0 * seen / lit_columns + 0.5)
	if per_column[x] > 0 then seen = seen + 1 end
end

local out = Sprite(w, h, ColorMode.RGB)
out.cels[1].image = Image(w, h, ColorMode.RGB)
local mask = out.cels[1].image
local cells = 0
for y = 0, h - 1 do
	for x = 0, w - 1 do
		local c = src:getPixel(x, y)
		if is_energy(app.pixelColor.rgbaR(c), app.pixelColor.rgbaG(c),
				app.pixelColor.rgbaB(c), app.pixelColor.rgbaA(c)) then
			local v = rank[x]
			mask:drawPixel(x, y, app.pixelColor.rgba(v, v, v, 255))
			cells = cells + 1
		else
			mask:drawPixel(x, y, app.pixelColor.rgba(0, 0, 0, 255))
		end
	end
end

-- The line to read: `strip` is how much of the drawing the gauge actually uses.
-- One sixth of the scale is one sixth of that, wherever on the gun it falls.
print(string.format("%d energy pixels of %d, strip %d columns of %d wide",
	cells, w * h, lit_columns, w))

if p.ase ~= nil then
	out:saveAs(p.ase)
end
if p.png ~= nil then
	out:saveCopyAs(p.png)
end
