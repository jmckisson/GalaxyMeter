-------------------------------------------------------------------------------
-- GeminiLogging
-- Copyright (c) NCsoft. All rights reserved
-- Author: draftomatic
-- Logging library (loosely) based on LuaLogging.
-- Comes with appenders for GeminiConsole and Print() Debug Channel.
-------------------------------------------------------------------------------

local GeminiPackages = _G["GeminiPackages"]		-- Get GeminiPackages from the global environment

GeminiPackages:Require("drafto_inspect-1.0", function(inspect) 
	--Print("GeminiLogging Require")
	
	local GeminiLogging = {}
	
	-- Initialize variables

	-- The GeminiLogging.DEBUG Level designates fine-grained informational events that are most useful to debug an application
	GeminiLogging.DEBUG = "DEBUG"
	-- The GeminiLogging.INFO level designates informational messages that highlight the progress of the application at coarse-grained level
	GeminiLogging.INFO = "INFO"
	-- The WARN level designates potentially harmful situations
	GeminiLogging.WARN = "WARN"
	-- The ERROR level designates error events that might still allow the application to continue running
	GeminiLogging.ERROR = "ERROR"
	-- The FATAL level designates very severe error events that will presumably lead the application to abort
	GeminiLogging.FATAL = "FATAL"

	-- Data structures for levels
	GeminiLogging.LEVEL = {"DEBUG", "INFO", "WARN", "ERROR", "FATAL"}
	GeminiLogging.MAX_LEVELS = #GeminiLogging.LEVEL
	-- Enumerate levels
	for i=1,GeminiLogging.MAX_LEVELS do
		GeminiLogging.LEVEL[GeminiLogging.LEVEL[i]] = i
	end

	-- Factory method for loggers
	function GeminiLogging:GetLogger(opt)
		
		-- Default options
		if not opt then 
			opt = {
				level = self.INFO,
				pattern = "%d %n %c %l - %m",
				appender = "GeminiConsole"
			}
		end

		-- Initialize logger object
		local logger = {}
		
		-- Set appender
		if type(opt.appender) == "string" then
			logger.append = self:getAppender(opt.appender)
			if not logger.append then
				Print("Invalid appender")
				return nil
			end
		elseif type(opt.appender) == "function" then
			logger.append = opt.appender
		else
			Print("Invalid appender")
			return nil
		end
		
		-- Set pattern
		logger.pattern = opt.pattern
		
		-- Set level
		logger.level = opt.level
		local order = self.LEVEL[logger.level]
		
		-- Set logger functions (debug, info, etc.) based on level option
		for i=1,self.MAX_LEVELS do
			local upperName = self.LEVEL[i]
			local name = upperName:lower()
			if i >= order then
				logger[name] = function(self, message, opt)
					local debugInfo = debug.getinfo(2)		-- Get debug info for caller of log function
					--Print(inspect(debug.getinfo(3)))
					--local caller = debugInfo.name or ""
					local dir, file, ext = string.match(debugInfo.short_src, "(.-)([^\\]-([^%.]+))$")
					local caller = file or ""
					caller = string.gsub(caller, "." .. ext, "")
					local line = debugInfo.currentline or "-"
					logger:append(GeminiLogging.prepareLogMessage(logger, message, upperName, caller, line))		-- Give the appender the level string
				end
			else
				logger[name] = function() end			-- noop if level is too high
			end
		end

		return logger
	end

	function GeminiLogging:prepareLogMessage(message, level, caller, line)
		
		if type(message) ~= "string" then
			if type(message) == "userdata" then
				message = inspect(getmetatable(message))
			else
				message = inspect(message)
			end
		end
		
		local logMsg = self.pattern
		message = string.gsub(message, "%%", "%%%%")
		logMsg = string.gsub(logMsg, "%%d", os.date("%I:%M:%S%p"))		-- only time, in 12-hour AM/PM format. This could be configurable...
		logMsg = string.gsub(logMsg, "%%l", level)
		logMsg = string.gsub(logMsg, "%%c", caller)
		logMsg = string.gsub(logMsg, "%%n", line)
		logMsg = string.gsub(logMsg, "%%m", message)
		
		return logMsg
	end


	-------------------------------------------------------------------------------
	-- Default Appenders
	-------------------------------------------------------------------------------
	local tLevelColors = {
		DEBUG = "FF4DDEFF",
		INFO = "FF52FF4D",
		WARN = "FFFFF04D",
		ERROR = "FFFFA04D",
		FATAL = "FFFF4D4D"
	}
	function GeminiLogging:getAppender(name)
		if name == "GeminiConsole" then
			return function(self, message, level)
				GeminiPackages:Require("GeminiConsole-1.1", function(GeminiConsole)
					--local GeminiConsole = GeminiPackages:GetPackage("GeminiConsole-1.1")
					--if GeminiConsole then
						-- Kinda hacky thing here to get level colors printed. The way messages are formated needs redesign to do this right.
						-- This works but it's really slow. Need to rethink this...
						--[[local prePieces = {}
						local suffix = ""
						local words = string.gmatch(message, "[%S\n]+")
						local i = 1
						for word in words do
							if i <= 2 then
								prePieces[i] = word
							else
								suffix = suffix .. " " .. word
							end
							i = i + 1
						end
						--Print(prePieces[1])
						--Print(prePieces[2])
						--Print(suffix)
						GeminiConsole:Append(prePieces[1] .. " ", nil, true)
						GeminiConsole:Append(prePieces[2], tLevelColors[level], true)
						GeminiConsole:Append(suffix, nil, true)
						GeminiConsole:Append("")		-- newline
						--]]
						GeminiConsole:Append(message)
					--else
					--	Print(message)		-- Writes to Debug channel by default
					--end
				end)
			end
		elseif name == "Print" then
			return function(self, message, level)
				Print(message)
			end
		end
		return nil
	end

	GeminiPackages:NewPackage(GeminiLogging, "GeminiLogging-1.0", 4)
	
end)