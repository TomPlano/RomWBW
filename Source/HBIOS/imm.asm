;
;=============================================================================
;   IMM DISK DRIVER
;=============================================================================
;
; PARALLEL PORT INTERFACE FOR SCSI DISK DEVICES USING A PARALLEL PORT
; ADAPTER.  PRIMARILY TARGETS PARALLEL PORT IOMEGA ZIP DRIVES.
;
; INTENDED TO CO-EXIST WITH LPT DRIVER.
;
; CREATED BY WAYNE WARTHEN FOR ROMWBW HBIOS.
; MUCH OF THE CODE IS DERIVED FROM FUZIX (ALAN COX).
;
; 5/23/2023 WBW - INITIAL RELEASE
; 5/26/2023 WBW - CLEAN UP, LED ACTIVITY
; 5/27/2023 WBW - ADDED SPP MODE
;
;=============================================================================
;
;  IBM PC STANDARD PARALLEL PORT (SPP):
;  - NHYODYNE PRINT MODULE
;
;  PORT 0 (OUTPUT):
;
;	D7	D6	D5	D4	D3	D2	D1	D0
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;     | PD7   | PD6   | PD5   | PD4   | PD3   | PD2   | PD1   | PD0   |
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;
;  PORT 1 (INPUT):
;
;	D7	D6	D5	D4	D3	D2	D1	D0
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;     | /BUSY | /ACK  | POUT  | SEL   | /ERR  | 0     | 0     | 0     |
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;
;  PORT 2 (OUTPUT):
;
;	D7	D6	D5	D4	D3	D2	D1	D0
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;     | STAT1 | STAT0 | ENBL  | PINT  | SEL   | RES   | LF    | STB   |
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;
;=============================================================================
;
;  MG014 STYLE INTERFACE:
;  - RCBUS MG014 MODULE
;
;  PORT 0 (OUTPUT):
;
;	D7	D6	D5	D4	D3	D2	D1	D0
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;     | PD7   | PD6   | PD5   | PD4   | PD3   | PD2   | PD1   | PD0   |
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;
;  PORT 1 (INPUT):
;
;	D7	D6	D5	D4	D3	D2	D1	D0
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;     |	      |	      |	      | /ERR  | SEL   | POUT  | BUSY  | /ACK  |
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;
;  PORT 2 (OUTPUT):
;
;	D7	D6	D5	D4	D3	D2	D1	D0
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;     | LED   |	      |	      |	      | /SEL  | /RES  | /LF   | /STB  |
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;
;=============================================================================
;
; TODO:
;
; - OPTIMIZE READ/WRITE LOOPS
;
; NOTES:
;
; - THIS DRIVER IS FOR THE ZIP DRIVE IMM INTERFACE.  IT WILL SIMPLY
;   FAIL TO EVEN RECOGNIZE A ZIP DRIVE WITH THE OLDER PPA INTERFACE.
;   THERE DOES NOT SEEM TO BE A WAY TO VISUALLY DETERMINE IF A ZIP
;   DRIVE IS PPA OR IMM.  SIGH.
;
; - THERE ARE SOME HARD CODED TIMEOUT LOOPS IN THE CODE.  THEY ARE
;   WORKING OK ON A 7 MHZ Z80.  THEY ARE LIKELY TO NEED TWEAKING ON
;   FASTER CPUS.
;
; - THIS DRIVER OPERATES PURELY IN NIBBLE MODE.  I SUSPECT IT IS
;   POSSIBLE TO USE FULL BYTE MODE (PS2 STYLE), BUT I HAVE NOT
;   ATTEMPTED IT.
;
; - RELATIVE TO ABOVE, THIS BEAST IS SLOW.  IN ADDITION TO THE
;   NIBBLE MODE READS, THE MG014 ASSIGNS SIGNALS DIFFERENTLY THAN
;   THE STANDARD IBM PARALLEL PORT WHICH NECESSITATES A BUNCH OF EXTRA
;   BIT FIDDLING ON EVERY READ.
;
; - SOME OF THE DATA TRANSFERS HAVE NO BUFFER OVERRUN CHECKS.  IT IS
;   ASSUMED SCSI DEVICES WILL SEND/REQUEST THE EXPECTED NUMBER OF BYTES.
;
; IMM PORT OFFSETS
;
IMM_IODATA	.EQU	0		; PORT A, DATA, OUT
IMM_IOSTAT	.EQU	1		; PORT B, STATUS, IN
IMM_IOCTRL	.EQU	2		; PORT C, CTRL, OUT
IMM_IOSETUP	.EQU	3		; PPI SETUP
;
; SCSI UNIT IDS
;
IMM_SELF	.EQU	7
IMM_TGT		.EQU	6
;
; IMM DEVICE STATUS
;
IMM_STOK	.EQU	0
IMM_STNOMEDIA	.EQU	-1
IMM_STCMDERR	.EQU	-2
IMM_STIOERR	.EQU	-3
IMM_STTO	.EQU	-4
IMM_STNOTSUP	.EQU	-5
;
; IMM DEVICE CONFIGURATION
;
IMM_CFGSIZ	.EQU	12		; SIZE OF CFG TBL ENTRIES
;
; PER DEVICE DATA OFFSETS IN CONFIG TABLE ENTRIES
;
IMM_DEV		.EQU	0		; OFFSET OF DEVICE NUMBER (BYTE)
IMM_MODE	.EQU	1		; OPERATION MODE: IMM MODE (BYTE)
IMM_STAT	.EQU	2		; LAST STATUS (BYTE)
IMM_IOBASE	.EQU	3		; IO BASE ADDRESS (BYTE)
IMM_MEDCAP	.EQU	4		; MEDIA CAPACITY (DWORD)
IMM_LBA		.EQU	8		; OFFSET OF LBA (DWORD)
;
; MACROS
;
#DEFINE IMM_WCTL(VAL)	LD A,VAL \ CALL IMM_WRITECTRL
#DEFINE IMM_WDATA(VAL)	LD A,VAL \ CALL IMM_WRITEDATA
;
;=============================================================================
; INITIALIZATION ENTRY POINT
;=============================================================================
;
IMM_INIT:
	LD	IY,IMM_CFG		; POINT TO START OF CONFIG TABLE
;
IMM_INIT1:
	LD	A,(IY)			; LOAD FIRST BYTE TO CHECK FOR END
	CP	$FF			; CHECK FOR END OF TABLE VALUE
	JR	NZ,IMM_INIT2		; IF NOT END OF TABLE, CONTINUE
	XOR	A			; SIGNAL SUCCESS
	RET				; AND RETURN
;
IMM_INIT2:
	CALL	NEWLINE			; FORMATTING
	PRTS("IMM:$")			; DRIVER LABEL
;
	PRTS(" IO=0x$")			; LABEL FOR IO ADDRESS
	LD	A,(IY+IMM_IOBASE)	; GET IO BASE ADDRES
	CALL	PRTHEXBYTE		; DISPLAY IT
;
	PRTS(" MODE=$")			; LABEL FOR MODE
	LD	A,(IY+IMM_MODE)		; GET MODE BITS
	LD	HL,IMM_STR_MODE_MAP
	ADD	A,A
	CALL	ADDHLA
	LD	E,(HL)
	INC	HL
	LD	D,(HL)
	CALL	WRITESTR
;
	; CHECK FOR HARDWARE PRESENCE
	CALL	IMM_DETECT		; PROBE FOR INTERFACE
	JR	Z,IMM_INIT4		; IF FOUND, CONTINUE
	CALL	PC_SPACE		; FORMATTING
	LD	DE,IMM_STR_NOHW		; NO IMM MESSAGE
	CALL	WRITESTR		; DISPLAY IT
	JR	IMM_INIT6		; SKIP CFG ENTRY
;
IMM_INIT4:
	; UPDATE DRIVER RELATIVE UNIT NUMBER IN CONFIG TABLE
	LD	A,(IMM_DEVNUM)		; GET NEXT UNIT NUM TO ASSIGN
	LD	(IY+IMM_DEV),A		; UPDATE IT
	INC	A			; BUMP TO NEXT UNIT NUM TO ASSIGN
	LD	(IMM_DEVNUM),A		; SAVE IT
;
	; ADD UNIT TO GLOBAL DISK UNIT TABLE
	LD	BC,IMM_FNTBL		; BC := FUNC TABLE ADR
	PUSH	IY			; CFG ENTRY POINTER
	POP	DE			; COPY TO DE
	CALL	DIO_ADDENT		; ADD ENTRY TO GLOBAL DISK DEV TABLE
;
	CALL	IMM_RESET		; RESET/INIT THE INTERFACE
#IF (IMMTRACE == 0)
	CALL	IMM_PRTSTAT
#ENDIF
	JR	NZ,IMM_INIT6
;
	; START PRINTING DEVICE INFO
	CALL	IMM_PRTPREFIX		; PRINT DEVICE PREFIX
;
IMM_INIT5:
	; PRINT STORAGE CAPACITY (BLOCK COUNT)
	PRTS(" BLOCKS=0x$")		; PRINT FIELD LABEL
	LD	A,IMM_MEDCAP		; OFFSET TO CAPACITY FIELD
	CALL	LDHLIYA			; HL := IY + A, REG A TRASHED
	CALL	LD32			; GET THE CAPACITY VALUE
	CALL	PRTHEX32		; PRINT HEX VALUE
;
	; PRINT STORAGE SIZE IN MB
	PRTS(" SIZE=$")			; PRINT FIELD LABEL
	LD	B,11			; 11 BIT SHIFT TO CONVERT BLOCKS --> MB
	CALL	SRL32			; RIGHT SHIFT
	CALL	PRTDEC32		; PRINT DWORD IN DECIMAL
	PRTS("MB$")			; PRINT SUFFIX
;
IMM_INIT6:
	LD	DE,IMM_CFGSIZ		; SIZE OF CFG TABLE ENTRY
	ADD	IY,DE			; BUMP POINTER
	JP	IMM_INIT1		; AND LOOP
;
;----------------------------------------------------------------------
; PROBE FOR IMM HARDWARE
;----------------------------------------------------------------------
;
; ON RETURN, ZF SET INDICATES HARDWARE FOUND
;
IMM_DETECT:
	; INITIALIZE 8255
	LD	A,(IY+IMM_IOBASE)	; BASE PORT
	ADD	A,IMM_IOSETUP		; BUMP TO SETUP PORT
	LD	C,A			; MOVE TO C FOR I/O
	LD	A,$82			; CONFIG A OUT, B IN, C OUT
	OUT	(C),A			; DO IT
	CALL	DELAY			; BRIEF DELAY FOR GOOD MEASURE
;
	; WE USE THIS SEQUENCE TO DETECT AN ACTUAL IMM DEVICE ON THE
	; PARALLEL PORT.  THE VALUES RECORDED IN THE FINAL CALL TO
	; IMM_DISCONNECT ARE USED TO CONFIRM DEVICE PRESENCE.
	; NO ACTUAL SCSI COMMANDS ARE USED.
	CALL	IMM_DISCONNECT
	CALL	IMM_CONNECT
	CALL	IMM_DISCONNECT
;
	; THE IMM_SN VALUES ARE RECORDED IN THE CPP ROUTINE USED BY
	; IMM_CONNECT/DISCONNECT.
	; EXPECTING S1=$B8, S2=$18, S3=$38
	LD	A,(IMM_S1)
	CP	$B8
	RET	NZ
	LD	A,(IMM_S2)
	CP	$18
	RET	NZ
	LD	A,(IMM_S3)
	CP	$38
	RET	NZ
;
	XOR	A
	RET
;
;=============================================================================
; DRIVER FUNCTION TABLE
;=============================================================================
;
IMM_FNTBL:
	.DW	IMM_STATUS
	.DW	IMM_RESET
	.DW	IMM_SEEK
	.DW	IMM_READ
	.DW	IMM_WRITE
	.DW	IMM_VERIFY
	.DW	IMM_FORMAT
	.DW	IMM_DEVICE
	.DW	IMM_MEDIA
	.DW	IMM_DEFMED
	.DW	IMM_CAP
	.DW	IMM_GEOM
#IF (($ - IMM_FNTBL) != (DIO_FNCNT * 2))
	.ECHO	"*** INVALID IMM FUNCTION TABLE ***\n"
#ENDIF
;
IMM_VERIFY:
IMM_FORMAT:
IMM_DEFMED:
	SYSCHKERR(ERR_NOTIMPL)		; NOT IMPLEMENTED
	RET
;
;
;
IMM_READ:
	CALL	HB_DSKREAD		; HOOK DISK READ CONTROLLER
	LD	A,SCSI_CMD_READ		; SETUP SCSI READ
	LD	(IMM_CMD_RW),A		; AND SAVE IT IN SCSI CMD
	JP	IMM_IO			; DO THE I/O
;
;
;
IMM_WRITE:
	CALL	HB_DSKWRITE		; HOOK DISK WRITE CONTROLLER
	LD	A,SCSI_CMD_WRITE	; SETUP SCSI WRITE
	LD	(IMM_CMD_RW),A		; AND SAVE IT IN SCSI CMD
	JP	IMM_IO			; DO THE I/O
;
;
;
IMM_IO:
	LD	(IMM_DSKBUF),HL		; SAVE DISK BUFFER ADDRESS
	CALL	IMM_CHKERR		; CHECK FOR ERR STATUS AND RESET IF SO
	JR	NZ,IMM_IO3		; BAIL OUT ON ERROR
;
	; SETUP LBA
	; 3 BYTES, LITTLE ENDIAN -> BIG ENDIAN
	LD	HL,IMM_CMD_RW+1		; START OF LBA FIELD IN CDB (MSB)
	LD	A,(IY+IMM_LBA+2)	; THIRD BYTE OF LBA FIELD IN CFG (MSB)
	LD	(HL),A
	INC	HL
	LD	A,(IY+IMM_LBA+1)
	LD	(HL),A
	INC	HL
	LD	A,(IY+IMM_LBA+0)
	LD	(HL),A
	INC	HL
;
	; DO SCSI IO
	LD	DE,(IMM_DSKBUF)		; DISK BUFFER TO DE
	LD	BC,512			; ONE SECTOR, 512 BYTES
	LD	HL,IMM_CMD_RW		; POINT TO READ/WRITE CMD TEMPLATE
	CALL	IMM_RUNCMD		; RUN THE SCSI ENGINE
	CALL	Z,IMM_CHKCMD		; IF EXIT OK, CHECK SCSI RESULTS
	JR	NZ,IMM_IO2		; IF ERROR, SKIP INCREMENT
	; INCREMENT LBA
	LD	A,IMM_LBA		; LBA OFFSET
	CALL	LDHLIYA			; HL := IY + A, REG A TRASHED
	CALL	INC32HL			; INCREMENT THE VALUE
	; INCREMENT DMA
	LD	HL,IMM_DSKBUF+1		; POINT TO MSB OF BUFFER ADR
	INC	(HL)			; BUMP DMA BY
	INC	(HL)			; ... 512 BYTES
	XOR	A			; SIGNAL SUCCESS
;
IMM_IO2:
IMM_IO3:
	LD	HL,(IMM_DSKBUF)		; CURRENT DMA TO HL
	OR	A			; SET FLAGS BASED ON RETURN CODE
	RET	Z			; RETURN IF SUCCESS
	LD	A,ERR_IO		; SIGNAL IO ERROR
	OR	A			; SET FLAGS
	RET				; AND DONE
;
;
;
IMM_STATUS:
	; RETURN UNIT STATUS
	LD	A,(IY+IMM_STAT)		; GET STATUS OF SELECTED DEVICE
	OR	A			; SET FLAGS
	RET				; AND RETURN
;
;
;
IMM_RESET:
	JP	IMM_INITDEV		; JUST (RE)INIT DEVICE
;
;
;
IMM_DEVICE:
	LD	D,DIODEV_IMM		; D := DEVICE TYPE
	LD	E,(IY+IMM_DEV)		; E := PHYSICAL DEVICE NUMBER
	LD	C,%01000000		; C := REMOVABLE HARD DISK
	LD	H,(IY+IMM_MODE)		; H := MODE
	LD	L,(IY+IMM_IOBASE)	; L := BASE I/O ADDRESS
	XOR	A			; SIGNAL SUCCESS
	RET
;
; IMM_GETMED
;
IMM_MEDIA:
	LD	A,E			; GET FLAGS
	OR	A			; SET FLAGS
	JR	Z,IMM_MEDIA1		; JUST REPORT CURRENT STATUS AND MEDIA
;
	CALL	IMM_RESET		; RESET INCLUDES MEDIA CHECK
;
IMM_MEDIA1:
	LD	A,(IY+IMM_STAT)		; GET STATUS
	OR	A			; SET FLAGS
	LD	D,0			; NO MEDIA CHANGE DETECTED
	LD	E,MID_HD		; ASSUME WE ARE OK
	RET	Z			; RETURN IF GOOD INIT
	LD	E,MID_NONE		; SIGNAL NO MEDIA
	LD	A,ERR_NOMEDIA		; NO MEDIA ERROR
	OR	A			; SET FLAGS
	RET				; AND RETURN
;
;
;
IMM_SEEK:
	BIT	7,D			; CHECK FOR LBA FLAG
	CALL	Z,HB_CHS2LBA		; CLEAR MEANS CHS, CONVERT TO LBA
	RES	7,D			; CLEAR FLAG REGARDLESS (DOES NO HARM IF ALREADY LBA)
	LD	(IY+IMM_LBA+0),L	; SAVE NEW LBA
	LD	(IY+IMM_LBA+1),H	; ...
	LD	(IY+IMM_LBA+2),E	; ...
	LD	(IY+IMM_LBA+3),D	; ...
	XOR	A			; SIGNAL SUCCESS
	RET				; AND RETURN
;
;
;
IMM_CAP:
	LD	A,(IY+IMM_STAT)		; GET STATUS
	PUSH	AF			; SAVE IT
	LD	A,IMM_MEDCAP		; OFFSET TO CAPACITY FIELD
	CALL	LDHLIYA			; HL := IY + A, REG A TRASHED
	CALL	LD32			; GET THE CURRENT CAPACITY INTO DE:HL
	LD	BC,512			; 512 BYTES PER BLOCK
	POP	AF			; RECOVER STATUS
	OR	A			; SET FLAGS
	RET
;
;
;
IMM_GEOM:
	; FOR LBA, WE SIMULATE CHS ACCESS USING 16 HEADS AND 16 SECTORS
	; RETURN HS:CC -> DE:HL, SET HIGH BIT OF D TO INDICATE LBA CAPABLE
	CALL	IMM_CAP			; GET TOTAL BLOCKS IN DE:HL, BLOCK SIZE TO BC
	LD	L,H			; DIVIDE BY 256 FOR # TRACKS
	LD	H,E			; ... HIGH BYTE DISCARDED, RESULT IN HL
	LD	D,16 | $80		; HEADS / CYL = 16, SET LBA CAPABILITY BIT
	LD	E,16			; SECTORS / TRACK = 16
	RET				; DONE, A STILL HAS IMM_CAP STATUS
;
;=============================================================================
; FUNCTION SUPPORT ROUTINES
;=============================================================================
;
; OUTPUT BYTE IN A TO THE DATA PORT
;
IMM_WRITEDATA:
	LD	C,(IY+IMM_IOBASE)	; DATA PORT IS AT IOBASE
	OUT	(C),A			; WRITE THE BYTE
	;CALL	DELAY			; IS THIS NEEDED???
	RET				; DONE
;
;
;
IMM_WRITECTRL:
	; IBM PC INVERTS ALL BUT C2 ON THE BUS, MG014 DOES NOT.
	; BELOW TRANSLATES FROM IBM -> MG014.	IT ALSO INVERTS THE
	; MG014 LED SIMPLY TO MAKE IT EASY TO KEEP LED ON DURING
	; ALL ACTIVITY.
;
#IF (IMMMODE == IMMMODE_MG014
	XOR	$0B | $80		; HIGH BIT IS MG014 LED
#ENDIF
;#IF (IMMMODE == IMMMODE_SPP
;	AND	%00001111
;	OR	%11000000
;#ENDIF
	LD	C,(IY+IMM_IOBASE)	; GET BASE IO ADDRESS
	INC	C			; BUMP TO CONTROL PORT
	INC	C
	OUT	(C),A			; WRITE TO CONTROL PORT
	;CALL	DELAY			; IS THIS NEEDED?
	RET				; DONE
;
; READ THE PARALLEL PORT INPUT LINES (STATUS) AND MAP SIGNALS FROM
; MG014 TO IBM STANDARD.  NOTE POLARITY CHANGE REQUIRED FOR BUSY.
;
; 	MG014		IBM PC (SPP)
;	--------	--------
;	0: /ACK		6: /ACK
;	1: BUSY		7: /BUSY
;	2: POUT		5: POUT
;	3: SEL		4: SEL
;	4: /ERR		3: /ERR
;
IMM_READSTATUS:
	LD	C,(IY+IMM_IOBASE)	; IOBASE TO C
	INC	C			; BUMP TO STATUS PORT
	IN	A,(C)			; READ IT
;
#IF (IMMMODE == IMMMODE_MG014)
;
	; SHUFFLE BITS ON MG014
	LD	C,0			; INIT RESULT
	BIT	0,A			; 0: /ACK
	JR	Z,IMM_READSTATUS1
	SET	6,C			; 6: /ACK
IMM_READSTATUS1:
	BIT	1,A			; 1: BUSY
	JR	NZ,IMM_READSTATUS2	; POLARITY CHANGE!
	SET	7,C			; 7: /BUSY
IMM_READSTATUS2:
	BIT	2,A			; 2: POUT
	JR	Z,IMM_READSTATUS3
	SET	5,C			; 5: POUT
IMM_READSTATUS3:
	BIT	3,A			; 3: SEL
	JR	Z,IMM_READSTATUS4
	SET	4,C			; 4: SEL
IMM_READSTATUS4:
	BIT	4,A			; 4: /ERR
	JR	Z,IMM_READSTATUS5
	SET	3,C			; 3: /ERR
IMM_READSTATUS5:
	LD	A,C			; RESULT TO A
;
#ENDIF
;
	RET
;
; SIGNAL SEQUENCE TO CONNECT/DISCONNECT
; VALUE IN A IS WRITTEN TO DATA PORT DURING SEQUENCE
;
IMM_CPP:
	PUSH	AF
	IMM_WCTL($0C)
	IMM_WDATA($AA)
	IMM_WDATA($55)
	IMM_WDATA($00)
	IMM_WDATA($FF)
	CALL	IMM_READSTATUS
	AND	$B8
	LD	(IMM_S1),A
	IMM_WDATA($87)
	CALL	IMM_READSTATUS
	AND	$B8
	LD	(IMM_S2),A
	IMM_WDATA($78)
	CALL	IMM_READSTATUS
	AND	$38
	LD	(IMM_S3),A
	POP	AF
	CALL	IMM_WRITEDATA
	IMM_WCTL($0C)
	IMM_WCTL($0D)
	IMM_WCTL($0C)
	IMM_WDATA($FF)
;
	; CONNECT: S1=$B8 S2=$18 S3=$30
	; DISCONNECT: S1=$B8 S2=$18 S3=$38
;
#IF (IMMTRACE >= 3)
	PRTS("\r\nCPP: S1=$")
	LD	A,(IMM_S1)
	CALL	PRTHEXBYTE
	PRTS(" S2=$")
	LD	A,(IMM_S2)
	CALL	PRTHEXBYTE
	PRTS(" S3=$")
	LD	A,(IMM_S3)
	CALL	PRTHEXBYTE
#ENDIF
;
	XOR	A		; ASSUME SUCCESS FOR NOW
	RET
;
IMM_S1	.DB	0
IMM_S2	.DB	0
IMM_S3	.DB	0
;
; SEQUENCE TO CONNECT TO DEVICE ON PARALLEL PORT BUS.
;
IMM_CONNECT:
	LD	A,$E0
	CALL	IMM_CPP
	LD	A,$30
	CALL	IMM_CPP
	LD	A,$E0
	CALL	IMM_CPP
	RET
;
; SEQUENCE TO DISCONNECT FROM DEVICE ON PARALLEL PORT BUS.
; THE FINAL IMM_WRITECTRL IS ONLY TO TURN OFF THE MG014 STATUS LED.
;
IMM_DISCONNECT:
	LD	A,$30
	CALL	IMM_CPP
;
	; TURNS OFF MG014 LED
	IMM_WCTL($8C)
;
	RET
;
; INITIATE A SCSI BUS RESET.
;
IMM_RESETPULSE:
	IMM_WCTL($04)
	IMM_WDATA($40)
	CALL	DELAY		; 16 US, IDEALLY, 1 US
	IMM_WCTL($0C)
	IMM_WCTL($0D)
	CALL	DELAY		; 48 US, IDEALLY, 50 US
	CALL	DELAY
	CALL	DELAY
	IMM_WCTL($0C)
	IMM_WCTL($04)
	RET
;
; SCSI SELECT PROCESS
;
IMM_SELECT:
#IF (IMMTRACE >= 3)
	PRTS("\r\nSELECT: $")
#ENDIF
	IMM_WCTL($0C)
;
	LD	HL,500			; TIMEOUT COUNTER
;
IMM_SELECT1:
	CALL	IMM_READSTATUS
	AND	$08
	JR	Z,IMM_SELECT2		; IF CLEAR, MOVE ON
	DEC	HL
	LD	A,H
	OR	L
	JP	Z,IMM_CMD_TIMEOUT	; TIMEOUT
	JR	IMM_SELECT1
;
IMM_SELECT2:
	IMM_WCTL($04)
	; PLACE HOST AND TARGET BIT ON DATA BUS
	LD	A,$80 | (1 << IMM_TGT)
	CALL	IMM_WRITEDATA
	CALL	DELAY			; CONFIRM DELAY TIME?
	IMM_WCTL($0C)
;
#IF (IMMTRACE >= 3)
	CALL	IMM_READSTATUS
	CALL	PC_SPACE
	CALL	PRTHEXBYTE
#ENDIF
;
	IMM_WCTL($0D)
;
#IF (IMMTRACE >= 3)
	CALL	IMM_READSTATUS
	CALL	PC_SPACE
	CALL	PRTHEXBYTE
#ENDIF
;
	LD	HL,500			; TIMEOUT COUNTER
;
IMM_SELECT3:
	CALL	IMM_READSTATUS
#IF (IMMTRACE >= 3)
	CALL	PC_SPACE
	CALL	PRTHEXBYTE
#ENDIF
	AND	$08
	JR	NZ,IMM_SELECT4		; IF SET, MOVE ON
	DEC	HL
	LD	A,H
	OR	L
	JP	Z,IMM_CMD_TIMEOUT	; TIMEOUT
	JR	IMM_SELECT3
;
IMM_SELECT4:
	IMM_WCTL($0C)
;
	XOR	A
	RET
;
; SEND SCSI CMD BYTE STRING.  AT ENTRY, HL POINTS TO START OF
; COMMAND BYTES.  THE LENGTH OF THE COMMAND STRING MUST PRECEED
; THE COMMAND BYTES (HL - 1).
;
; NOTE THAT DATA IS SENT AS BYTE PAIRS!  EACH LOOP SENDS 2 BYTES.
; DATA OUTPOUT IS BURSTED (NO CHECK FOR BUSY).  SEEMS TO WORK FINE.
;
IMM_SENDCMD:
;
#IF (IMMTRACE >= 3)
	PRTS("\r\nSENDCMD:$")
#ENDIF
;
	DEC	HL		; BACKUP TO LENGTH BYTE
	LD	B,(HL)		; PUT IN B FOR LOOP COUNTER
;
#IF (IMMTRACE >= 3)
	LD	A,B
	CALL	PC_SPACE
	CALL	PRTHEXBYTE
	PRTS(" BYTES$")
#ENDIF
;
	INC	HL		; BACK TO FIRST CMD BYTE
IMM_SENDCMD1:
	IMM_WCTL($04)
	LD	A,(HL)		; LOAD CMD BYTE
;
#IF (IMMTRACE >= 3)
	CALL	PC_SPACE
	CALL	PRTHEXBYTE
#ENDIF
;
	CALL	IMM_WRITEDATA	; PUT IT ON THE BUS
	INC	HL		; BUMP TO NEXT BYTE
	DEC	B		; DEC LOOP COUNTER
	IMM_WCTL($05)
	LD	A,(HL)		; LOAD CMD BYTE
;
#IF (IMMTRACE >= 3)
	CALL	PC_SPACE
	CALL	PRTHEXBYTE
#ENDIF
;
	CALL	IMM_WRITEDATA	; PUT IT ON THE BUS
	INC	HL		; BUMP TO NEXT BYTE
	IMM_WCTL($00)
	DJNZ	IMM_SENDCMD1	; LOOP TILL DONE
;
IMM_SENDCMD2:
	IMM_WCTL($04)
;
	RET
;
; WAIT FOR SCSI BUS TO BECOME READY WITH A TIMEOUT.
;
IMM_WAITLOOP:
	CALL	IMM_READSTATUS
	BIT	7,A
	RET	NZ			; DONE, STATUS IN A
	DEC	HL
	LD	A,H
	OR	L
	RET	Z			; TIMEOUT
	JR	IMM_WAITLOOP
;
IMM_WAIT:
	LD	HL,500			; GOOD VALUE???
	IMM_WCTL($0C)
	CALL	IMM_WAITLOOP
	JP	Z,IMM_CMD_TIMEOUT	; HANDLE TIMEOUT
	PUSH	AF
	IMM_WCTL($04)
	POP	AF
	AND	$B8
	RET				; RETURN W/ RESULT IN A
;
; MAX OBSERVED IMM_WAITLOOP ITERATIONS IS $0116B3
;
IMM_LONGWAIT:
	LD	B,3			; VALUE???
	IMM_WCTL($0C)
IMM_LONGWAIT1:
	LD	HL,0
	CALL	IMM_WAITLOOP
	JR	NZ,IMM_LONGWAIT2	; HANDLE SUCCESS
	DJNZ	IMM_LONGWAIT1		; LOOP TILL COUNTER EXHAUSTED
	JP	IMM_CMD_TIMEOUT		; HANDLE TIMEOUT
;
IMM_LONGWAIT2:
	PUSH	AF
	IMM_WCTL($04)
;
#IF 0
	CALL	PC_GT
	LD	A,B
	CALL	PRTHEXBYTE
	CALL	PC_COLON
	CALL	PRTHEXWORDHL
#ENDIF
;
	POP	AF
	AND	$B8
	RET				; RETURN W/ RESULT IN A
;
; PEROFRM SCSI BUS NEGOTIATION.  REQURIED PRIOR TO DATA READS.
;
IMM_NEGOTIATE:
#IF (IMMTRACE >= 3)
	PRTS("\r\nNEGO: $")
#ENDIF
	IMM_WCTL($04)
	CALL	DELAY			; 16 US, IDEALLY 5 US
	IMM_WDATA($00)
	LD	DE,7			; 112 US, IDEALLY 100 US
	CALL	VDELAY
	IMM_WCTL($06)
	CALL	DELAY			; 16 US, IDEALLY 5 US
	CALL	IMM_READSTATUS
	PUSH	AF			; SAVE RESULT
	CALL	DELAY			; 16 US, IDEALLY 5 US
	IMM_WCTL($07)
	CALL	DELAY			; 16 US, IDEALLY 5 US
	IMM_WCTL($06)
;
	POP	AF
;
#IF (IMMTRACE >= 3)
	CALL	PC_SPACE
	CALL	PRTHEXBYTE
#ENDIF
;
	AND	$20
;
#IF (IMMTRACE >= 3)
	CALL	PC_SPACE
	CALL	PC_GT
	CALL	PRTHEXBYTE
#ENDIF
;
	CP	$20			; $20 MEANS DATA READY
	JP	NZ,IMM_CMD_IOERR
	RET
;
; GET A BYTE OF DATA FROM THE SCSI DEVICE.  THIS IS A NIBBLE READ.
; BYTE RETURNED IN A.
;
IMM_GETBYTE:
	CALL	IMM_WAIT
	IMM_WCTL($06)
	CALL	IMM_READSTATUS
	AND	$F0
	RRCA
	RRCA
	RRCA
	RRCA
	PUSH 	AF
	IMM_WCTL($05)
	CALL	IMM_READSTATUS
	AND	$F0
	POP	HL
	OR	H
	PUSH	AF
	IMM_WCTL($04)
	POP	AF
	RET
;
; GET A CHUNK OF DATA FROM SCSI BUS.  THIS IS SPECIFICALLY FOR
; READ PHASE.  IF A LENGTH IS SPECIFIED (NON-ZERO HL), THEN THE
; DATA IS BURST READ.  IF NO LENGTH SPECIFIED, DATA IS READ AS
; LONG AS SCSI DEVICE WANTS TO CONTINUE SENDING (NO OVERRUN
; CHECK IN THIS CASE).
;
; THIS IS A NIBBLE READ.
;
; DE=BUFFER
; HL=LENGTH (0 FOR VARIABLE)
;
IMM_GETDATA:
	; BRANCH TO CORRECT ROUTINE
	LD	A,H
	OR	L			; IF ZERO
	JR	NZ,IMM_GETDATALEN	; DO BURST READ
;
#IF (IMMTRACE >= 3)
	PRTS("\r\nGETDATA:$")
#ENDIF
;
IMM_GETDATA1:
	PUSH	HL			; SAVE BYTE COUNTER
	CALL	IMM_WAIT		; WAIT FOR BUS READY
	POP	HL			; RESTORE BYTE COUNTER
	CP	$98			; CHECK FOR READ PHASE
	JR	NZ,IMM_GETDATA2		; IF NOT, ASSUME WE ARE DONE
	IMM_WCTL($04)
	IMM_WCTL($06)
	CALL	IMM_READSTATUS		; GET FIRST NIBBLE
	AND	$F0			; ISOLATE BITS
	RRCA				; AND SHIFT TO LOW NIBBLE
	RRCA
	RRCA
	RRCA
	PUSH 	AF			; SAVE WORKING VALUE
	IMM_WCTL($05)
	CALL	IMM_READSTATUS		; GET SECOND NIBBLE
	AND	$F0			; ISOLATE BITS
	POP	BC			; RECOVER LOW NIBBLE
	OR	B			; COMBINE
	LD	(DE),A			; AND SAVE THE FULL BYTE VALUE
	INC	DE			; NEXT BUFFER POS
	INC	HL			; INCREMENT BYTES COUNTER
	IMM_WCTL($04)
	IMM_WCTL($0C)
	JR	IMM_GETDATA1		; LOOP TILL DONE
;
IMM_GETDATA2:
;
#IF (IMMTRACE >= 3)
	CALL	PC_SPACE
	CALL	PRTHEXWORDHL
	PRTS(" BYTES$")
#ENDIF
;
	RET
;
IMM_GETDATALEN:
;
#IF (IMMTRACE >= 3)
	PRTS("\r\nGETDLEN:$")
	CALL	PC_SPACE
	CALL	PRTHEXWORDHL
	PRTS(" BYTES$")
#ENDIF
;
	IMM_WCTL($04)
IMM_GETDATALEN1:
	IMM_WCTL($06)
	CALL	IMM_READSTATUS		; GET FIRST NIBBLE
	AND	$F0			; ISOLATE BITS
	RRCA				; MOVE TO LOW NIBBLE
	RRCA
	RRCA
	RRCA
	PUSH 	AF			; SAVE WORKING VALUE
	IMM_WCTL($05)
	CALL	IMM_READSTATUS		; GET SECOND NIBBLE
	AND	$F0			; ISOLATE BITS
	POP	BC			; RECOVER FIRST NIBBLE
	OR	B			; COMBINE
	LD	(DE),A			; SAVE FINAL BYTE VALUE
	INC	DE			; NEXT BUFFER POS
	DEC	HL			; DEC LOOP COUNTER
	IMM_WCTL($04)
	LD	A,H			; CHECK LOOP COUNTER
	OR	L
	JR	NZ,IMM_GETDATALEN1	; LOOP IF NOT DONE
	IMM_WCTL($0C)
	RET
;
; PUT A CHUNK OF DATA TO THE SCSI BUS.  THIS IS SPECIFICALLY FOR
; WRITE PHASE.  IF A LENGTH IS SPECIFIED (NON-ZERO HL), THEN THE
; DATA IS BURST WRITTEN.  IF NO LENGTH SPECIFIED, DATA IS WRITTEN AS
; LONG AS SCSI DEVICE WANTS TO CONTINUE RECEIVING (NO OVERRUN
; CHECK IN THIS CASE).
;
; READS ARE DONE AS BYTE PAIRS.  EACH LOOP READS 2 BYTES.
;
; DE=BUFFER
; HL=LENGTH (0 FOR VARIABLE)
;
IMM_PUTDATA:
	LD	A,H
	OR	L
	JR	NZ,IMM_PUTDATALEN
;
#IF (IMMTRACE >= 3)
	PRTS("\r\nPUTDATA:$")
#ENDIF
;
IMM_PUTDATA1:
	PUSH	HL			; SAVE BYTE COUNTER
	CALL	IMM_WAIT		; WAIT FOR BUS READY
	POP	HL			; RESTORE BYTE COUNTER
	CP	$88			; CHECK FOR WRITE PHASE
	JR	NZ,IMM_PUTDATA2		; IF NOT, ASSUME WE ARE DONE
	IMM_WCTL($04)
	LD	A,(DE)			; GET NEXT BYTE TO WRITE (FIRST OF PAIR)
	CALL	IMM_WRITEDATA		; PUT ON BUS
	INC	DE			; BUMP TO NEXT BUF POS
	INC	HL			; INCREMENT COUNTER
	IMM_WCTL($05)
	LD	A,(DE)			; GET NEXT BYTE TO WRITE (SECOND OF PAIR)
	CALL	IMM_WRITEDATA		; PUT ON BUS
	INC	DE			; BUMP TO NEXT BUF POS
	INC	HL			; INCREMENT COUNTER
	IMM_WCTL($00)
	JR	IMM_PUTDATA1		; LOOP TILL DONE
;
IMM_PUTDATA2:
	IMM_WCTL($04)
;
#IF (IMMTRACE >= 3)
	CALL	PC_SPACE
	CALL	PRTHEXWORDHL
	PRTS(" BYTES$")
#ENDIF
;
	RET
;
IMM_PUTDATALEN:
;
#IF (IMMTRACE >= 3)
	PRTS("\r\nPUTDLEN:$")
	CALL	PC_SPACE
	CALL	PRTHEXWORDHL
	PRTS(" BYTES$")
#ENDIF
;
	IMM_WCTL($04)
IMM_PUTDATALEN1:
	LD	A,(DE)			; GET NEXT BYTE (FIRST OF PAIR)
	CALL	IMM_WRITEDATA		; PUT ON BUS
	INC	DE			; INCREMENT BUF POS
	DEC	HL			; DEC LOOP COUNTER
	IMM_WCTL($05)
	LD	A,(DE)			; GET NEXT BYTE (SECOND OF PAIR)
	CALL	IMM_WRITEDATA		; PUT ON BUS
	INC	DE			; INCREMENT BUF POS
	DEC	HL			; DEC LOOP COUNTER
	IMM_WCTL($00)
	LD	A,H			; CHECK LOOP COUNTER
	OR	L
	JR	NZ,IMM_PUTDATALEN1	; LOOP TILL DONE
	IMM_WCTL($04)
	RET
;
; READ SCSI COMMAND STATUS
;
IMM_GETSTATUS:
;
#IF (IMMTRACE >= 3)
	PRTS("\r\nSTATUS:$")
#ENDIF
;
	CALL	IMM_GETBYTE		; GET ONE BYTE
	LD	(IMM_CMDSTAT),A		; SAVE AS FIRST STATUS BYTE
;
#IF (IMMTRACE >= 3)
	CALL	PC_SPACE
	CALL	PRTHEXBYTE
#ENDIF
;
	CALL	IMM_WAIT		; CHECK FOR OPTIONAL SECOND BYTE
	CP	$B8			; STILL IN STATUS PHASE?
	RET	NZ			; IF NOT, DONE
	CALL	IMM_GETBYTE		; ELSE, GET THE SECOND BYTE
	LD	(IMM_CMDSTAT+1),A	; AND SAVE IT
;
#IF (IMMTRACE >= 3)
	CALL	PC_SPACE
	CALL	PRTHEXBYTE
#ENDIF
;
	RET
;
; TERMINATE A BULD READ OPERATION
;
IMM_ENDREAD:
	IMM_WCTL($04)
	IMM_WCTL($0C)
	IMM_WCTL($0E)
	IMM_WCTL($04)
	RET
;
; THIS IS THE MAIN SCSI ENGINE.  BASICALLY, IT SELECTS THE DEVICE
; ON THE BUS, SENDS THE COMMAND, THEN PROCESSES THE RESULT.
;
; HL: COMMAND BUFFER
; DE: TRANSFER BUFFER
; BC: TRANSFER LENGTH (0=VARIABLE)
;
IMM_RUNCMD:
	; THERE ARE MANY PLACES NESTED WITHIN THE ROUTINES THAT
	; ARE CALLED HERE.  HERE WE SAVE THE STACK SO THAT WE CAN
	; EASILY AND QUICKLY ABORT OUT OF ANY NESTED ROUTINE.
	; SEE IMM_CMD_ERR BELOW.
	LD	(IMM_CMDSTK),SP		; FOR ERROR ABORTS
	LD	(IMM_DSKBUF),DE		; SAVE BUF PTR
	LD	(IMM_XFRLEN),BC		; SAVE XFER LEN
	PUSH	HL
	CALL	IMM_CONNECT		; PARALLEL PORT BUS CONNECT
	CALL	IMM_SELECT		; SELECT TARGET DEVICE
	CALL	IMM_WAIT		; WAIT TILL READY
	POP	HL
	CALL	IMM_SENDCMD		; SEND THE COMMAND
;
IMM_RUNCMD_PHASE:
	; WAIT FOR THE BUS TO BE READY.  WE USE AN EXTRA LONG WAIT
	; TIMEOUT HERE BECAUSE THIS IS WHERE WE WILL WAIT FOR LONG
	; OPERATIONS TO COMPLETE.  IT CAN TAKE SOME TIME IF THE
	; DEVICE HAS GONE TO SLEEP BECAUSE IT WILL NEED TO WAKE UP
	; AND SPIN UP BEFORE PROCESSING AN I/O COMMAND.
	CALL	IMM_LONGWAIT		; WAIT TILL READY
;
#IF (IMMTRACE >= 3)
	PRTS("\r\nPHASE: $")
	CALL	PRTHEXBYTE
#ENDIF
;
	CP	$88			; DEVICE WANTS TO RCV DATA
	JR	Z,IMM_RUNCMD_WRITE
	CP	$98			; DEVICE WANTS TO SEND DATA
	JR	Z,IMM_RUNCMD_READ
	CP	$B8			; DEVICE WANTS TO BE DONE
	JR	Z,IMM_RUNCMD_END
	JR	IMM_CMD_IOERR
;
IMM_RUNCMD_WRITE:
	LD	DE,(IMM_DSKBUF)		; XFER BUFFER
	LD	HL,(IMM_XFRLEN)		; XFER LENGTH
	CALL	IMM_PUTDATA		; SEND DATA NOW
	JR	IMM_RUNCMD_PHASE	; BACK TO DISPATCH
;
IMM_RUNCMD_READ:
	CALL	IMM_NEGOTIATE		; NEGOTIATE FOR READ
	CALL	IMM_WAIT		; WAIT TILL READY
	; CHECK FOR STATUS $98???
	LD	DE,(IMM_DSKBUF)		; XFER BUFFER
	LD	HL,(IMM_XFRLEN)		; XFER LENGTH
	CALL	IMM_GETDATA		; GET THE DATA NOW
	CALL	IMM_ENDREAD		; TERMINATE THE READ
	JR	IMM_RUNCMD_PHASE	; BACK TO DISPATCH
;
IMM_RUNCMD_END:
	CALL	IMM_NEGOTIATE		; NEGOTIATE FOR READ (STATUS)
	CALL	IMM_WAIT		; WAIT TILL READY
	; CHECK FOR STATUS $B8???
	CALL	IMM_GETSTATUS		; READ STATUS BYTES
	CALL	IMM_ENDREAD		; TERMINATE THE READ
	CALL	IMM_DISCONNECT		; PARALLEL PORT BUS DISCONNECT
	XOR	A			; SIGNAL SUCCESS
	RET
;
IMM_CMD_IOERR:
	LD	A,IMM_STIOERR		; ERROR VALUE TO A
	JR	IMM_CMD_ERR		; CONTINUE
;
IMM_CMD_TIMEOUT:
	LD	A,IMM_STTO		; ERROR VALUE TO A
	JR	IMM_CMD_ERR		; CONTINUE
;
IMM_CMD_ERR:
	LD	SP,(IMM_CMDSTK)		; UNWIND STACK
	PUSH	AF			; SAVE STATUS
	;CALL	IMM_RESETPULSE		; CLEAN UP THE MESS???
	LD	DE,62			; DELAY AFTER RESET PULSE
	CALL	VDELAY
	CALL	IMM_DISCONNECT		; PARALLEL PORT BUS DISCONNECT
	LD	DE,62			; DELAY AFTER DISCONNECT
	CALL	VDELAY
	POP	AF			; RECOVER STATUS
	JP	IMM_ERR			; NOW DO STANDARD ERR PROCESSING
;
; ERRORS SHOULD GENERALLY NOT CAUSE SCSI PROCESSING TO FAIL.  IF A
; DEVICE ERROR (I.E., READ ERROR) OCCURS, THEN THE SCSI PROTOCOL WILL
; PROVIDE ERROR INFORMATION.  THE STATUS RESULT OF THE SCSI COMMAND
; WILL INDICATE IF AN ERROR OCCURRED.  ADDITIONALLY, IF THE ERROR IS
; A CHECK CONDITION ERROR, THEN IT IS MANDATORY TO ISSUE A SENSE
; REQUEST SCSI COMMAND TO CLEAR THE ERROR AND RETRIEVE DETAILED ERROR
; INFO.
;
IMM_CHKCMD:
	; SCSI COMMAND COMPLETED, CHECK SCSI CMD STATUS
	LD	A,(IMM_CMDSTAT)		; GET STATUS BYTE
	OR	A			; SET FLAGS
	RET	Z			; IF ZERO, ALL GOOD, DONE
;
	; DO WE HAVE A CHECK CONDITION?
	CP	2			; CHECK CONDITION RESULT?
	JR	Z,IMM_CHKCMD1		; IF SO, REQUEST SENSE
	JP	IMM_IOERR		; ELSE, GENERAL I/O ERROR
;
IMM_CHKCMD1:
	; USE REQUEST SENSE CMD TO GET ERROR DETAILS
	LD	DE,HB_WRKBUF		; PUT DATA IN WORK BUF
	LD	BC,0			; VARIABLE LENGTH REQUEST
	LD	HL,IMM_CMD_SENSE	; REQUEST SENSE CMD
	CALL	IMM_RUNCMD		; DO IT
	JP	NZ,IMM_IOERR		; BAIL IF ERROR IN CMD
;
	; REQ SENSE CMD COMPLETED
#IF (IMMTRACE >= 3)
	LD	A,16
	LD	DE,HB_WRKBUF
	CALL	Z,PRTHEXBUF
#ENDIF
;
	; CHECK SCSI CMD STATUS
	LD	A,(IMM_CMDSTAT)		; GET STATUS BYTE
	OR	A			; SET FLAGS
	JP	NZ,IMM_IOERR		; IF FAILED, GENERAL I/O ERROR
;
	; RETURN RESULT BASED ON REQ SENSE DATA
	; TODO: WE NEED TO CHECK THE SENSE KEY FIRST!!!
	LD	A,(HB_WRKBUF+12)	; GET ADDITIONAL SENSE CODE
	CP	$3A			; NO MEDIA?
	JP	Z,IMM_NOMEDIA		; IF SO, RETURN NO MEDIA ERR
	JP	IMM_IOERR		; ELSE GENERAL I/O ERR
;
; CHECK CURRENT DEVICE FOR ERROR STATUS AND ATTEMPT TO RECOVER
; VIA RESET IF DEVICE IS IN ERROR.
;
IMM_CHKERR:
	LD	A,(IY+IMM_STAT)		; GET STATUS
	OR	A			; SET FLAGS
	CALL	NZ,IMM_RESET		; IF ERROR STATUS, RESET BUS
	RET
;
; (RE)INITIALIZE DEVICE
;
IMM_INITDEV:
	; INITIALIZE 8255
	LD	A,(IY+IMM_IOBASE)	; BASE PORT
	ADD	A,IMM_IOSETUP		; BUMP TO SETUP PORT
	LD	C,A			; MOVE TO C FOR I/O
	LD	A,$82			; CONFIG A OUT, B IN, C OUT
	OUT	(C),A			; DO IT
	CALL	DELAY			; SHORT DELAY FOR BUS SETTLE
;
	CALL	IMM_DISCONNECT		; DISCONNECT FIRST JUST IN CASE
	CALL	IMM_CONNECT		; NOW CONNECT TO BUS
	CALL	IMM_RESETPULSE		; ISSUE A SCSI BUS RESET
	LD	DE,62			; WAIT A BIT
	CALL	VDELAY
	CALL	IMM_DISCONNECT		; AND DISCONNECT FROM BUS
	LD	DE,62			; WAIT A BIT MORE
	CALL	VDELAY
;
	; INITIALLY, THE DEVICE MAY REQUIRE MULTIPLE REQUEST SENSE
	; COMMANDS BEFORE IT WILL ACCEPT I/O COMMANDS.  THIS IS DUE
	; TO THINGS LIKE BUS RESET NOTIFICATION, MEDIA CHANGE, ETC.
	; HERE, WE RUN A FEW REQUEST SENSE COMMANDS.  AS SOON AS ONE
	; INDICATES NO ERRORS, WE CAN CONTINUE.
	LD	B,4			; TRY UP TO 4 TIMES
IMM_INITDEV1:
	PUSH	BC			; SAVE LOOP COUNTER
;
	; REQUEST SENSE COMMAND
	LD	DE,HB_WRKBUF		; BUFFER FOR SENSE DATA
	LD	BC,0			; READ WHATEVER IS SENT
	LD	HL,IMM_CMD_SENSE	; POINT TO CMD BUFFER
	CALL	IMM_RUNCMD		; RUN THE SCSI ENGINE
	JR	NZ,IMM_INITDEV2		; CMD PROC ERROR
;
	; CHECK CMD STATUS
	LD	A,(IMM_CMDSTAT)		; GET STATUS BYTE
	OR	A			; SET FLAGS
	JR	NZ,IMM_INITDEV2		; IF ERROR, LOOP
;
#IF (IMMTRACE >= 3)
	LD	A,16
	LD	DE,HB_WRKBUF
	CALL	PRTHEXBUF
#ENDIF
;
	; CHECK SENSE KEY
	LD	A,(HB_WRKBUF + 2)	; GET SENSE KEY
	OR	A			; SET FLAGS
;
IMM_INITDEV2:
	POP	BC			; RESTORE LOOP COUNTER
	JR	Z,IMM_INITDEV3		; IF NO ERROR, MOVE ON
	DJNZ	IMM_INITDEV1		; TRY UNTIL COUNTER EXHAUSTED
	JP	IMM_IOERR		; BAIL OUT WITH ERROR
;
IMM_INITDEV3:
	; READ & RECORD DEVICE CAPACITY
	LD	DE,HB_WRKBUF		; BUFFER TO CAPACITY RESPONSE
	LD	BC,0			; READ WHATEVER IS SENT
	LD	HL,IMM_CMD_RDCAP	; POINT TO READ CAPACITY CMD
	CALL	IMM_RUNCMD		; RUN THE SCSI ENGINE
	CALL	Z,IMM_CHKCMD		; CHECK AND RECORD ANY ERRORS
	RET	NZ			; BAIL ON ON ERROR
;
#IF (IMMTRACE >= 3)
	LD	A,8
	LD	DE,HB_WRKBUF
	CALL	PRTHEXBUF
#ENDIF
;
	; CAPACITY IS RETURNED IN A 4 BYTE, BIG ENDIAN FIELD AND
	; INDICATES THE LAST LBA VALUE.  WE NEED TO CONVERT THIS TO
	; LITTLE ENDIAN AND INCREMENT THE VALUE TO MAKE IT A CAPACITY
	; COUNT INSTEAD OF A LAST LBA VALUE.
	LD	A,IMM_MEDCAP		; OFFSET IN CFG FOR CAPACITY
	CALL	LDHLIYA			; POINTER TO HL
	PUSH	HL			; SAVE IT
	LD	HL,HB_WRKBUF		; POINT TO VALUE IN CMD RESULT
	CALL	LD32			; LOAD IT TO DE:HL
	LD	A,L			; FLIP BYTES
	LD	L,D			; ... BIG ENDIAN
	LD	D,A			; ... TO LITTLE ENDIAN
	LD	A,H
	LD	H,E
	LD	E,A
	CALL	INC32			; INCREMENT TO FINAL VALUE
	POP	BC			; RECOVER SAVE LOCATION
	CALL	ST32			; STORE VALUE
;
	XOR	A			; SIGNAL SUCCESS
	LD	(IY+IMM_STAT),A		; RECORD IT
	RET
;
;=============================================================================
; ERROR HANDLING AND DIAGNOSTICS
;=============================================================================
;
; ERROR HANDLERS
;
IMM_NOMEDIA:
	LD	A,IMM_STNOMEDIA
	JR	IMM_ERR
;
IMM_CMDERR:
	LD	A,IMM_STCMDERR
	JR	IMM_ERR
;
IMM_IOERR:
	LD	A,IMM_STIOERR
	JR	IMM_ERR
;
IMM_TO:
	LD	A,IMM_STTO
	JR	IMM_ERR
;
IMM_NOTSUP:
	LD	A,IMM_STNOTSUP
	JR	IMM_ERR
;
IMM_ERR:
	LD	(IY+IMM_STAT),A		; SAVE NEW STATUS
;
IMM_ERR2:
#IF (IMMTRACE >= 1)
	CALL	IMM_PRTSTAT
#ENDIF
	OR	A			; SET FLAGS
	RET
;
;
;
IMM_PRTERR:
	RET	Z			; DONE IF NO ERRORS
	; FALL THRU TO IMM_PRTSTAT
;
; PRINT FULL DEVICE STATUS LINE
;
IMM_PRTSTAT:
	PUSH	AF
	PUSH	DE
	PUSH	HL
	LD	A,(IY+IMM_STAT)
	CALL	IMM_PRTPREFIX		; PRINT UNIT PREFIX
	CALL	PC_SPACE		; FORMATTING
	CALL	IMM_PRTSTATSTR
	POP	HL
	POP	DE
	POP	AF
	RET
;
; PRINT STATUS STRING
;
IMM_PRTSTATSTR:
	PUSH	AF
	PUSH	DE
	PUSH	HL
	LD	A,(IY+IMM_STAT)
	NEG
	LD	HL,IMM_STR_ST_MAP
	ADD	A,A
	CALL	ADDHLA
	LD	E,(HL)
	INC	HL
	LD	D,(HL)
	CALL	WRITESTR
	POP	HL
	POP	DE
	POP	AF
	RET
;
; PRINT DEVICE/UNIT PREFIX
;
IMM_PRTPREFIX:
	PUSH	AF
	CALL	NEWLINE
	PRTS("IMM$")
	LD	A,(IY+IMM_DEV)		; GET CURRENT DEVICE NUM
	CALL	PRTDECB
	CALL	PC_COLON
	POP	AF
	RET
;
;=============================================================================
; STRING DATA
;=============================================================================
;
IMM_STR_ST_MAP:
	.DW		IMM_STR_ST_OK
	.DW		IMM_STR_ST_NOMEDIA
	.DW		IMM_STR_ST_CMDERR
	.DW		IMM_STR_ST_IOERR
	.DW		IMM_STR_ST_TO
	.DW		IMM_STR_ST_NOTSUP
;
IMM_STR_ST_OK		.TEXT	"OK$"
IMM_STR_ST_NOMEDIA	.TEXT	"NO MEDIA$"
IMM_STR_ST_CMDERR	.TEXT	"COMMAND ERROR$"
IMM_STR_ST_IOERR	.TEXT	"IO ERROR$"
IMM_STR_ST_TO		.TEXT	"TIMEOUT$"
IMM_STR_ST_NOTSUP	.TEXT	"NOT SUPPORTED$"
IMM_STR_ST_UNK		.TEXT	"UNKNOWN ERROR$"
;
IMM_STR_MODE_MAP:
	.DW	IMM_STR_MODE_NONE
	.DW	IMM_STR_MODE_SPP
	.DW	IMM_STR_MODE_MG014
;
IMM_STR_MODE_NONE	.TEXT	"NONE$"
IMM_STR_MODE_SPP	.TEXT	"SPP$"
IMM_STR_MODE_MG014	.TEXT	"MG014$"
;
IMM_STR_NOHW		.TEXT	"NOT PRESENT$"
;
;=============================================================================
; DATA STORAGE
;=============================================================================
;
IMM_DEVNUM	.DB	0		; TEMP DEVICE NUM USED DURING INIT
IMM_CMDSTK	.DW	0		; STACK PTR FOR CMD ABORTING
IMM_DSKBUF	.DW	0		; WORKING DISK BUFFER POINTER
IMM_XFRLEN	.DW	0		; WORKING TRANSFER LENGTH
IMM_CMDSTAT	.DB	0, 0		; CMD RESULT STATUS
;
; SCSI COMMAND TEMPLATES (LENGTH PREFIXED)
;
		.DB	6
IMM_CMD_RW	.DB	$00, $00, $00, $00, $01, $00	; READ/WRITE SECTOR
		.DB	6
IMM_CMD_SENSE	.DB	$03, $00, $00, $00, $FF, $00	; REQUEST SENSE DATA
		.DB	10
IMM_CMD_RDCAP	.DB	$25, $00, $00, $00, $00, $00, $00, $00, $00, $00 ; READ CAPACITY
;
; IMM DEVICE CONFIGURATION TABLE
;
IMM_CFG:
;
#IF (IMMCNT >= 1)
;
IMM0_CFG:	; DEVICE 0
	.DB	0			; DRIVER DEVICE NUMBER (FILLED DYNAMICALLY)
	.DB	IMMMODE			; DRIVER DEVICE MODE
	.DB	0			; DEVICE STATUS
	.DB	IMM0BASE		; IO BASE ADDRESS
	.DW	0,0			; DEVICE CAPACITY
	.DW	0,0			; CURRENT LBA
#ENDIF
;
#IF (IMMCNT >= 2)
;
IMM1_CFG:	; DEVICE 1
	.DB	0			; DRIVER DEVICE NUMBER (FILLED DYNAMICALLY)
	.DB	IMMMODE			; DRIVER DEVICE MODE
	.DB	0			; DEVICE STATUS
	.DB	IMM1BASE		; IO BASE ADDRESS
	.DW	0,0			; DEVICE CAPACITY
	.DW	0,0			; CURRENT LBA
#ENDIF
;
#IF ($ - IMM_CFG) != (IMMCNT * IMM_CFGSIZ)
	.ECHO	"*** INVALID IMM CONFIG TABLE ***\n"
#ENDIF
;
	.DB	$FF			; END MARKER