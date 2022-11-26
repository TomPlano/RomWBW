;
;==================================================================================================
; RP5C01 CLOCK DRIVER
;==================================================================================================
;
THIS_DRV		.SET	DRV_ID_RP5RTC
;
RP5RTC_BUFSIZ	.EQU	6	; SIX BYTE BUFFER (YYMMDDHHMMSS)
;
; RTC DEVICE INITIALIZATION ENTRY
;

; TODO:
; set the day of week register
; read block of nvram
; write block of nvram
; set alarm/get alarm????

;; NOTES FOR USING DRIVER IN Z-DOS
; First load the LDDS datestamper
; A:LDDS
; next prepare and drives with datestamper info:
; eg: a:putds -d=g: -V
; then view date time of files with:
; a:filedate


RP5RTC_REG	.EQU	$B4
RP5RTC_DAT	.EQU	$B5

REG_1SEC	.EQU	$00
REG_10SEC	.EQU	$01
REG_1MIN	.EQU	$02
REG_10MIN	.EQU	$03
REG_1HR		.EQU	$04
REG_10HR	.EQU	$05
REG_DAYWEEK	.EQU	$06		; NOT USED BY THIS DRIVER
REG_1DAY	.EQU	$07
REG_10DAY	.EQU	$08
REG_1MNTH	.EQU	$09
REG_10MNTH	.EQU	$0A
REG_1YEAR	.EQU	$0B
REG_10YEAR	.EQU	$0C
REG_MODE	.EQU	$0D
REG_TEST	.EQU	$0E
REG_RESET	.EQU	$0F


REG_12_24	.EQU	$0A
REG_LEAPYR	.EQU	$0B

MODE_TIMEST	.EQU	0
MODE_ALRMST	.EQU	1
MODE_RAM0	.EQU	2
MODE_RAM1	.EQU	3

MD_TIME		.EQU	8
MD_ALRM		.EQU	4

RP5RTC_INIT:
	LD	A, (RTC_DISPACT)	; RTC DISPATCHER ALREADY SET?
	OR	A			; SET FLAGS
	RET	NZ			; IF ALREADY ACTIVE, ABORT

	CALL	NEWLINE			; FORMATTING
	PRTS("RP5C01 RTC: $")

	; PRINT RTC LATCH PORT ADDRESS
	PRTS("IO=0x$")			; LABEL FOR IO ADDRESS
	LD	A,RP5RTC_REG		; GET IO ADDRESS
	CALL	PRTHEXBYTE		; PRINT IT
        CALL    PC_SPACE                ; FORMATTING

	; CHECK PRESENCE STATUS
	CALL	RP5RTC_DETECT		; HARDWARE DETECTION
	JR	Z, RP5RTC_INIT1		; IF ZERO, ALL GOOD
	PRTS("NOT PRESENT$")		; NOT ZERO, H/W NOT PRESENT
	OR	$FF			; SIGNAL FAILURE
	RET				; BAIL OUT

RP5RTC_INIT1:
;	ENSURE DEVICE IS RESET AND NOT IN TEST MODE
	LD	A, REG_TEST		; SELECT TEST REGISTER
	OUT	(RP5RTC_REG), A
	CALL	DLY16
	XOR	A
	OUT	(RP5RTC_DAT), A		; TURN OFF ALL TEST MODE BITS

	LD	B, MODE_ALRMST
	CALL	RP5RTC_SETMD

	CALL	RP5RTC_ENTIME

	LD	A, REG_12_24		; SET TO 24 HOUR CLOCK
	OUT	(RP5RTC_REG), A
	LD	A, 1
	OUT	(RP5RTC_DAT), A

	CALL	RP5RTC_RDTIM

	; DISPLAY CURRENT TIME
	LD	HL, RP5RTC_BCDBUF	; POINT TO BCD BUF
	CALL	PRTDT
;
	LD	BC, RP5RTC_DISPATCH
	CALL	RTC_SETDISP
;
	XOR	A			; SIGNAL SUCCESS
	RET
;
; DETECT RTC HARDWARE PRESENCE
;
RP5RTC_DETECT:
	LD	C, 0			; NVRAM INDEX 0
	CALL	RP5RTC_GETBYT		; GET VALUE
	LD	A, E			; TO ACCUM
	LD	L, A			; SAVE IT
	XOR	$FF			; FLIP ALL BITS
	LD	E, A			; TO E
	LD	C, 0			; NVRAM INDEX 0
	CALL	RP5RTC_SETBYT		; WRITE IT
	LD	C, 0			; NVRAM INDEX 0
	CALL	RP5RTC_GETBYT		; GET VALUE
	LD	A, L			; GET SAVED VALUE
	XOR	$FF			; FLIP ALL BITS
	CP	E			; COMPARE WITH VALUE READ
	LD	A, 0			; ASSUME OK
	JR	Z, RP5RTC_DETECT1	; IF MATCH, GO AHEAD
	LD	A, $FF			; ELSE STATUS IS ERROR

RP5RTC_DETECT1:
	PUSH	AF			; SAVE STATUS
	LD	A, L			; GET SAVED VALUE
	LD	C, 0 			; NVRAM INDEX 0
	CALL	RP5RTC_SETBYT		; SAVE IT
	POP	AF			; RECOVER STATUS
	OR	A			; SET FLAGS
	RET
;
; RTC DEVICE FUNCTION DISPATCH ENTRY
;   A: RESULT (OUT), 0=OK, Z=OK, NZ=ERR
;   B: FUNCTION (IN)
;
RP5RTC_DISPATCH:
	LD	A,B			; GET REQUESTED FUNCTION
	AND	$0F			; ISOLATE SUB-FUNCTION
	JP	Z,RP5RTC_GETTIM		; GET TIME
	DEC	A
	JP	Z,RP5RTC_SETTIM		; SET TIME
	DEC	A
	JP	Z,RP5RTC_GETBYT		; GET NVRAM BYTE VALUE
	DEC	A
	JP	Z,RP5RTC_SETBYT		; SET NVRAM BYTE VALUE
	DEC	A
	JP	Z,RP5RTC_GETBLK		; GET NVRAM DATA BLOCK VALUES
	DEC	A
	JP	Z,RP5RTC_SETBLK		; SET NVRAM DATA BLOCK VALUES
	DEC	A
	JP	Z,RP5RTC_GETALM		; GET ALARM
	DEC	A
	JP	Z,RP5RTC_SETALM		; SET ALARM
	DEC	A
	JP	Z,RP5RTC_DEVICE		; REPORT RTC DEVICE INFO
	SYSCHKERR(ERR_NOFUNC)
	RET
;
; RTC GET NVRAM BYTE
;   C: INDEX
;   E: VALUE (OUTPUT)
;   A:0 IF OK, ERR_RANGE IF OUT OF RANGE
;
RP5RTC_GETBYT:
	LD	A, C
	CP	$0D
	JR	NC, RP5RTC_BADIDX

	LD	B, MODE_RAM0
	CALL	RP5RTC_SETMD
	LD	A, C			; SELECT NVRAM INDEX
	OUT	(RP5RTC_REG), A
	IN	A, (RP5RTC_DAT)
	AND	$0F			; RETRIEVE UNIT NIBBLE
	LD	E, A

	LD	B, MODE_RAM1
	CALL	RP5RTC_SETMD
	LD	A, C			; SELECT NVRAM INDEX
	OUT	(RP5RTC_REG), A
	IN	A, (RP5RTC_DAT)
	AND	$0F			; RETRIEVE UNIT NIBBLE
	RLCA
	RLCA
	RLCA
	RLCA
	OR	E
	LD	E, A

	XOR	A			; SIGNAL SUCCESS
	RET				; AND RETURN

RP5RTC_BADIDX:
	LD	E, 00
	LD	A, ERR_RANGE
	RET
;
; RTC SET NVRAM BYTE
;   C: INDEX
;   E: VALUE
;   A:0 IF OK, ERR_RANGE IF OUT OF RANGE
;
RP5RTC_SETBYT:
	LD	A, C
	CP	$0D
	JR	NC, RP5RTC_BADIDX

	LD	B, MODE_RAM0
	CALL	RP5RTC_SETMD
	LD	A, C			; SELECT NVRAM INDEX
	OUT	(RP5RTC_REG), A
	LD	A, E
	AND	$0F
	OUT	(RP5RTC_DAT), A

	LD	B, MODE_RAM1
	CALL	RP5RTC_SETMD
	LD	A, C			; SELECT NVRAM INDEX
	OUT	(RP5RTC_REG), A
	LD	A, E
	AND	$F0
	RRCA
	RRCA
	RRCA
	RRCA
	OUT	(RP5RTC_DAT), A

	XOR	A			; SIGNAL SUCCESS
	RET				; AND RETURN

RP5RTC_GETBLK:
RP5RTC_SETBLK:
RP5RTC_GETALM:
RP5RTC_SETALM:
	SYSCHKERR(ERR_NOTIMPL)
	RET
;
; RTC GET TIME
;   A: RESULT (OUT), 0=OK, Z=OK, NZ=ERR
;   HL: DATE/TIME BUFFER (OUT)
; BUFFER FORMAT IS BCD: YYMMDDHHMMSS
; 24 HOUR TIME FORMAT IS ASSUMED
;
RP5RTC_GETTIM:
	; GET THE TIME INTO TEMP BUF
	PUSH	HL			; SAVE PTR TO CALLERS BUFFER
;
	CALL	RP5RTC_RDTIM

	; NOW COPY TO REAL DESTINATION (INTERBANK SAFE)
	LD	A,BID_BIOS		; COPY FROM BIOS BANK
	LD	(HB_SRCBNK),A		; SET IT
	LD	A,(HB_INVBNK)		; COPY TO CURRENT USER BANK
	LD	(HB_DSTBNK),A		; SET IT
	LD	HL,RP5RTC_BCDBUF	; SOURCE ADR
	POP	DE			; DEST ADR
	LD	BC,RP5RTC_BUFSIZ	; LENGTH
	CALL	HB_BNKCPY		; COPY THE CLOCK DATA

	XOR	A			; SIGNAL SUCCESS
	RET				; AND RETURN
;
;
; RTC SET TIME
;   A: RESULT (OUT), 0=OK, Z=OK, NZ=ERR
;   HL: DATE/TIME BUFFER (IN)
; BUFFER FORMAT IS BCD: YYMMDDHHMMSSWW
; 24 HOUR TIME FORMAT IS ASSUMED
;
RP5RTC_SETTIM:
	; COPY TO BCD BUF
	LD	A,(HB_INVBNK)		; COPY FROM CURRENT USER BANK
	LD	(HB_SRCBNK),A		; SET IT
	LD	A,BID_BIOS		; COPY TO BIOS BANK
	LD	(HB_DSTBNK),A		; SET IT
	LD	DE,RP5RTC_BCDBUF	; DEST ADR
	LD	BC,RP5RTC_BUFSIZ	; LENGTH
	CALL	HB_BNKCPY		; COPY THE CLOCK DATA
;
	LD	B, MODE_TIMEST
	CALL	RP5RTC_SETMD

	LD	B, REG_1SEC
	LD	A, (RP5RTC_SS)
	CALL	RP5RTC_WRVL

	LD	B, REG_1MIN
	LD	A, (RP5RTC_MM)
	CALL	RP5RTC_WRVL

	LD	B, REG_1HR
	LD	A, (RP5RTC_HH)
	CALL	RP5RTC_WRVL

	LD	B, REG_1DAY
	LD	A, (RP5RTC_DT)
	CALL	RP5RTC_WRVL

	LD	B, REG_1MNTH
	LD	A, (RP5RTC_MO)
	CALL	RP5RTC_WRVL

	LD	B, REG_1YEAR
	LD	A, (RP5RTC_YR)
	CALL	RP5RTC_WRVL

	LD	B, MODE_ALRMST
	CALL	RP5RTC_SETMD

	LD	A, (RP5RTC_YR)
	CALL	BCD2BYTE
	AND	3
	LD	B, REG_LEAPYR
	CALL	RP5RTC_WRVL

	CALL	RP5RTC_ENTIME

	XOR	A			; SIGNAL SUCCESS
	RET				; AND RETURN
;
; REPORT RTC DEVICE INFO
;
RP5RTC_DEVICE:
	LD	D,RTCDEV_RP5		; D := DEVICE TYPE
	LD	E,0			; E := PHYSICAL DEVICE NUMBER
	LD	H,0			; H := 0, DRIVER HAS NO MODES
	LD	L,0			; L := 0, NO I/O ADDRESS
	XOR	A			; SIGNAL SUCCESS
	RET

;
; READ OUT THE TIME
RP5RTC_RDTIM:
	LD	B, MODE_TIMEST
	CALL	RP5RTC_SETMD

	LD	B, REG_1SEC
	CALL	RP5RTC_RDVL
	LD	(RP5RTC_SS), A

	LD	B, REG_1MIN
	CALL	RP5RTC_RDVL
	LD	(RP5RTC_MM), A

	LD	B, REG_1HR
	CALL	RP5RTC_RDVL
	LD	(RP5RTC_HH), A

	LD	B, REG_1DAY
	CALL	RP5RTC_RDVL
	LD	(RP5RTC_DT), A

	LD	B, REG_1MNTH
	CALL	RP5RTC_RDVL
	LD	(RP5RTC_MO), A

	LD	B, REG_1YEAR
	CALL	RP5RTC_RDVL
	LD	(RP5RTC_YR), A

	RET

; SET MODE
; MODE IN B (MODE_TIMEST, MODE_ALRMST, MODE_RAM0, MODE_RAM1)
RP5RTC_SETMD:
	LD	A, REG_MODE			; SELECT MODE REGISTER
	OUT	(RP5RTC_REG), A

	IN	A, (RP5RTC_DAT)
	AND	MD_TIME | MD_ALRM
	OR	B
	OUT	(RP5RTC_DAT), A			; ASSIGN MODE
	RET

; ENABLE THE TIME COUNTER
RP5RTC_ENTIME:
	LD	B, MD_TIME
	JP	RP5RTC_SETMD

; READ OUT 2 REGISTERS - 2 NIBBLES TO 1 BYTE
; REGISTER IN B
RP5RTC_RDVL:
	LD	A, B				; SELECT UNIT REGISTER
	OUT	(RP5RTC_REG), A
	IN	A, (RP5RTC_DAT)
	AND	$0F				; RETRIEVE UNIT NIBBLE
	LD	L, A

	INC	B
	LD	A, B				; SELECT TENS REGISTER
	OUT	(RP5RTC_REG), A
	IN	A, (RP5RTC_DAT)
	AND	$0F
	RLCA
	RLCA
	RLCA
	RLCA					; MOVE TO TOP NIBBLE
	OR	L				; MERGE IN LOW NIBBLE
	LD	H, A				; A = VALUE AS BCD

	RET

; WRITE OUT 2 REGISTERS - 1 BYTE TO 2 NIBBLES
; REGISTER IN B (B+1)
; VALUE IN A
RP5RTC_WRVL:
	LD	C, A
	LD	A, B				; SELECT UNIT REGISTER
	OUT	(RP5RTC_REG), A

	LD	A, C				; WRITE C (ONLY LOW NIBBLE WILL BE USED)
	OUT	(RP5RTC_DAT), A

	INC	B
	LD	A, B				; SELECT TENS REGISTER
	OUT	(RP5RTC_REG), A

	LD	A, C				; SHIFT TOP NIBBLE TO LOW NIBBLE
	RRCA
	RRCA
	RRCA
	RRCA
	OUT	(RP5RTC_DAT), A			; WRITE IT

	RET
;
; REGISTER EXTRACTED VALUES
;
RP5RTC_BCDBUF:
RP5RTC_YR	.DB	20
RP5RTC_MO	.DB	01
RP5RTC_DT	.DB	01
RP5RTC_HH	.DB	00
RP5RTC_MM	.DB	00
RP5RTC_SS	.DB	00

