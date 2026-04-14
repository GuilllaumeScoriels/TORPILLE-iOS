Build cleanup applied:
- removed Xcode user-specific workspace data (xcuserdata)
- removed saved UI state (UserInterfaceState.xcuserstate)
- removed local Firebase hosting cache

If Xcode still shows CreateBuildDescription / unable to write manifest:
1. Quit Xcode
2. Delete DerivedData for TorpilleIOS
3. Reopen the project
4. File > Packages > Reset Package Caches
5. Build again
