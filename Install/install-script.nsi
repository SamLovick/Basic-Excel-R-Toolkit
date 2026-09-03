;
; Copyright (c) 2017-2018 Structured Data, LLC
;
; This file is part of BERT.
;
; BERT is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; BERT is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with BERT.  If not, see <http://www.gnu.org/licenses/>.
;

;--------------------------------
; BERT 2 installer, 64-bit only. Installs over an existing BERT 2
; installation without touching the user's settings: bert-config.json,
; user-stylesheet.less and the files in Documents\BERT2 are created from
; templates only when they do not exist. The console, module and startup
; directories belong to the application and are replaced.
;
;   makensis /DVERSION=<version> install-script.nsi
;
; R is not bundled. The installer looks for an installed 64-bit R in the
; registry and writes it into bert-languages.json as the default R home,
; after the bundled R-3.5.0 that older installers left behind (the add-in
; uses the last candidate that exists). BERT.R.home in bert-config.json
; overrides both.

!ifndef VERSION
  !error "version is not defined"
!endif

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "StrFunc.nsh"
${StrRep}

Unicode true

Var ExcelFlavor
Var ExcelPath
Var RHome

Icon "bert2.ico"
UninstallIcon "bert2.ico"
Name "BERT ${VERSION}"
OutFile "BERT-Installer-${VERSION}-x64.exe"
BrandingText "BERT-Installer"
InstallDir "$LOCALAPPDATA\BERT2"
InstallDirRegKey HKCU "Software\BERT2" "InstallDir"
RequestExecutionLevel user

!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN_TEXT "Open Excel and the BERT Console"
!define MUI_FINISHPAGE_RUN_PARAMETERS "/x:BERT"
!define MUI_FINISHPAGE_RUN $ExcelPath
!define MUI_ICON "bert2.ico"
!define MUI_UNICON "bert2.ico"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "license.txt"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "English"

;--------------------------------
; which Excel is installed (Win64 or Win32), and where

Function CheckExcelVersion
  StrCpy $ExcelFlavor ""
  StrCpy $ExcelPath ""
  EnumRegKey $1 HKCR "TypeLib\{00020813-0000-0000-C000-000000000046}" 0
  StrCmp $1 "" CheckExcel_end
  EnumRegKey $ExcelFlavor HKCR "TypeLib\{00020813-0000-0000-C000-000000000046}\$1\0" 0
  StrCmp $ExcelFlavor "" CheckExcel_end
  ReadRegStr $ExcelPath HKCR "TypeLib\{00020813-0000-0000-C000-000000000046}\$1\0\$ExcelFlavor" ""
CheckExcel_end:
FunctionEnd

;--------------------------------
; a BERT v1 installation is disabled (not removed), with the user's consent

Function CheckOldBERT
  StrCpy $1 ""
  SetRegView 32
  ReadRegStr $0 HKCU "Software\Microsoft\Office\Excel\Addins\BERTRibbon.Connect" "Description"
  StrCmp $0 "" CheckOldBERT_Check64
  ReadRegDWORD $0 HKCU "Software\Microsoft\Office\Excel\Addins\BERTRibbon.Connect" "LoadBehavior"
  IntCmp $0 3 +2
  Goto CheckOldBERT_Check64
  MessageBox MB_OKCANCEL|MB_ICONQUESTION "Installer found an old BERT (v1) installation.$\nOkay to disable it?" IDCANCEL CheckOldBERT_Cancel
  WriteRegDWORD HKCU "Software\Microsoft\Office\Excel\Addins\BERTRibbon.Connect" "LoadBehavior" 2
  StrCpy $1 "Disable"
CheckOldBERT_Check64:
  SetRegView 64
  ReadRegStr $0 HKCU "Software\Microsoft\Office\Excel\Addins\BERTRibbon.Connect" "Description"
  StrCmp $0 "" CheckOldBERT_End
  ReadRegDWORD $0 HKCU "Software\Microsoft\Office\Excel\Addins\BERTRibbon.Connect" "LoadBehavior"
  IntCmp $0 3 +2
  Goto CheckOldBERT_End
  MessageBox MB_OKCANCEL|MB_ICONQUESTION "Installer found an old BERT (v1) installation.$\nOkay to disable it?" IDCANCEL CheckOldBERT_Cancel
  WriteRegDWORD HKCU "Software\Microsoft\Office\Excel\Addins\BERTRibbon.Connect" "LoadBehavior" 2
  StrCpy $1 "Disable"
  Goto CheckOldBERT_End
CheckOldBERT_Cancel:
  Abort "Install canceled. Please see the BERT website for more information about upgrading."
CheckOldBERT_End:
  SetRegView default
  StrCmp $1 "" CheckOldBERT_Exit
  MessageBox MB_OK|MB_ICONINFORMATION "Your old BERT installation was disabled, but not deleted. Please see the BERT website for more information on upgrading from BERT v1."
CheckOldBERT_Exit:
FunctionEnd

;--------------------------------
; the current 64-bit R, as registered by the R installer (per user or per
; machine, under R64 for 64-bit builds, older installers under R)

Function DetectR
  StrCpy $RHome ""
  SetRegView 64
  ReadRegStr $RHome HKCU "Software\R-core\R64" "InstallPath"
  StrCmp $RHome "" 0 DetectR_check
  ReadRegStr $RHome HKLM "Software\R-core\R64" "InstallPath"
  StrCmp $RHome "" 0 DetectR_check
  ReadRegStr $RHome HKCU "Software\R-core\R" "InstallPath"
  StrCmp $RHome "" 0 DetectR_check
  ReadRegStr $RHome HKLM "Software\R-core\R" "InstallPath"
DetectR_check:
  SetRegView default
  StrCmp $RHome "" DetectR_none
  IfFileExists "$RHome\bin\x64\R.dll" DetectR_ok
DetectR_none:
  StrCpy $RHome ""
  MessageBox MB_OK|MB_ICONINFORMATION "No 64-bit R installation was found. BERT needs R 4.2 or later (https://cran.r-project.org).$\n$\nAfter installing R, either run this installer again or set BERT.R.home in bert-config.json."
DetectR_ok:
FunctionEnd

;--------------------------------
; bert-languages.json from its template, with the detected R filled in
; (backslashes doubled for JSON)

Function WriteLanguagesFile
  ${StrRep} $1 $RHome "\" "\\"
  ClearErrors
  FileOpen $2 "$INSTDIR\bert-languages.template.json" r
  FileOpen $3 "$INSTDIR\bert-languages.json" w
WriteLanguages_loop:
  FileRead $2 $4
  IfErrors WriteLanguages_end
  ${StrRep} $4 $4 "@R_HOME@" $1
  FileWrite $3 $4
  Goto WriteLanguages_loop
WriteLanguages_end:
  FileClose $3
  FileClose $2
  ClearErrors
FunctionEnd

;--------------------------------

Section "Main" SecMain

CheckExcelRunning:
  FindWindow $0 "XLMAIN"
  StrCmp $0 0 +4
  MessageBox MB_OKCANCEL|MB_ICONINFORMATION "Please close Excel before running the installer." IDCANCEL +2
  Goto CheckExcelRunning
  Abort "Install canceled"

  Call CheckExcelVersion
  StrCmp $ExcelFlavor "Win64" +3
  MessageBox MB_OK|MB_ICONSTOP "This installer is for 64-bit Excel, which was not found (found: '$ExcelFlavor')."
  Abort "Install canceled: 64-bit Excel not found"

  Call CheckOldBERT
  Call DetectR

  SetOutPath "$INSTDIR"

  ; application-owned directories are replaced outright, so nothing from an
  ; older layout is left behind
  RMDir /r "$INSTDIR\console"
  RMDir /r "$INSTDIR\module"
  RMDir /r "$INSTDIR\startup"
  File /r ..\Build\Console
  File /r ..\Build\module
  File /r ..\Build\startup

  File ..\Build\BERT64.xll
  File ..\Build\BERTRibbon2x64.dll
  File ..\Build\ControlR.exe

  ; protobuf is linked statically now; remove the DLLs an earlier build
  ; shipped, which needed the Visual C++ redistributable
  Delete "$INSTDIR\libprotobuf.dll"
  Delete "$INSTDIR\abseil_dll.dll"

  ; the language list, with the detected R filled in
  File "bert-languages.template.json"
  Call WriteLanguagesFile

  ; settings: created from the templates only when they do not exist
  File ..\Build\bert-config-template.json
  IfFileExists "$INSTDIR\bert-config.json" +2
  CopyFiles "$INSTDIR\bert-config-template.json" "$INSTDIR\bert-config.json"

  File "..\Build\user-stylesheet-template.less"
  IfFileExists "$INSTDIR\user-stylesheet.less" +2
  CopyFiles "$INSTDIR\user-stylesheet-template.less" "$INSTDIR\user-stylesheet.less"

  ExecWait 'regsvr32 /s "$INSTDIR\BERTRibbon2x64.dll"'

  WriteRegStr HKCU "Software\BERT2" "InstallDir" "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$INSTDIR\lib"

  ; examples and starter functions, only where the user has none
  SetOutPath "$INSTDIR\files"
  File ..\Examples\functions.*
  File ..\Examples\excel-scripting.r
  File ..\Examples\excel-functions.r

  CreateDirectory "$DOCUMENTS\BERT2\examples"
  CreateDirectory "$DOCUMENTS\BERT2\functions"

  IfFileExists "$DOCUMENTS\BERT2\examples\excel-scripting.r" +2
  CopyFiles "$INSTDIR\files\excel-scripting.r" "$DOCUMENTS\BERT2\examples\excel-scripting.r"
  IfFileExists "$DOCUMENTS\BERT2\functions\functions.r" +2
  CopyFiles "$INSTDIR\files\functions.r" "$DOCUMENTS\BERT2\functions\functions.r"
  IfFileExists "$DOCUMENTS\BERT2\examples\excel-functions.r" +2
  CopyFiles "$INSTDIR\files\excel-functions.r" "$DOCUMENTS\BERT2\examples\excel-functions.r"

  SetOutPath "$INSTDIR"
  File ..\Build\Welcome.md
  File "bert2.ico"

  ; an empty add-in that lets the Excel-DNA IntelliSense add-in find the
  ; function descriptions BERT writes; loading it is optional, and nothing
  ; else depends on it. see docs/FUNCTION-HELP.md

  File "BERT-IntelliSense.xlam"

  ; bundled R from installers before 2.4 (2.4 bundled R-3.5.0, which stays
  ; as a fallback for anyone who has not installed R themselves)
  RMDir /r "$INSTDIR\R-3.4.1"
  RMDir /r "$INSTDIR\R-3.4.2"
  RMDir /r "$INSTDIR\R-3.4.3"
  RMDir /r "$INSTDIR\R-3.4.4"

  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BERT2" "DisplayName" "BERT Toolkit"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BERT2" "DisplayIcon" "$\"$INSTDIR\bert2.ico$\""
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BERT2" "DisplayVersion" ${VERSION}
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BERT2" "Publisher" "Structured Data LLC"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BERT2" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BERT2" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BERT2" "NoRepair" 1
  ${GetTime} "" "L" $0 $1 $2 $3 $4 $5 $6
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BERT2" "InstallDate" "$2$1$0"

SectionEnd

;--------------------------------
; uninstall leaves the user's settings (bert-config.json, user-stylesheet.less)
; and Documents\BERT2 in place

Section "Uninstall"

UninstallCheckExcelRunning:
  FindWindow $0 "XLMAIN"
  StrCmp $0 0 +4
  MessageBox MB_OKCANCEL|MB_ICONINFORMATION "Please close Excel before running the uninstaller." IDCANCEL +2
  Goto UninstallCheckExcelRunning
  Abort "Uninstall canceled"

  RMDir /r "$INSTDIR\console"
  RMDir /r "$INSTDIR\module"
  RMDir /r "$INSTDIR\files"
  RMDir /r "$INSTDIR\startup"
  RMDir /r "$INSTDIR\R-3.4.1"
  RMDir /r "$INSTDIR\R-3.4.2"
  RMDir /r "$INSTDIR\R-3.4.3"
  RMDir /r "$INSTDIR\R-3.4.4"
  RMDir /r "$INSTDIR\R-3.5.0"
  RMDir /r "$APPDATA\bert2-console"

  ExecWait 'regsvr32 /s /u "$INSTDIR\BERTRibbon2x64.dll"'

  Delete "$INSTDIR\BERT64.xll"
  Delete "$INSTDIR\BERT32.xll"
  Delete "$INSTDIR\BERTRibbon2x64.dll"
  Delete "$INSTDIR\BERTRibbon2x86.dll"
  Delete "$INSTDIR\ControlR.exe"
  Delete "$INSTDIR\ControlJulia.exe"
  Delete "$INSTDIR\ControlJulia07.exe"
  Delete "$INSTDIR\libprotobuf.dll"
  Delete "$INSTDIR\abseil_dll.dll"
  Delete "$INSTDIR\bert-config-template.json"
  Delete "$INSTDIR\user-stylesheet-template.less"
  Delete "$INSTDIR\bert-languages.json"
  Delete "$INSTDIR\bert-languages.template.json"
  Delete "$INSTDIR\BERT-IntelliSense.xlam"
  Delete "$INSTDIR\BERT-IntelliSense.intellisense.xml"
  Delete "$INSTDIR\Welcome.md"
  Delete "$INSTDIR\bert2.ico"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"

  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BERT2"

SectionEnd
