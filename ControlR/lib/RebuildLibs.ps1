#=============================================
#
# Copyright (c) 2015 Structured Data, LLC.
# All rights reserved.
#
#=============================================

#=============================================
# parameters
#=============================================

# usage: .\RebuildLibs.ps1 -R <R home> -def -x64 [-ARM64] [-x86]
#
# run from a Visual Studio developer prompt (needs dumpbin and lib). -def
# regenerates the .def files from the R.dll and RGraphApp.dll exports in
# <R home>; the other switches build import libraries from those .def files.
# -ARM64 produces ARM64X libraries for the ARM64EC configuration; they are
# built from the x64 exports because R for Windows ships x64 binaries only.
# -x86 needs an R with an i386 build, which R stopped shipping in 4.2.0.

Param(	[switch]$x86,
	[switch]$x64,
	[switch]$ARM64,
	[switch]$def,
	[switch]$all,
	[String]$R
);

if( $all )
{
	$def = $TRUE;
	$x86 = $TRUE;
	$x64 = $TRUE;
};

#=============================================
# functions
#=============================================

#---------------------------------------------
# exit on error, with message
#---------------------------------------------
Function ExitOnError( $message ) {

	if( $LastExitCode -ne 0 ){
		if( $message -ne $null ){ Write-Host "$message" -foregroundcolor red ; }
		Write-Host "Exit on error: $LastExitCode`r`n" -foregroundcolor red ;
		Exit $LastExitCode;
	}
	
}

#---------------------------------------------
# create the .def file
#---------------------------------------------
Function GenerateDef( $sub, $key ) {

	Write-Host "Generating $key-bit .defs (R.dll)" -foregroundcolor yellow ;
	
	$cmd = "dumpbin /exports $r\bin\$sub\R.dll"
	Write-Host "$cmd"

	$symbols = dumpbin /exports $r\bin\$sub\R.dll | Out-String
	ExitOnError;
	
	$symbols = ($symbols -replace "(?s)^.*ordinal.*?\n", "");
	$symbols = ($symbols -replace "(?s)\n\s*Summary.*?$", "");
	$symbols = ($symbols -replace "(?m)^\s+\S+\s+\S+\s+\S+\s+", "");

	echo "LIBRARY R`nEXPORTS`n`n$symbols`n" | Out-File -encoding ASCII R$key.def
	ExitOnError;

	Write-Host "Generating $key-bit .defs (RGraphApp.dll)" -foregroundcolor yellow ;

	$symbols = dumpbin /exports $r\bin\$sub\RGraphApp.dll | Out-String
	ExitOnError;
	
	$symbols = ($symbols -replace "(?s)^.*ordinal.*?\n", "");
	$symbols = ($symbols -replace "(?s)\n\s*Summary.*?$", "");
	$symbols = ($symbols -replace "(?m)^\s+\S+\s+\S+\s+\S+\s+", "");

	$symbols = ($symbols -replace "(?m)^\(.*?\n", "");

	echo "LIBRARY RGraphApp`nEXPORTS`n`n$symbols`n" | Out-File -encoding ASCII RGraphApp$key.def
	ExitOnError;

}

#---------------------------------------------
# create the lib file from the .def
#---------------------------------------------
Function GenerateLib( $machine, $key, $suffix ){

	Write-Host "Generating $key-bit libs for $machine" -foregroundcolor yellow ;
	lib /machine:$machine /def:R$key.def /out:R$key$suffix.lib
	lib /machine:$machine /def:RGraphApp$key.def /out:RGraphApp$key$suffix.lib
	ExitOnError;

}

#=============================================
# runtime
#=============================================

Write-Host "";
if( $def ){
	if( $x86 ){ GenerateDef "i386" "32"  }
	if( $x64 -or $ARM64 ){ GenerateDef "x64" "64"  }
	Write-Host "";
}
if( $x86 ){ GenerateLib "X86" "32" "" }
if( $x64 ){ GenerateLib "X64" "64" "" }
if( $ARM64 ){ GenerateLib "ARM64X" "64" "arm" }
Write-Host "";
Write-Host "Done" -foregroundcolor green;
Write-Host "";
