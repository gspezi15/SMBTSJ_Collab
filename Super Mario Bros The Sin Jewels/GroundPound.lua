--[[
	Groundpound.lua
	By Marioman2007 - v1.3.1
]]

local easing = require("ext/easing")
local clearpipe = require("blocks/AI/clearpipe")
local GP = {}

-- constants for pound states
GP.STATE_NONE = 0
GP.STATE_SPIN = 1
GP.STATE_POUND = 2
GP.STATE_POUND_AFTER = 3

-- input constants for GP.inputStyle
GP.INPUT_ALT_JUMP = 1
GP.INPUT_DOWN = 2
GP.INPUT_DOUBLE_DOWN = 3

-- input style for ground pounding
GP.inputStyle = GP.INPUT_ALT_JUMP

-- input delay if GP.inputStyle is set to GP.INPUT_DOUBLE_DOWN
GP.doublePressDelay = 32

-- number of frames the player needs to wait before starting another pound
GP.cooldown = 16

-- player's can't ground pound if set to false
GP.enabled = true

-- whether or not the pound jump is enabled
GP.poundJumpEnabled = true

-- speed of the pound jump
GP.poundJumpSpeed = -13

-- default speed of the player when they pound into a slope
GP.slopeSpeed = 6

-- default pounding speed
GP.poundSpeed = 12

-- turn blocks are handled a bit differently
GP.turnBlocks = table.map{90}

-- small players can't break blocks if true
GP.smallCantBreak = true

-- players can directly start warping if they come in contact with a warp while pounding, requires quickPipes.lua
GP.quickWarpPipes = true

-- if true, players will automatically enter clearpipes when pounding
GP.enterClearPipes = true

-- time in frames it takes to complete the rotation
GP.rotationDuration = 20

-- extra vertical offset when pounding blocks containing more than one npc
GP.extraBonkOffset = 4

-- size of one frame in the sprite sheet
GP.cellSize = vector(100, 100)

-- speedY acceleration after a player's momentum gets disturbed by brick blocks
GP.acceleration = 0.5

-- default animation settings
GP.animation = {
	[GP.STATE_SPIN] = {frames = 1, framespeed = 5},
	[GP.STATE_POUND] = {frames = 1, framespeed = 8},
	[GP.STATE_POUND_AFTER] = {frames = 1, framespeed = 5},
}

-- default player images
GP.images = {
	[CHARACTER_MARIO] = Graphics.loadImageResolved("GroundPound/groundPound-1.png"),
	[CHARACTER_LUIGI] = Graphics.loadImageResolved("GroundPound/groundPound-2.png"),
}

-- effects table
GP.effects = {
	smoke = 900,
	poof  = 901,
	stars = 902,
}

-- sounds table
GP.SFX = {
	poundStart = {id = SFX.open(Misc.resolveSoundFile("GroundPound/poundStart")), volume = 1},
	poundJump = {id = 59, volume = 1},
	poundHit = {id = SFX.open(Misc.resolveSoundFile("GroundPound/poundHit")), volume = 1},
}

local data = {}
local charData = {}
local durableBlocks = {}
local brittleBlocks = {}
local customBlockFuncs = {}
local customNPCFuncs = {}

local solidBlocks = table.iclone(Block.SOLID)
local blockBlacklist = {}

local hittableNPCs = table.iclone(NPC.HITTABLE)
local npcBlacklist = {}
local jumphurtNPCs = {}

local blackListedStates = table.map{3, 6, 7, 8, 9, 10, 499, 500}

local starShader = Shader()
starShader:compileFromFile(nil, Misc.multiResolveFile("starman.frag", "shaders\\npc\\starman.frag"))

local quickPipes
pcall(function() quickPipes = require("quickPipes") end)

local aw
pcall(function() aw = require("anotherwalljump") end)
pcall(function() aw = aw or require("aw") end)

aw = aw or {
	preventWallSlide = function() end,
	isWallSliding = function() return 0 end,
}

local function changeState(cfg, s)
	cfg.state = s
	cfg.frameTimer = 0
	cfg.currentFrame = 0
end

-- registers a character with the given settings
function GP.registerCharacter(id, settings)
	settings = settings or {}

	local anim = settings.anim or GP.animation
	local rd = (anim[GP.STATE_POUND_AFTER].frames or 1) * (anim[GP.STATE_POUND_AFTER].framespeed or 1)
	local frames = settings.frames or {{{7}, {7}, {7}}}
	local defCanSlide = Graphics.getHUDType(id) == Graphics.HUD_ITEMBOX
	
	charData[id] = {
		enabled = true,
		poundSpeed = settings.poundSpeed or GP.poundSpeed,
		slopeSpeed = settings.slopeSpeed or GP.slopeSpeed,
		jumpSpeed = settings.jumpSpeed or GP.poundJumpSpeed,
		jumpEnabled = settings.jumpEnabled or GP.poundJumpEnabled,
		frames = frames,
		image = settings.image or GP.images[id],
		anim = anim,
		restDuration = rd,
		canSlide = (settings.canSlide == nil and defCanSlide) or settings.canSlide,
		draw = settings.draw ~= false,
	}
end

-- convenience function to register the main 5 characters
function GP.applyDefaultSettings()
	local frameTable = {{{1, 15, -1, 13}, {1, 15, -1, 13}, {1}}}

	local animTable = {
		[GP.STATE_SPIN] = {frames = 4, framespeed = 6},
		[GP.STATE_POUND] = {frames = 4, framespeed = 2},
		[GP.STATE_POUND_AFTER] = {frames = 1, framespeed = 5},
	}

	GP.registerCharacter(CHARACTER_MARIO)
	GP.registerCharacter(CHARACTER_LUIGI, {frames = {{{24}, {24}, {1}}}, jumpSpeed = -14})
	GP.registerCharacter(CHARACTER_PEACH, {frames = frameTable, anim = animTable})
	GP.registerCharacter(CHARACTER_TOAD, {frames = frameTable, anim = animTable})
	GP.registerCharacter(CHARACTER_LINK, {frames = {{{9}, {9}, {1}}}})
end

-- registers a block as a breakable block
function GP.whitelistBlock(id)
	if durableBlocks[id] then
		durableBlocks[id] = false
	end

	brittleBlocks[id] = true
end

-- deregisters a block as a breakable block
function GP.blacklistBlock(id)
	if brittleBlocks[id] then
		brittleBlocks[id] = false
	end

	durableBlocks[id] = true
end

-- adds a block so that it can be pounded
function GP.addSolidBlock(id)
	if not BLOCK.SOLID_MAP[id] then
		table.insert(solidBlocks, id)
	end

	blockBlacklist[id] = nil
end

-- removes a block so that it cannot be pounded
function GP.removeSolidBlock(id)
	blockBlacklist[id] = true
end

-- registers a block as a breakable block
function GP.whitelistNPC(id)
	if not NPC.HITTABLE_MAP[id] then
		table.insert(hittableNPCs, id)
	end

	npcBlacklist[id] = nil

	if NPC.config[id].jumphurt then
		jumphurtNPCs[id] = true
	end
end

-- deregisters a block as a breakable block
function GP.blacklistNPC(id)
	npcBlacklist[id] = true
end

-- registers a custom npc function, runs when it gets pounded and ignores any other changes
function GP.registerCustomNPCFunc(id, func)
	customNPCFuncs[id] = func
	GP.whitelistNPC(id)
end

-- registers a custom block function, runs when it gets pounded and ignores any other changes
function GP.registerCustomBlockFunc(id, func)
	customBlockFuncs[id] = func
	GP.addSolidBlock(id)
end

-- returns a table of per-player data
function GP.getData(idx)
	if idx then
		return data[idx]
	else
		return data
	end
end

-- returns a table of per-character data
function GP.getCharacterData(char)
	if char then
		return charData[char]
	else
		return charData
	end
end

-- starts the given player's pound
function GP.startPound(p)
	local cfg = data[p.idx]

	if p:mem(0x12E, FIELD_BOOL) and p.powerup > 1 then
		p:mem(0x164, FIELD_WORD, -1)
		p:mem(0x12E, FIELD_BOOL, false)
	end

	p.speedX = 0
	p:mem(0x11C, FIELD_WORD, 0)
	p:mem(0x3C, FIELD_BOOL, false)
	p:mem(0x50,  FIELD_BOOL, false)

	changeState(cfg, GP.STATE_SPIN)
	SFX.play(GP.SFX.poundStart.id, GP.SFX.poundStart.volume)
end

-- cancels the given player's pound
function GP.cancelPound(p)
	local cfg = data[p.idx]

	p:mem(0x164, FIELD_WORD, 0)

	changeState(cfg, GP.STATE_NONE)
	cfg.bonkOffset = 0
	cfg.waitTimer = 0
	cfg.rotation = 0
	cfg.rotlerp = 0
	cfg.inputTimer = 0
	cfg.cooldown = GP.cooldown
	cfg.colNPCs = {}
	cfg.colBlocks = {}

	if p.forcedState ~= FORCEDSTATE_PIPE then
		cfg.poundedIntoWarp = false
	end
end

-- starts a pound jump
function GP.poundJump(p)
	if data[p.idx].cantJumpThisFrame then return end

	p.speedX = data.oldInputDir * 1.5
	p.speedY = charData[p.character].jumpSpeed
	SFX.play(GP.SFX.poundJump.id, GP.SFX.poundJump.volume)
	GP.cancelPound(p)
	
	p:mem(0x1A, FIELD_BOOL, false)
	p:mem(0x176, FIELD_WORD, 0)
	p:mem(0x11C, FIELD_WORD, 0)

	Routine.run(function(v)
		for i = 1, 6 do
			if v.speedY < 1 then
				Routine.waitFrames(3)
				Effect.spawn(GP.effects.smoke, v.x + v.width/2, v.y + v.height)
			else
				break
			end
		end
	end, p)
end

-- enables a player's ability to pound
function GP.enable(p)
	data[p.idx].enabled = true
end

-- disables a player's ability to pound
function GP.disable(p)
	data[p.idx].enabled = false
end

-- enables a character's ability to pound
function GP.enableCharacter(char)
	charData[char].enabled = true
end

-- disables a character's ability to pound
function GP.disableCharacter(char)
	charData[char].enabled = false
end

-- prevents pounding for one frame
function GP.preventPound(p)
	data[p.idx].cantThisFrame = true
end

-- prevents pound jumping for one frame
function GP.preventPoundJump(p)
	data[p.idx].cantJumpThisFrame = true
end

-- prevents spawning for one frame
function GP.preventEffects(p)
	data[p.idx].cantSpawnEffects = true
end

-- returns true if the given player is pounding, also returns the pound state
function GP.isPounding(p)
	return data[p.idx].state ~= 0, data[p.idx].state
end

-- returns the current frame on the sheet, for animation purposes
function GP.getFrame(p)
	local cfg = data[p.idx]
	local cData = charData[p.character]
	local offsetY = 0

	if cfg.state == GP.STATE_POUND or cfg.state == GP.STATE_NONE then
		offsetY = cData.anim[GP.STATE_SPIN].frames
	elseif cfg.state == GP.STATE_POUND_AFTER then
		offsetY = cData.anim[GP.STATE_SPIN].frames + cData.anim[GP.STATE_POUND].frames
	end

	return offsetY + cfg.currentFrame
end

function GP.renderPlayer(p, args)
	args = args or {}

	local cfg = data[p.idx]
	local cellSize = args.cellSize or GP.cellSize
	local priority = args.priority or ((p.forcedState == FORCEDSTATE_PIPE and -70) or -25)
	local direction = args.direction or p.direction
	local rotation = args.rotation or cfg.rotation
	local shader = args.shader or (p.hasStarman and starShader) or nil
	local uniforms = args.uniforms or {time = lunatime.tick() * 2}
	local offset = args.offset or vector(0, cfg.bonkOffset)
	local frameX = args.frameX or (p.powerup - 1)
	local frameY = args.frameY or GP.getFrame(p)
	local texture = args.texture or charData[p.character].image

	Graphics.drawBox{
		texture      = texture,
		x            = p.x + p.width/2 + offset.x * p.direction,
		y            = p.y + p.height/2 + offset.y,
		width        = cellSize.x * direction,
		height       = cellSize.y,
		sourceX      = frameX * cellSize.x,
		sourceY      = frameY * cellSize.y,
		sourceWidth  = cellSize.x,
		sourceHeight = cellSize.y,
		centered     = true,
		sceneCoords  = true,
		priority     = priority,
		rotation     = rotation * direction,
		shader       = shader,
		uniforms     = uniforms
	}
end

function GP.overrideRenderData(p, newTable)
	data[p.idx].renderData = newTable
end

local function initData(idx)
	if data[idx] ~= nil then return end

	data[idx] = {
		enabled = true,
		cantThisFrame = false,
		cantJumpThisFrame = false,
		cantSpawnEffects = false,
		canPressJump = true,
		canPressPoundButton = true,
		poundedIntoWarp = false,
		cooldown = 0,

		collider = Colliders.Box(0, 0, 1, 1),
		colNPCs = {},
		colBlocks = {},
		oldInputDir = 0,

		state = GP.STATE_NONE,
		bonkOffset = 0,
		waitTimer = 0,
		rotlerp = 0,
		rotation = 0,
		inputTimer = 0,
		frameTimer = 0,
		currentFrame = 0,
		renderData = {},
	}
end

local function spawnFX(p, x, y)
	if data[p.idx].cantSpawnEffects then return end

	local posX = x or (p.x + p.width/2)
	local posY = y or (p.y + p.height)
	
	for i = -1, 1, 2 do
		local poof = Effect.spawn(GP.effects.poof, posX + (p.width + 8) * i, posY)
		poof.direction = i
		poof.y = poof.y - poof.height/2
	end

	Effect.spawn(GP.effects.stars, posX, posY)
	SFX.play(GP.SFX.poundHit.id, GP.SFX.poundHit.volume)
end

local function getKey()
	if GP.inputStyle == GP.INPUT_ALT_JUMP then
		return "altJump"
	end

	return "down"
end

local function npcFilter(v)
	return (
		not v.isHidden
		and not v.isGenerator
		and not v.friendly
		and (not NPC.config[v.id].jumphurt or jumphurtNPCs[v.id])
		and not npcBlacklist[v.id]
	)
end

local function blockFilter(v)
	return (
		not v.isHidden
		and not v:mem(0x5A, FIELD_BOOL)
		and not blockBlacklist[v.id]
	)
end

local function isOnGround(p)
	return (
		(p.speedY == 0) -- "on a block"
		or p:mem(0x176,FIELD_WORD) ~= 0 -- on an NPC
		or (p:mem(0x48,FIELD_WORD) ~= 0) -- on a slope
	)
end

local function canPound(p)
	return (
        GP.enabled
		and data[p.idx].enabled
		and data[p.idx].state == 0
		and not p.inLaunchBarrel
		and not p.inClearPipe
		and charData[p.character]
		and aw.isWallSliding(p) == 0
		and not isOnGround(p)
		and not data[p.idx].cantThisFrame
		and p.forcedState == FORCEDSTATE_NONE
		and p.deathTimer == 0 and not p:mem(0x13C, FIELD_BOOL) -- not dead
		and p.mount == MOUNT_NONE
		and not p.isMega
		and not p:mem(0x50, FIELD_BOOL) -- spin jumping
		and not p:mem(0x0C, FIELD_BOOL) -- fairy
		and not p:mem(0x3C, FIELD_BOOL) -- sliding
		and not p:mem(0x44, FIELD_BOOL) -- surfing on a rainbow shell
		and not p:mem(0x4A, FIELD_BOOL) -- statue
		and p:mem(0x26,FIELD_WORD) == 0 -- picking up something from the top
		and not p.holdingNPC
		and p:mem(0x06, FIELD_WORD) <= 0
		and Level.endState() == LEVEL_WIN_TYPE_NONE
	)
end

local function canCancel(p)
	return (
		blackListedStates[p.forcedState]
		or p.inLaunchBarrel
		or p.inClearPipe
		or not charData[p.character]
		or p.isMega
		or aw.isWallSliding(p) ~= 0
		or p.mount ~= MOUNT_NONE
		or p:mem(0x4A, FIELD_BOOL) -- statue
		or p:mem(0x3C, FIELD_BOOL) -- sliding
		or p:mem(0x0C, FIELD_BOOL) -- fairy
		or (p.deathTimer > 0 and p:mem(0x13C, FIELD_BOOL))
		or p:mem(0x06, FIELD_WORD) > 0
		or Level.endState() ~= LEVEL_WIN_TYPE_NONE
	)
end

local function checkRoom(id, v)
	for k, b in ipairs(Block.getIntersecting(v.x, v.y + v.height, v.x + v.width, v.y + v.height + NPC.config[id].height)) do
		if b.isValid and (not Block.SEMISOLID_MAP[b.id]) and (not Block.PLAYERSOLID_MAP[b.id]) and (not Block.config[b.id].passthrough) and (not b.isHidden) and (not b:mem(0x5A, FIELD_BOOL)) then
			return false
		end
	end

	return true
end

local function poundBlock(v, p)
	local cfg = data[p.idx]
	local eventObj = {cancelled = false}

	GP.onBlockPound(eventObj, v, p)

	if eventObj.cancelled then return end

	if customBlockFuncs[v.id] then
		customBlockFuncs[v.id](v, p)
		return
	end

	-- coins
	if (v.contentID > 0 and v.contentID <= 99) then
		if v.contentID > 1 and not p.keys[getKey()] then
			if isOnGround(p) then
				spawnFX(p)
				changeState(cfg, GP.STATE_POUND_AFTER)
				p:mem(0x164, FIELD_WORD, 0)
			elseif p.speedY < 0 then
				spawnFX(p)
				GP.cancelPound(p)
			end
		end

		v:hit(true, p)
		p.speedY = charData[p.character].poundSpeed
		SFX.play(3)

	-- npcs
	elseif v.contentID >= 1001 then -- other npcs
		SFX.play(3)

		if not checkRoom(v.contentID - 1000, v) then
			GP.cancelPound(p)
			v:hit(false, p)
			p.speedY = -7
		else
			v:hit(true, p)
			p.speedY = charData[p.character].poundSpeed
		end

	-- empty
	elseif v.contentID == 0 then
		if p.powerup == 1 and GP.smallCantBreak then
			SFX.play(3)
			v:hit(true, p)

			if GP.turnBlocks[v.id] then
				p.speedY = 0.05
			end
		elseif GP.turnBlocks[v.id] and not durableBlocks[v.id] then
			v:hit(true, p)
			SFX.play(3)
			p.speedY = 0.05
		elseif (brittleBlocks[v.id] or Block.MEGA_SMASH_MAP[v.id]) and not durableBlocks[v.id] then
			v:remove(true)
			p.speedY = 0.05
		else
			v:hit(true, p)
		end
	end

	GP.onPostBlockPound(v, p)
end

local function poundNPC(v, p)
	local eventObj = {cancelled = false}

	GP.onNPCPound(eventObj, v, p)

	if eventObj.cancelled or v:mem(0x156, FIELD_WORD) > 0 then return end

	if customNPCFuncs[v.id] then
		customNPCFuncs[v.id](v, p)
	elseif not NPC.MULTIHIT_MAP[v.id] then
		v:harm(HARM_TYPE_NPC)
	else
		v:harm(HARM_TYPE_JUMP)
		GP.cancelPound(p)
		Colliders.bounceResponse(p, 1)
	end

	v:mem(0x156, FIELD_WORD, 20)
	GP.onPostNPCPound(v, p)
end

local function onTickPlayer(p, cfg, cData)
	if cfg.state ~= GP.STATE_NONE then
		cfg.frameTimer = cfg.frameTimer + 1
		cfg.currentFrame = math.floor(cfg.frameTimer / cData.anim[cfg.state].framespeed) % cData.anim[cfg.state].frames

		if p.keys.left and not p.keys.right then
			data.oldInputDir = -1
		elseif p.keys.right and not p.keys.left then
			data.oldInputDir = 1
		else
			data.oldInputDir = 0
		end

		p.keys.right = false
		p.keys.left = false
		p.speedX = 0

		p:mem(0x172, FIELD_BOOL, false) -- run
		p:mem(0x120, FIELD_BOOL, false) -- spin jump
		p:mem(0xBC, FIELD_WORD, 2) -- mount cooldown

		cfg.canPressPoundButton = false
		cfg.colNPCs = Colliders.getColliding{a = cfg.collider, b = hittableNPCs, btype = Colliders.NPC, filter = npcFilter}
		cfg.colBlocks = Colliders.getColliding{a = cfg.collider, b = solidBlocks, btype = Colliders.BLOCK}

		if p.powerup ~= 5 then
			p.keys.altRun = false
		end

		if canCancel(p) then
			GP.cancelPound(p)
		end

		aw.preventWallSlide(p)

		if getKey() == "altJump" then
			if p.powerup == 4 or p.powerup == 5 then
				if not isOnGround(p) and p:mem(0x48, FIELD_WORD) == 0 then
					p.keys.altJump = false
				end
			end

			if p:mem(0x48, FIELD_WORD) == 0 then
				p.keys.down = false
			end
		else
			p.keys.altJump = false
		end
	end

	if cfg.state == GP.STATE_NONE then
		if not cfg.canPressPoundButton and not p.keys[getKey()] then
			cfg.canPressPoundButton = true
		end

		if p.keys.jump ~= KEYS_PRESSED and p.keys[getKey()] == KEYS_PRESSED
		and not p.keys.up and canPound(p) and (getKey() == "altJump" or cfg.canPressPoundButton) and cfg.cooldown == 0
		then
			if cfg.inputTimer > 0 or GP.inputStyle ~= GP.INPUT_DOUBLE_DOWN then
				GP.startPound(p)
			else
				cfg.inputTimer = GP.doublePressDelay
			end
		end

	elseif cfg.state == GP.STATE_SPIN then
		cfg.rotlerp = math.min(cfg.rotlerp + 1/GP.rotationDuration, 1)
		cfg.rotation = easing.inOutSine(cfg.rotlerp, 0, 360, 1)
		p.speedY = -Defines.player_grav

		if cfg.rotlerp == 1 then
			cfg.waitTimer = cfg.waitTimer + 1
		end

		if cfg.waitTimer >= cData.anim[GP.STATE_SPIN].framespeed then
			cfg.waitTimer = 0
			cfg.rotation = 0
			cfg.rotlerp = 0
			
			if p:mem(0x34, FIELD_WORD) > 0 and p:mem(0x06, FIELD_WORD) == 0 then
				GP.cancelPound(p)
				p.speedY = cData.poundSpeed/2
			else
				changeState(cfg, GP.STATE_POUND)
				p.speedY = cData.poundSpeed
				p.keys.altJump = false

				-- do this a frame early to avoid bounces
				for k,v in ipairs(cfg.colNPCs) do
					poundNPC(v, p)
				end
			end
		end

	elseif cfg.state == GP.STATE_POUND then
		clearpipe.overrideInput(p, "down", true)

		if p.speedY > 0 then
			p.speedY = math.min(p.speedY + GP.acceleration, cData.poundSpeed)
		end

		if quickPipes and GP.quickWarpPipes then
			local col = cfg.collider

			for k, w in ipairs(Warp.getIntersectingEntrance(
				(p.x - 4) + p.speedX,
				(p.y - 4) + p.speedY,
				(p.x - 4) + (p.width + 4) + p.speedX,
				(p.y - 4) + (p.height + 4) + p.speedY
			)) do
				local warpBottom = w.entranceY + w.entranceHeight

				if w.entranceDirection == 3 and (p.y + p.height) >= (warpBottom - 2) and p.y <= warpBottom then
					local entered = quickPipes.enterLogic(p, w, true)
	
					if entered then
						cfg.poundedIntoWarp = true
						spawnFX(p, w.entranceX + w.entranceWidth/2, w.entranceY + w.entranceHeight)
						break
					end
				end
			end
		end

		for k,v in ipairs(cfg.colBlocks) do
			if Block.SLOPE_MAP[v.id] and cData.canSlide then
				GP.cancelPound(p)
				spawnFX(p)
				p:mem(0x3C, FIELD_BOOL, true)

				if Block.SLOPE_LR_FLOOR_MAP[v.id] then
					p.speedX = -cData.slopeSpeed
				elseif Block.SLOPE_RL_FLOOR_MAP[v.id] then
					p.speedX = cData.slopeSpeed
				end
			else
				poundBlock(v, p)
			end
		end

		for k,v in ipairs(cfg.colNPCs) do
			poundNPC(v, p)
		end

		if p:mem(0x34, FIELD_WORD) > 0 and p:mem(0x06, FIELD_WORD) == 0 then
			GP.cancelPound(p)
			p.speedY = cData.poundSpeed/2
		end

		if isOnGround(p) then
			if p:mem(0x48, FIELD_WORD) == 0 and not cfg.poundedIntoWarp then
				spawnFX(p)
				changeState(cfg, GP.STATE_POUND_AFTER)
				p:mem(0x164, FIELD_WORD, 0)
			else
				GP.cancelPound(p)
			end
		end

		if p.speedY < 0 then
			GP.cancelPound(p)
			p.speedY = math.min(p.speedY, -7)
		end

		if p.keys.up == KEYS_PRESSED and not p.keys[getKey()] then
			GP.cancelPound(p)
		end
	elseif cfg.state == GP.STATE_POUND_AFTER then		
		if p.keys.jump == KEYS_PRESSED and cData.jumpEnabled then
			GP.poundJump(p)
		end

		if cfg.frameTimer >= cData.restDuration + cData.anim[GP.STATE_POUND_AFTER].framespeed then
			GP.cancelPound(p)
		end
	end

	if cfg.state ~= GP.STATE_NONE and cfg.state ~= GP.STATE_POUND_AFTER then
		cfg.canPressJump = false
	elseif not cfg.canPressJump and not p.keys.jump then
		cfg.canPressJump = true
	end

	if not cfg.canPressJump then
		if cfg.state ~= GP.STATE_POUND_AFTER then
			p.keys.jump = false
		else
			p:mem(0x11E, FIELD_BOOL, false)
		end
	end

	if not cfg.canPressPoundButton then
		if getKey() == "altJump" then
			p:mem(0x120, FIELD_BOOL, false)
		elseif p:mem(0x48, FIELD_WORD) == 0 then
			p.keys.down = false
		end
	end

	cfg.cantThisFrame = false
	cfg.cantJumpThisFrame = false
	cfg.cantSpawnEffects = false
	cfg.inputTimer = math.max(cfg.inputTimer - 1, 0)
	cfg.cooldown = math.max(cfg.cooldown - 1, 0)

	local isExiting = quickPipes and (quickPipes.getData(p.idx).waitTimer > quickPipes.waitTime)

	if cfg.poundedIntoWarp and (p.forcedState ~= FORCEDSTATE_PIPE or isExiting) then
		cfg.poundedIntoWarp = false
	end
end

local function onTickEndPlayer(p, cfg, cData)
	cfg.collider.width = p.width
	cfg.collider.height = math.max(p.speedY, 8)
	cfg.collider.x = p.x + p.width/2 - cfg.collider.width/2
	cfg.collider.y = p.y + p.height

	if cfg.state > GP.STATE_SPIN and #cfg.colBlocks > 0 then
		local v

		for k, b in ipairs(cfg.colBlocks) do
			if b.isValid and b.contentID > 0 and b:mem(0x56, FIELD_WORD) ~= 0 then
				v = b
				break
			end
		end

		if v then
			if not GP.turnBlocks[v.id] then
				cfg.bonkOffset = v:mem(0x56, FIELD_WORD) + ((cfg.state == GP.STATE_POUND and GP.extraBonkOffset) or 0)
			end

			p.y = v.y - p.height
		end
	else
		cfg.bonkOffset = 0
	end
end

local function onDrawPlayer(p, cfg, cData)
	if not cData.draw then return end

	if (cfg.state ~= GP.STATE_NONE or cfg.poundedIntoWarp) and
	not p:mem(0x142, FIELD_BOOL) and p.deathTimer == 0 then
		p:setFrame(-50 * p.direction)

		if cData.image then
			GP.renderPlayer(p, cfg.renderData)
			
		elseif cData.frames then
			local thisFrames = cData.frames[p.powerup] or cData.frames[#cData.frames]
			local frame = thisFrames[cfg.state][cfg.currentFrame + 1]
			
			p:render{
				x = p.x,
				y = p.y + cfg.bonkOffset,
				frame = frame or 1,
				shader = (p.hasStarman and starShader) or nil,
				uniforms = {time = lunatime.tick() * 2}
			}
		end
	end
end

-- register events
function GP.onInitAPI()
	registerEvent(GP, "onTick")
	registerEvent(GP, "onTickEnd")
	registerEvent(GP, "onInputUpdate")
	registerEvent(GP, "onDraw")

	registerCustomEvent(GP, "onNPCPound")
	registerCustomEvent(GP, "onBlockPound")
	registerCustomEvent(GP, "onPostNPCPound")
	registerCustomEvent(GP, "onPostBlockPound")
end

-- main logic
function GP.onTick()
	for _, p in ipairs(Player.get()) do
		initData(p.idx)

		if charData[p.character] then
			onTickPlayer(p, data[p.idx], charData[p.character])
		end
	end
end

-- handle collider and bonk offset
function GP.onTickEnd()
	for _, p in ipairs(Player.get()) do
		if data[p.idx] and charData[p.character] then
			onTickEndPlayer(p, data[p.idx], charData[p.character])
		end
	end
end

-- interaction with clearpipes
function GP.onInputUpdate()
	if not GP.enabled or not GP.enterClearPipes then return end
	
	for _, p in ipairs(Player.get()) do
		local cfg = data[p.idx]

		if cfg and charData[p.character] and cfg.state == GP.STATE_POUND then
			clearpipe.overrideInput(p, "down", true)
		end
	end
end

-- rendering
function GP.onDraw()
	if not GP.enabled then return end
	
	for _, p in ipairs(Player.get()) do
		if data[p.idx] and charData[p.character] then
			onDrawPlayer(p, data[p.idx], charData[p.character])
		end
	end
end

return GP