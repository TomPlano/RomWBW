;
;==================================================================================================
;   SBC STANDARD CONFIGURATION
;==================================================================================================
;
; THE COMPLETE SET OF DEFAULT CONFIGURATION SETTINGS FOR THIS PLATFORM ARE FOUND IN THE
; CFG_<PLT>.ASM INCLUDED FILE WHICH IS FOUND IN THE PARENT DIRECTORY.  THIS FILE CONTAINS
; COMMON CONFIGURATION SETTINGS THAT OVERRIDE THE DEFAULTS.  IT IS INTENDED THAT YOU MAKE
; YOUR CUSTOMIZATIONS IN THIS FILE AND JUST INHERIT ALL OTHER SETTINGS FROM THE DEFAULTS.
; EVEN BETTER, YOU CAN MAKE A COPY OF THIS FILE WITH A NAME LIKE <PLT>_XXX.ASM AND SPECIFY
; YOUR FILE IN THE BUILD PROCESS.
;
; THE SETTINGS BELOW ARE THE SETTINGS THAT ARE MOST COMMONLY MODIFIED FOR THIS PLATFORM.
; MANY OF THEM ARE EQUAL TO THE SETTINGS IN THE INCLUDED FILE, SO THEY DON'T REALLY DO
; ANYTHING AS IS.  THEY ARE LISTED HERE TO MAKE IT EASY FOR YOU TO ADJUST THE MOST COMMON
; SETTINGS.
;
; N.B., SINCE THE SETTINGS BELOW ARE REDEFINING VALUES ALREADY SET IN THE INCLUDED FILE,
; TASM INSISTS THAT YOU USE THE .SET OPERATOR AND NOT THE .EQU OPERATOR BELOW. ATTEMPTING
; TO REDEFINE A VALUE WITH .EQU BELOW WILL CAUSE TASM ERRORS!
;
; PLEASE REFER TO THE CUSTOM BUILD INSTRUCTIONS (README.TXT) IN THE SOURCE DIRECTORY (TWO
; DIRECTORIES ABOVE THIS ONE).
;
#DEFINE	BOOT_DEFAULT	"H"		; DEFAULT BOOT LOADER CMD ON <CR> OR AUTO BOOT
;
#include "cfg_sbc.asm"
;
CPUOSC		.SET	8000000		; CPU OSC FREQ IN MHZ
INTMODE		.SET	0		; INTERRUPTS: 0=NONE, 1=MODE 1, 2=MODE 2
CRTACT		.SET	FALSE		; ACTIVATE CRT (VDU,CVDU,PROPIO,ETC) AT STARTUP
;
UARTENABLE	.SET	TRUE		; UART: ENABLE 8250/16550-LIKE SERIAL DRIVER (UART.ASM)
SIOENABLE	.SET	TRUE		; SIO: ENABLE ZILOG SIO SERIAL DRIVER (SIO.ASM)
;
TMSENABLE	.SET	FALSE		; TMS: ENABLE TMS9918 VIDEO/KBD DRIVER (TMS.ASM)
VDUENABLE	.SET	FALSE		; VDU: ENABLE VDU VIDEO/KBD DRIVER (VDU.ASM)
CVDUENABLE	.SET	TRUE		; CVDU: ENABLE CVDU VIDEO/KBD DRIVER (CVDU.ASM)
VGAENABLE	.SET	TRUE		; VGA: ENABLE VGA VIDEO/KBD DRIVER (VGA.ASM)
VDAEMU_SERKBD	.SET	0		; VDA EMULATION: SERIAL KBD UNIT #, OR $FF FOR HW KBD
;
FDENABLE	.SET	TRUE		; FD: ENABLE FLOPPY DISK DRIVER (FD.ASM)
FDMODE		.SET	FDMODE_DIO3	; FD: DRIVER MODE: FDMODE_[DIO|ZETA|ZETA2|DIDE|N8|DIO3|RCSMC|RCWDC|DYNO|EPFDC]
;
IDEENABLE	.SET	FALSE		; IDE: ENABLE IDE DISK DRIVER (IDE.ASM)
PPIDEENABLE	.SET	TRUE		; PPIDE: ENABLE PARALLEL PORT IDE DISK DRIVER (PPIDE.ASM)
SDENABLE	.SET	FALSE		; SD: ENABLE SD CARD DISK DRIVER (SD.ASM)
SDMODE		.SET	SDMODE_PPI	; SD: DRIVER MODE: SDMODE_[JUHA|N8|CSIO|PPI|UART|DSD|MK4|SC]
;
PRPENABLE	.SET	TRUE		; PRP: ENABLE ECB PROPELLER IO BOARD DRIVER (PRP.ASM)
