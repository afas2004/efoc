@echo off
rem Backs up stitched vlogs to this laptop. Schedule it daily (see
rem worker/backup.py). The log goes next to the backups' settings file.
python "%~dp0backup.py" >> "%~dp0..\..\efoc-backup.log" 2>&1
