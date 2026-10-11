# 1. Dry run: only lists the dead entries, changes nothing
powershell -ExecutionPolicy Bypass -File .\<file-name>.ps1

# 2. Remove them, asking y/N for each one
powershell -ExecutionPolicy Bypass -File .\<file-name> -Remove

# 3. Remove all of them without prompting
powershell -ExecutionPolicy Bypass -File .\<file-name> -Remove -Force