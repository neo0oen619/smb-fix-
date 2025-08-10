# Disconnect any existing SMB sessions to the target IP
net use * /delete /y | Out-Null
