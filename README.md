# SMB Drive Mapper

A quick and dirty PowerShell script to map SMB shares from your Tailscale network to free drive letters on Windows.

---

## How to use

1. Make sure you have [Tailscale CLI](https://tailscale.com/download) installed and running.
2. Open PowerShell.
3. Run the script **with the interactive flag**:

```powershell
.\smbchack.ps1 -i
