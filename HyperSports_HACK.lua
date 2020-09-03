local M = {}

local cpu = manager:machine().devices[":maincpu"]
local mem = cpu.spaces["program"]
local ioport = manager:machine():ioport()
local in0 = ioport.ports[":P1_P2"]
local in1 = ioport.ports[":SYSTEM"]
local screen = manager:machine().screens[":screen"]

M.RunLeft  = { in0 = in0, field = in0.fields["P1 Button 1"] }
M.Action   = { in0 = in0, field = in0.fields["P1 Button 2"] }
M.RunRight = { in0 = in0, field = in0.fields["P1 Button 3"] }
M.start1   = { in1 = in1, field = in1.fields["1 Player Start"] }

local EVENT_NUMBER   	= 0x3068
local STROKE_COUNTER	= 0x3157
local SWIMMING_PISTOL   = 0x31C0 	-- 0->1
local LETTER_COUNTER 	= 0x3402
local CURRENT_LETTER 	= 0x3420

-- Main States
local STATE_STARTUP   	= 0
local STATE_INITIALS  	= 1
local STATE_SWIMMING  	= 2

-- Universal "Nothing going on" state
local SUBSTATE_NONE				  = 0

-- Enter your Initials substates
local SUBSTATE_INITIALS_1STLETTER = 1
local SUBSTATE_INITIALS_2NDLETTER = 2
local SUBSTATE_INITIALS_3RDLETTER = 3
local SUBSTATE_INITIALS_DONE      = 4

-- Swimming substates
local SUBSTATE_SWIMMING_WAITING   = 1
local SUBSTATE_SWIMMING_SWIMMING  = 2
local SUBSTATE_SWIMMING_BREATHE	  = 3
local SUBSTATE_SWIMMING_DONE	  = 4


-- Bit defines for player buttons
local RIGHT   = 1
local ACTION  = 2
local LEFT    = 4

-- Temp variable initializations
M.framestart = 0
M.framecounter = 0
M.pressed = 0
M.buttonHoldTimer = 0
M.currentState  = STATE_STARTUP
M.subState = SUBSTATE_NONE


-- Reset all the buttons and states
function M.reset()
	M.Action.field:set_value(0)
	M.RunLeft.field:set_value(0)
	M.RunRight.field:set_value(0)
	M.pressed = 0
end

-- Press the run buttons, alternate which button based on the status of the RIGHT button
function M.swim()
	-- This toggles which run button is pressed per 1/2 frame
	if M.pressed & RIGHT == RIGHT then
		M.RunLeft.field:set_value(1)
		M.RunRight.field:set_value(0)
		M.pressed = M.pressed & ~RIGHT
	else
		M.RunLeft.field:set_value(0)
		M.RunRight.field:set_value(1)
		M.pressed = M.pressed | RIGHT
	end
end

-- function called every frame
function M.updateMem()
	M.frameCounter = screen:frame_number() - M.frameStart
	
	if M.currentState == STATE_STARTUP then
		-- If we're here, we're just waiting for the signal that we're on the "Enter your initials" screen
		if mem:read_u8(CURRENT_LETTER) == 0x11 then
			-- Unpress the start button
			M.start1.field:set_value(0)
			-- Move us on to the next state
			M.currentState = STATE_INITIALS
			M.subState = SUBSTATE_INITIALS_1STLETTER
		end
	elseif M.currentState == STATE_INITIALS then
		if M.subState == SUBSTATE_INITIALS_1STLETTER then
			-- 'F' is 0x16
			if mem:read_u8(CURRENT_LETTER) == 0x16 then
				-- Stop moving if we're on the right letter
				M.RunRight.field:set_value(0)
				M.pressed = M.pressed & ~RIGHT
				
				-- Press the ACTION button to select it.
				M.Action.field:set_value(1)
				M.pressed = M.pressed | ACTION
				-- Go to next substate
				M.subState = SUBSTATE_INITIALS_2NDLETTER
				return
			else
				if M.pressed & RIGHT ~= RIGHT then
					M.RunRight.field:set_value(1)
					M.pressed = M.pressed | RIGHT
				end
			end
		elseif M.subState == SUBSTATE_INITIALS_2NDLETTER then
			-- Wait for the counter to change
			if mem:read_u8(LETTER_COUNTER) ~= 0x51 then
				M.buttonHoldTimer = M.buttonHoldTimer + 1
				if M.buttonHoldTimer > 10 then
					M.buttonHoldTimer = 0
					if in0:read() == 253 then
						M.Action.field:set_value(0)
					else
						M.Action.field:set_value(1)
					end
				end
				return
			else
				M.Action.field:set_value(0)			
				M.pressed = M.pressed & ~ACTION
			end

			-- 'A' is 0x11
			if mem:read_u8(CURRENT_LETTER) == 0x11 then
				-- Stop moving if we're on the right letter
				M.RunLeft.field:set_value(0)
				M.pressed = M.pressed & ~LEFT
				
				-- Press the ACTION button to select it.
				M.Action.field:set_value(1)
				M.pressed = M.pressed | ACTION
				
				-- Go to next substate
				M.subState = SUBSTATE_INITIALS_3RDLETTER
				return
			else
				if M.pressed & LEFT ~= LEFT then
					M.RunLeft.field:set_value(1)
					M.pressed = M.pressed | LEFT
				end
			end
		elseif M.subState == SUBSTATE_INITIALS_3RDLETTER then
			-- Wait for the counter to change
			if mem:read_u8(LETTER_COUNTER) ~= 0x52 then
				M.buttonHoldTimer = M.buttonHoldTimer + 1
				if M.buttonHoldTimer > 10 then
					M.buttonHoldTimer = 0
					if in0:read() == 253 then
						M.Action.field:set_value(0)
					else
						M.Action.field:set_value(1)
					end
				end
				return
			else
				M.Action.field:set_value(0)			
				M.pressed = M.pressed & ~ACTION
			end

			-- 'B' is 0x12
			if mem:read_u8(CURRENT_LETTER) == 0x12 then
				-- Press the ACTION button to select it.
				-- Stop moving if we're on the right letter
				M.RunRight.field:set_value(0)
				M.pressed = M.pressed & ~RIGHT
				
				-- Press the ACTION button to select it.
				M.Action.field:set_value(1)
				M.pressed = M.pressed | ACTION
				
				-- Go to next state
				M.subState = SUBSTATE_INITIALS_DONE
				return
			else
				if M.pressed & RIGHT ~= RIGHT then
					M.RunRight.field:set_value(1)
					M.pressed = M.pressed | RIGHT
				end
			end
		elseif M.subState == SUBSTATE_INITIALS_DONE then
			-- Wait for the counter to change
			if mem:read_u8(LETTER_COUNTER) ~= 0 then
				M.buttonHoldTimer = M.buttonHoldTimer + 1
				if M.buttonHoldTimer > 10 then
					M.buttonHoldTimer = 0
					if in0:read() == 253 then
						M.Action.field:set_value(0)
					else
						M.Action.field:set_value(1)
					end
				end
				return
			else
				-- We're done here, release the action button
				M.Action.field:set_value(0)
				M.pressed = M.pressed & ~ACTION
				
				-- Go to next state
				M.currentState = STATE_SWIMMING
				M.subState	   = SUBSTATE_SWIMMING_WAITING
				M.reset()
			end
		end
	elseif M.currentState == STATE_SWIMMING then
		-- Make sure we're still in this event
		event = math.fmod(mem:read_u8(EVENT_NUMBER), 7)
		if  event ~= 0 then
			M.reset()
			print("MADE IT TO THE END!")
			emu.pause()
			return
		end
		-- Waiting for the starter's pistol
		if M.subState == SUBSTATE_SWIMMING_WAITING then
			if mem:read_u8(SWIMMING_PISTOL) ~= 0x01 then
				return
			else
				-- Gun has fired, time to swim
				M.subState = SUBSTATE_SWIMMING_SWIMMING
				-- Release all buttons, clear all states
				M.reset()
				return
			end
		elseif M.subState == SUBSTATE_SWIMMING_SWIMMING then
			-- Stroke counter tracks the number of stokes since the last breath.
			-- When it gets to 4, you have to breathe.  Until then, SWIM
			if mem:read_u8(STROKE_COUNTER) ~= 4 then
				M.swim()
			else
				-- Press the ACTION button to breathe.
				M.Action.field:set_value(1)
				M.subState = SUBSTATE_SWIMMING_BREATHE
				return
			end
		elseif M.subState == SUBSTATE_SWIMMING_BREATHE then
			-- Release the ACTION button.
			M.Action.field:set_value(0)
			M.subState = SUBSTATE_SWIMMING_SWIMMING
		end
	end
end

function M.waiter()
	repeat
		emu.wait(screen:time_until_pos(0, 0))
		M.updateMem()
		emu.wait(screen:time_until_pos(screen:height()/2), 0)
		M.updateMem()
	until false
end

-- start game
function M.start()
    -- Press 1-player start button
    M.start1.field:set_value(1)
    M.frameStart = screen:frame_number()

    -- register update loop callback function
    local co = coroutine.create(M.waiter)
	coroutine.resume(co)
end

M.start()

return M
