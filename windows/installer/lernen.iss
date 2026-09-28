; Windows-Installer für Lernen (Inno Setup 6), gebaut in
; .github/workflows/windows-app.yml:
;   iscc /DAppVersion=1.0.<build> /DSourceDir=<runner\Release> /O<Ausgabe> lernen.iss
; Eine einzige Setup-Datei statt eines Ordners voller DLLs: installiert nur
; für den aktuellen Nutzer (keine Admin-Rechte) nach
; %LOCALAPPDATA%\Programs\Lernen, legt Startmenü- und auf Wunsch
; Desktop-Verknüpfung an und lässt sich über "Apps" wieder entfernen.
; Updates installieren einfach drüber (gleiche AppId); die Lerndaten liegen
; ohnehin getrennt in %APPDATA% und bleiben erhalten.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{6F1C8E2A-4B7D-4C39-9E5A-2D8B7F3A1C64}
AppName=Lernen
AppVersion={#AppVersion}
AppVerName=Lernen {#AppVersion}
AppPublisher=Lernen
DefaultDirName={autopf}\Lernen
DisableDirPage=auto
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\build\installer
OutputBaseFilename=Lernen-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\lernen.exe
UninstallDisplayName=Lernen
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; Läuft die App noch, wird sie vor dem Kopieren geschlossen.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Assets der alten Version entfernen, bevor die neuen kommen.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Lernen"; Filename: "{app}\lernen.exe"
Name: "{autodesktop}\Lernen"; Filename: "{app}\lernen.exe"; Tasks: desktopicon

[Run]
; Ohne "skipifsilent": nach einem stillen Update aus der App heraus startet
; sie danach von selbst wieder.
Filename: "{app}\lernen.exe"; Description: "{cm:LaunchProgram,Lernen}"; Flags: nowait postinstall
