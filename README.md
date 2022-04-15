# azure-homeworks

## vm-ops

After applying terraform file there are several manual tasks to complete:

1. Get Azure File Share connection script for '/attached' share (PowerShell) and upload it to '/vm-custom-scripts' storage container
2. Remove installed VM extension (to avoid conflict for CustomScript extension after terraform's IIS script)
3. Add custom script VM extension with .ps1 file and confirm deployment
