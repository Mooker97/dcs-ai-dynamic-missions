@echo off
rem Pedal rudder bridge. Double-click to run it; pass calibrate / monitor / install / uninstall.
uv run --script "%~dp0pedal_rudder.py" %*
if errorlevel 1 pause
