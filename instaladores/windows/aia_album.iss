[Setup]
AppName=AIA Album
AppVersion=1.0
AppPublisher=AIA
SetupIconFile=C:\Users\alexa\Videos\codigos\aia_album\windows\runner\resources\app_icon.ico
DefaultDirName={autopf}\AIA Album
DefaultGroupName=AIA Album
UninstallDisplayIcon={app}\aia_album.exe
OutputDir=.
OutputBaseFilename=AIA_Album_Setup_v1.8
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

[Files]
; IMPORTANT: You must run "flutter build windows --obfuscate --split-debug-info=./build/debug_info --release" before compiling this script.
Source: "C:\Users\alexa\Videos\codigos\aia_album\build\windows\x64\runner\Release\aia_album.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\Users\alexa\Videos\codigos\aia_album\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AIA Album"; Filename: "{app}\aia_album.exe"
Name: "{autodesktop}\AIA Album"; Filename: "{app}\aia_album.exe"
