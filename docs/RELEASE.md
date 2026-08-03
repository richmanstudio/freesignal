# Release process

1. Run the repository checks on Windows:

```powershell
.\tests\StaticTests.ps1
node .\tests\test_profiles.mjs
```

2. Build the portable release:

```powershell
.\Build-Release.ps1 -Version 0.1.1
```

3. Verify the generated SHA-256 file.
4. Test install, update, profile switching, emergency stop and uninstall on clean Windows 10 and Windows 11 virtual machines.
5. Scan the release archive with Microsoft Defender and at least one independent multi-engine service.
6. Publish the ZIP, checksum, source commit and full changelog together.
7. Do not bundle third-party engine binaries until all corresponding redistribution obligations have been reviewed.
