--
--  AppDelegate.applescript
--  OC USB MEDIA
--  Created by chris on 2026-09-09.
--
--  MODERN ONLY: macOS 10.13 (Mojave) -> Tahoe 26.
--  Legacy installers (Mavericks -> Sierra) are NOT supported
--  by this build. Progress = real log percentages + blind-window creep.
--  Install polling = NSTimer (1s) -> app always "Responding".
--  Flow starts via the button (connected to Build:).
--

use AppleScript version "2.4"
use framework "Foundation"
use scripting additions

script AppDelegate
	property parent : class "NSObject"
	property spinner : missing value
	property statusField : missing value
	property animated : false
	property pathToResources : "NSString"
	
	--- Engine state ---
	property myTimer : missing value
	property engineOSX : ""
	property engineDisk : ""
	property engineAppPath : false
	property engineAppName : ""
	property engineProgress : 0
	property engineDeadSeen : false
	property engineLogFile : "/tmp/cim_progress.log"
	property flowStarted : false
	property ocMode : false
	property ocLaunchTick : false
	property ocTicks : 0
	property enginePass : ""
	property ocRealVol : ""
	
	--- Your button (connected to Build:) starts the flow ---
	on Build:sender
		mainFlow()
	end Build:
	
	on cancel:sender
		quit
	end cancel:
	
	on applicationShouldTerminateAfterLastWindowClosed:sender
		return true
	end applicationShouldTerminateAfterLastWindowClosed:
	
	on applicationShouldTerminate:sender
		do shell script "killall Main 2>/dev/null; killall 'HP EliteBook 840 G4' 2>/dev/null; true"
		return current application's NSTerminateNow
	end applicationShouldTerminate:
	
	on applicationWillFinishLaunching:aNotification
		set pathToResources to (current application's class "NSBundle"'s mainBundle()'s resourcePath()) as string
	end applicationWillFinishLaunching:
	
	---- Fix the beachball ---- 
	on applicationDidFinishLaunching:aNotification
		set pathToResources to (current application's class "NSBundle"'s mainBundle()'s resourcePath()) as string
	end applicationDidFinishLaunching:
	
	--- Bring the app to front before EVERY dialog ---
	on bringToFront()
		try
			current application's NSApp's activateIgnoringOtherApps:(true)
		end try
		delay 0.2
	end bringToFront
	
	
	-- ============================================
	--  MAIN FLOW (runs once)
	--  CANCEL RULE: -128 (any Cancel/Quit click) -> quit app
	-- ============================================
	
	on mainFlow()
		if flowStarted then return
		set flowStarted to true
		
		my bringToFront()
		set theAction to button returned of (display dialog "
Welcome to OC USB MEDIA
You can create a bootable USB drive
from macOS High Sierra 10.13 to macOS Tahoe 26.

To create a USB installation media, you need a 16 GB or larger USB drive.

Starting with macOS Sonoma 14, some 16 GB USB drives are not sufficient, so use a 32 GB USB drive to avoid errors.

NOTE: SIP security and Gatekeeper must be disabled.

You must Quit Disk Utilty when you finished to format the USB Media." with icon note buttons {"Quit", "OC-Installer", "Create Install Media"} default button "Create Install Media")
		
		-- OC-Installer: open pkg then quit this app
		if theAction = "OC-Installer" then
			set pkgPath to pathToResources & "/Installer/OpenCore.pkg"
			do shell script "open " & quoted form of pkgPath
			delay 2
			quit
		end if
		
		if theAction = "Quit" then
			delay 1
			quit
		end if
		
		if theAction = "Create Install Media" then
			
			tell application "Disk Utility" to activate
			
			repeat
				if application "Disk Utility" is not running then exit repeat
				delay 1
			end repeat
			
			my bringToFront()
			
			set Volumepath to paragraphs of (do shell script "ls /Volumes")
			set Diskpath to choose from list Volumepath with prompt "
To be able to continue, select the volume
that you just formatted.
Then press the OK button" OK button name "OK" with multiple selections allowed
			
			if Diskpath is false then
				my bringToFront()
				display dialog "Quit Installer" with icon 0 buttons {"EXIT"} default button "EXIT"
				quit
			end if
			
			set Diskpath to item 1 of Diskpath -- list -> single volume name
			
			try
				my bringToFront()
				set theAction to button returned of (display dialog "

Choose the location of your Install macOS.app" with icon note buttons {"Quit", "10.13 to Tahoe 26"} cancel button "Quit" default button "10.13 to Tahoe 26")
				
				if theAction is in {"10.13 to Tahoe 26"} then
					
					my bringToFront()
					set InstallOSX to choose file of type {"XLSX", "APPL"} default location (path to applications folder) with prompt "Choose your Install macOS.app"
					set OSXInstaller to POSIX path of InstallOSX
					
					-- Sanity check: is it really a macOS installer?
					set CIMcheck to quoted form of (OSXInstaller & "/Contents/Resources/createinstallmedia")
					set checkResult to do shell script "test -x " & CIMcheck & " && echo yes || echo no"
					if checkResult is "no" then
						my bringToFront()
						display dialog "That app is not a valid macOS installer.
(createinstallmedia not found inside it.)" with icon stop buttons {"OK"} default button "OK"
						return
					end if
					
					-- App name (confirm dialog + volume icon cleanup)
					set nm to name of (info for InstallOSX)
					
					-- --applicationpath kept for safety (harmless)
					set needsAppPath to false
					
					delay 2
					my bringToFront()
					set confirmed to button returned of (display dialog "

Please confirm your choice?
Create Install Media from --> " & POSIX path of InstallOSX & "
Install to --> " & Diskpath & "

App name: " & nm & "

⚠️: Everything on this volume will be ERASED!" with icon note buttons {"Cancel", "OK"} cancel button "Cancel" default button "OK")
					
					if confirmed is "OK" then
						-- 🔑 Ask password ONCE (hidden, verified, 3 tries)
						set enginePass to my askPassword()
						if enginePass is "" then
							quit
						end if
						
						delay 2
						-- Store engine state, then hand over to the timer
						set engineOSX to OSXInstaller
						set engineDisk to Diskpath
						set engineAppPath to needsAppPath
						set engineAppName to nm
						my startEngine()
					end if
				end if
				
			on error errMsg number errNum
				-- -128 = user pressed a Cancel/Quit button -> close app
				if errNum is -128 then
					quit
				else
					my bringToFront()
					display dialog "Error: " & errMsg with icon stop buttons {"OK"} default button "OK"
				end if
			end try
		end if
	end mainFlow
	
	
	-- 🔑 Ask once, verify, retry until correct (or cancelled)
	on askPassword()
		my bringToFront()
		repeat 3 times
			set thePass to text returned of (display dialog "
Enter your administrator password.
It will be used for the whole process." default answer "" with icon note buttons {"Cancel", "OK"} cancel button "Cancel" default button "OK" with hidden answer)
			try
				do shell script "true" password thePass with administrator privileges
				return thePass
			on error
				my bringToFront()
				display dialog "Wrong password. Try again." with icon caution buttons {"OK"} default button "OK"
			end try
		end repeat
		return ""
	end askPassword
	
	
	-- ============================================================
	--  ENGINE START
	-- ============================================================
	
	on startEngine()
		set logFile to engineLogFile
		
		set OSXInstaller to engineOSX
		if OSXInstaller does not end with "/" then set OSXInstaller to OSXInstaller & "/"
		
		set appPathArg to ""
		if engineAppPath then set appPathArg to " --applicationpath \"" & OSXInstaller & "\""
		
		set startCmd to "rm -f " & logFile & " ; \"" & OSXInstaller & "Contents/Resources/createinstallmedia\" --volume /Volumes/\"" & engineDisk & "\"" & appPathArg & " --nointeraction > " & logFile & " 2>&1 &"
		do shell script startCmd password enginePass with administrator privileges
		
		try
			current application's NSApp's activateIgnoringOtherApps:(true)
		end try
		
		-- Progress bar: switch to determinate 0-100 mode
		if spinner is not missing value then
			spinner's stopAnimation:me
			set animated to false
			spinner's setIndeterminate:(false)
			spinner's setMinValue:(0 as real)
			spinner's setMaxValue:(100 as real)
			spinner's setDoubleValue:(0 as real)
		end if
		if statusField is not missing value then
			statusField's setStringValue:"Installing macOS... 0%"
		end if
		
		set engineProgress to 0
		set engineDeadSeen to false
		set ocMode to false
		set ocLaunchTick to false
		
		my startPollingTimer()
	end startEngine
	
	on startPollingTimer()
		set tickSel to current application's NSSelectorFromString("timerTick:")
		set myTimer to current application's NSTimer's scheduledTimerWithTimeInterval:1.0 target:me selector:tickSel userInfo:(missing value) repeats:true
	end startPollingTimer
	
	
	-- ============================================================
	--  TIMER TICK - three phases:
	--  media  : watch createinstallmedia log
	--  ocPrep : (one tick after 100%) launch the installer
	--  ocWatch: pgrep watches installer -> dialog when done
	-- ============================================================
	
	on timerTick:theTimer
		---------------- OC: LAUNCH TICK ----------------
		if ocMode and ocLaunchTick then
			set ocLaunchTick to false
			my launchOpenCoreInstall()
			return
		end if
		
		---------------- OC: WATCH MODE ----------------
		if ocMode then
			set ocTicks to ocTicks + 1
			
			set instRunning to "no"
			try
				set instRunning to do shell script "pgrep -x installer > /dev/null && echo yes || echo no"
			end try
			
			if instRunning is "no" then
				-- installer finished
				set ocMode to false
				my stopTimer()
				
				if spinner is not missing value then
					spinner's setIndeterminate:(false)
					spinner's setMinValue:(0 as real)
					spinner's setMaxValue:(100 as real)
					spinner's setDoubleValue:(100 as real)
				end if
				
				if statusField is not missing value then
					statusField's setStringValue:"OpenCore installed!"
				end if
				
				my bringToFront()
				set endAction to button returned of (display dialog "Install media created successfully
Quit OC USB MEDIA then 
Install OpenCore Package on USB Drive 
to make it bootable." with icon note buttons {"Done"} default button "Done" giving up after 50)
			else if ocTicks > 600 then
				-- 10 min safety: stop waiting, offer manual pkg
				set ocMode to false
				my stopTimer()
				do shell script "killall installer 2>/dev/null; true"
				set pkgPath to pathToResources & "/Installer/OpenCore.pkg"
				do shell script "open " & quoted form of pkgPath
				my bringToFront()
				set endAction to button returned of (display dialog "Install media created successfully!

" & engineDisk & " is now bootable." with icon note buttons {"Done"} default button "Done" giving up after 30)
			end if
			-- still running -> spinner keeps turning
			return
		end if
		
		---------------- MEDIA MODE ----------------
		set logFile to engineLogFile
		
		set logContent to ""
		try
			set logContent to do shell script "cat " & logFile & " 2>/dev/null"
		end try
		
		if logContent contains "Install media now available" then
			my finishInstall()
			return
		end if
		if logContent contains "Done." and logContent does not contain "fail" then
			my finishInstall()
			return
		end if
		
		if logContent is not "" then
			set newProgress to 0
			
			-- MODERN: log percentages
			set newProgress to my calculateTrueProgress(logContent)
			if newProgress is 2 or newProgress is 4 then
				-- Blind window: erase done, copy not started
				set creep to engineProgress + 0.05
				if creep > 12 then set creep to 12
				set newProgress to creep
			end if
			
			if newProgress > engineProgress then
				set engineProgress to newProgress
			end if
			my setBar(engineProgress)
		end if
		
		-- Process died? -> two-tick race-safe verification
		set isRunning to do shell script "pgrep -x createinstallmedia > /dev/null && echo yes || echo no"
		if isRunning is "no" and logContent is not "" then
			if engineDeadSeen then
				
				-- Second dead tick: log is final now. Judge it.
				if logContent contains "Install media now available" or logContent contains "Done." then
					if logContent does not contain "fail" then
						my finishInstall()
						return
					end if
				end if
				
				-- Truly failed
				my stopTimer()
				if (length of logContent) > 400 then
					set logContent to text ((length of logContent) - 399) thru -1 of logContent
				end if
				my bringToFront()
				display dialog "Error: createinstallmedia failed: " & logContent with icon stop buttons {"OK"} default button "OK"
				return
			else
				set engineDeadSeen to true
			end if
		else
			set engineDeadSeen to false
		end if
	end timerTick:
	
	
	-- ============================================================
	--  MEDIA FINISHED - instant UI only, OC launch deferred
	--  to the next tick (no blocking = no beachball)
	-- ============================================================
	
	on finishInstall()
		my stopTimer()
		my setBar(100)
		
		-- REAL volume name = app name without ".app"
		set realVol to text 1 thru -5 of engineAppName
		set ocRealVol to realVol
		
		-- Spinner turns + status (instant)
		if spinner is not missing value then
			spinner's setIndeterminate:(true)
			spinner's startAnimation:me
			set animated to true
		end if
		if statusField is not missing value then
			statusField's setStringValue:"Installing OpenCore to USB..."
		end if
		
		-- Hand the installer launch to the NEXT tick
		set ocMode to true
		set ocLaunchTick to true
		set ocTicks to 0
		my startPollingTimer()
	end finishInstall
	
	
	-- ============================================================
	--  OC INSTALL - launched from its own tick (event loop alive)
	--  Cached password -> no prompt. Backgrounded, pipes closed.
	-- ============================================================
	
	on launchOpenCoreInstall()
		-- Theme icon removal (instant, tiny)
		try
			do shell script "rm -f " & quoted form of ("/Volumes/" & ocRealVol & "/.VolumeIcon.icns") password enginePass with administrator privileges
			
		end try
		
		set pkgPath to pathToResources & "/Installer/OpenCore.pkg"
		do shell script "open " & quoted form of pkgPath
	end launchOpenCoreInstall
	
	
	on stopTimer()
		if myTimer is not missing value then
			myTimer's invalidate()
			set myTimer to missing value
		end if
	end stopTimer
	
	on setBar(pct)
		if spinner is not missing value then
			spinner's setDoubleValue:(pct as real)
		end if
		if statusField is not missing value then
			statusField's setStringValue:("Installing macOS... " & ((round pct) as string) & "%")
		end if
	end setBar
	
	
	-- ---------- Progress math (MODERN only) ----------
	
	on calculateTrueProgress(logContent)
		set AppleScript's text item delimiters to ""
		
		if logContent contains "Install media now available" then return 100
		
		set erasePos to 0
		set copyPos to 0
		set bootPos to 0
		if logContent contains "Erasing disk" then set erasePos to offset of "Erasing disk" in logContent
		if logContent contains "Copying to disk:" then set copyPos to offset of "Copying to disk:" in logContent
		if logContent contains "Making disk bootable" then set bootPos to offset of "Making disk bootable" in logContent
		
		set copyFirst to (copyPos > 0 and (bootPos is 0 or copyPos < bootPos))
		
		set maxPos to erasePos
		set lastPhase to "erase"
		if copyPos > maxPos then
			set maxPos to copyPos
			set lastPhase to "copy"
		end if
		if bootPos > maxPos then
			set lastPhase to "boot"
		end if
		
		if lastPhase is "erase" then
			set erasePct to my extractLatestPercentage(logContent, "Erasing disk")
			return 2 * erasePct / 100
			
		else if lastPhase is "copy" then
			set copyPct to my extractLatestPercentage(logContent, "Copying to disk:")
			if copyFirst then
				return 2 + (95 * copyPct / 100)
			else
				return 5 + (92 * copyPct / 100)
			end if
			
		else if lastPhase is "boot" then
			if copyFirst then
				return 98
			else
				return 4
			end if
		end if
		
		return 0
	end calculateTrueProgress
	
	on extractLatestPercentage(logContent, phaseName)
		set AppleScript's text item delimiters to phaseName
		set phaseParts to text items of logContent
		set AppleScript's text item delimiters to ""
		
		if (count of phaseParts) < 2 then return 0
		
		set tailText to item -1 of phaseParts
		
		set AppleScript's text item delimiters to "%"
		set pctParts to text items of tailText
		set AppleScript's text item delimiters to ""
		
		if (count of pctParts) < 2 then return 0
		
		set pctStr to item -2 of pctParts
		
		set cleanNum to ""
		repeat with i from length of pctStr to 1 by -1
			set thisChar to character i of pctStr
			if thisChar is in "0123456789" then
				set cleanNum to thisChar & cleanNum
			else if cleanNum is not "" then
				exit repeat
			end if
		end repeat
		
		try
			return cleanNum as integer
		on error
			return 0
		end try
	end extractLatestPercentage
	
end script
