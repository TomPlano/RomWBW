@echo off

setlocal

set PATH=%PATH%;..\..\..\Tools\zx;..\..\..\Tools\cpmtools;

set ZXBINDIR=../../../tools/cpm/bin/
set ZXLIBDIR=../../../tools/cpm/lib/
set ZXINCDIR=../../../tools/cpm/include/

copy ..\z3baset.lib .
zx ZMAC -zcpr33t.z80 -/P
copy zcpr33t.rel ..

copy ..\z3basen.lib .
zx ZMAC -zcpr33n.z80 -/P
copy zcpr33n.rel ..
