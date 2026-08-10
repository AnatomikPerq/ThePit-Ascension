-- Knock the opaque canvas colour out of a drawing, from the border inwards.
--
--   "$ASEPRITE" -b --script-param src=<in> --script-param png=<out.png> \
--               [--script-param save=1] --script tools/aseprite/knockout_background.lua
--
-- Why this exists: two of the drawings for Uzi arrived with the Aseprite canvas
-- colour baked in as an opaque background — `uzi_standing_1` and the railgun
-- charge indicator both came out with #B9A8D8 filling every pixel around the
-- silhouette, while the two railgun states exported with proper alpha. A sprite
-- with an opaque background draws a lavender rectangle around the character.
--
-- It floods from the EDGES rather than replacing the colour everywhere, so the
-- same lavender used as a highlight inside the drawing survives. That is the
-- whole reason this is a script and not a colour-replace.
--
-- `pockets=1` then clears whatever of that colour the flood could not reach:
-- the enclosed holes a drawing has on purpose — the trigger guard and the grip
-- cutout on the charge indicator, which the border can never reach. Pass it
-- only when the colour is known to be background everywhere, and read the
-- count it prints: a large number means it is being used as paint somewhere.
--
-- `save=1` writes the .aseprite back as well, so re-exporting later needs no
-- second pass. Without it only the PNG is written and the source is left alone.

local p = app.params
local src = p.src
local png = p.png

local spr = app.open(src)
if spr == nil then
	print("cannot open " .. tostring(src))
	return
end

app.command.ChangePixelFormat { format = "rgb" }
app.command.FlattenLayers { visibleOnly = false }
-- Flattening merges into a layer Aseprite calls "Background", and a background
-- layer is opaque BY DEFINITION: it exports every cleared pixel back to solid,
-- however transparent the image behind it is. Demoting it to an ordinary layer
-- is what makes the knockout below survive saveCopyAs.
app.command.LayerFromBackground()

local w, h = spr.width, spr.height
local cel = spr.cels[1]

-- One image the size of the canvas, so a cel that does not start at the origin
-- does not shift every coordinate below.
local full = Image(w, h, ColorMode.RGB)
if cel ~= nil then
	full:drawImage(cel.image, cel.position)
end

local clear = app.pixelColor.rgba(0, 0, 0, 0)
local bg = full:getPixel(0, 0)

if app.pixelColor.rgbaA(bg) == 0 then
	print(src .. ": already transparent at the corner, nothing to do")
else
	local stack = {}
	local seen = {}

	local function push(x, y)
		if x < 0 or y < 0 or x >= w or y >= h then return end
		local k = y * w + x
		if seen[k] then return end
		seen[k] = true
		if full:getPixel(x, y) ~= bg then return end
		stack[#stack + 1] = { x, y }
	end

	for x = 0, w - 1 do
		push(x, 0)
		push(x, h - 1)
	end
	for y = 0, h - 1 do
		push(0, y)
		push(w - 1, y)
	end

	local cleared = 0
	while #stack > 0 do
		local q = table.remove(stack)
		local x, y = q[1], q[2]
		full:drawPixel(x, y, clear)
		cleared = cleared + 1
		push(x + 1, y)
		push(x - 1, y)
		push(x, y + 1)
		push(x, y - 1)
	end
	print(string.format("%s: cleared %d background pixels of %d", src, cleared, w * h))

	if p.pockets ~= nil then
		local pockets = 0
		for y = 0, h - 1 do
			for x = 0, w - 1 do
				if full:getPixel(x, y) == bg then
					full:drawPixel(x, y, clear)
					pockets = pockets + 1
				end
			end
		end
		print(string.format("%s: cleared %d enclosed pocket pixels", src, pockets))
	end
end

spr.cels[1].image = full
spr.cels[1].position = Point(0, 0)

if png ~= nil then
	spr:saveCopyAs(png)
end
if p.save ~= nil then
	spr:saveAs(src)
end
