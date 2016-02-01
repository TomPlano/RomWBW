;
;=============================================================================
;   PPIDE DISK DRIVER
;=============================================================================
;
; TODO:
; - IMPLEMENT PPIDE_INITDEVICE
; - IMPLEMENT INTELLIGENT RESET, CHECK IF DEVICE IS ACTUALLY BROKEN BEFORE RESET
; - FIX SCALER CONSTANT
;
;
PPIDE_IO_DATALO	.EQU	PPIDEIOB + 0	; IDE DATA BUS LSB (8255 PORT A)
PPIDE_IO_DATAHI	.EQU	PPIDEIOB + 1	; IDE DATA BUS MSB (8255 PORT B)
PPIDE_IO_CTL	.EQU	PPIDEIOB + 2	; IDE ADDRESS BUS AND CONTROL SIGNALS (8255 PORT C)
PPIDE_IO_PPI	.EQU	PPIDEIOB + 3	; 8255 CONTROL PORT
;
; THE CONTROL PORT OF THE 8255 IS PROGRAMMED AS NEEDED TO READ OR WRITE
; DATA ON THE IDE BUS.  PORT C OF THE 8255 IS ALWAYS IN OUTPUT MODE BECAUSE
; IT IS DRIVING THE ADDRESS BUS AND CONTROL SIGNALS.  PORTS A & B WILL BE
; PLACED IN READ OR WRITE MODE DEPENDING ON THE DIRECTION OF THE DATA BUS.
;
PPIDE_DIR_READ	.EQU	%10010010	; IDE BUS DATA INPUT MODE
PPIDE_DIR_WRITE	.EQU	%10000000	; IDE BUS DATA OUTPUT MODE
;
; PORT C OF THE 8255 IS USED TO DRIVE THE IDE INTERFACE ADDRESS BUS
; AND VARIOUS CONTROL SIGNALS.  THE CONSTANTS BELOW REFLECT THESE
; ASSIGNMENTS.
;
PPIDE_CTL_DA0	.EQU	%00000001	; DRIVE ADDRESS BUS - BIT 0 (DA0)
PPIDE_CTL_DA1	.EQU	%00000010	; DRIVE ADDRESS BUS - BIT 1 (DA1)
PPIDE_CTL_DA2	.EQU	%00000100	; DRIVE ADDRESS BUS - BIT 2 (DA2)
PPIDE_CTL_CS1FX	.EQU	%00001000	; DRIVE CHIP SELECT 0 (ACTIVE LOW, INVERTED)
PPIDE_CTL_CS3FX	.EQU	%00010000	; DRIVE CHIP SELECT 1 (ACTIVE LOW, INVERTED)
PPIDE_CTL_DIOW	.EQU	%00100000	; DRIVE I/O WRITE (ACTIVE LOW, INVERTED)
PPIDE_CTL_DIOR	.EQU	%01000000	; DRIVE I/O READ (ACTIVE LOW, INVERTED)
PPIDE_CTL_RESET	.EQU	%10000000	; DRIVE RESET (ACTIVE LOW, INVERTED)
;
;	+-----------------------------------------------------------------------+
;	| CONTROL BLOCK REGISTERS (CS3FX)					|
;	+-----------------------+-------+-------+-------------------------------+
;	| REGISTER      	| PORT	| DIR	| DESCRIPTION                   |
;	+-----------------------+-------+-------+-------------------------------+
;	| PPIDE_REG_ALTSTAT	| 0x06	| R	| ALTERNATE STATUS REGISTER	|
;	| PPIDE_REG_CTRL	| 0x06	| W	| DEVICE CONTROL REGISTER	|
;	| PPIDE_REG_DRVADR	| 0x07	| R	| DRIVE ADDRESS REGISTER	|
;	+-----------------------+-------+-------+-------------------------------+
;
;	+-----------------------+-------+-------+-------------------------------+
;	| COMMAND BLOCK REGISTERS (CS1FX)					|
;	+-----------------------+-------+-------+-------------------------------+
;	| REGISTER      	| PORT	| DIR	| DESCRIPTION                   |
;	+-----------------------+-------+-------+-------------------------------+
;	| PPIDE_REG_DATA	| 0x00	| R/W	| DATA INPUT/OUTPUT		|
;	| PPIDE_REG_ERR		| 0x01	| R	| ERROR REGISTER		|
;	| PPIDE_REG_FEAT	| 0x01	| W	| FEATURES REGISTER		|
;	| PPIDE_REG_COUNT	| 0x02	| R/W	| SECTOR COUNT REGISTER		|
;	| PPIDE_REG_SECT	| 0x03	| R/W	| SECTOR NUMBER REGISTER	|
;	| PPIDE_REG_CYLLO	| 0x04	| R/W	| CYLINDER NUM REGISTER (LSB)	|
;	| PPIDE_REG_CYLHI	| 0x05	| R/W	| CYLINDER NUM REGISTER (MSB)	|
;	| PPIDE_REG_DRVHD	| 0x06	| R/W	| DRIVE/HEAD REGISTER		|
;	| PPIDE_REG_LBA0*	| 0x03	| R/W	| LBA BYTE 0 (BITS 0-7) 	|
;	| PPIDE_REG_LBA1*	| 0x04	| R/W	| LBA BYTE 1 (BITS 8-15)	|
;	| PPIDE_REG_LBA2*	| 0x05	| R/W	| LBA BYTE 2 (BITS 16-23)	|
;	| PPIDE_REG_LBA3*	| 0x06	| R/W	| LBA BYTE 3 (BITS 24-27)	|
;	| PPIDE_REG_STAT	| 0x07	| R	| STATUS REGISTER		|
;	| PPIDE_REG_CMD		| 0x07	| W	| COMMAND REGISTER (EXECUTE)	|
;	+-----------------------+-------+-------+-------------------------------+
;	* LBA0-4 ARE ALTERNATE DEFINITIONS OF SECT, CYL, AND DRVHD PORTS
;
;	=== STATUS REGISTER ===
;
;	    7       6       5       4       3       2       1       0
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;	|  BSY  | DRDY  |  DWF  |  DSC  |  DRQ  | CORR  |  IDX  |  ERR  |
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;
;	BSY:	BUSY
;	DRDY:	DRIVE READY
;	DWF:	DRIVE WRITE FAULT
;	DSC:	DRIVE SEEK COMPLETE
;	DRQ:	DATA REQUEST
;	CORR:	CORRECTED DATA
;	IDX:	INDEX
;	ERR:	ERROR
;
;	=== ERROR REGISTER ===
;
;	    7       6       5       4       3       2       1       0
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;	| BBK   |  UNC  |  MC   |  IDNF |  MCR  | ABRT  | TK0NF |  AMNF |
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;	(VALID WHEN ERR BIT IS SET IN STATUS REGISTER)
;
;	BBK:	BAD BLOCK DETECTED
;	UNC:	UNCORRECTABLE DATA ERROR
;	MC:	MEDIA CHANGED
;	IDNF:	ID NOT FOUND
;	MCR:	MEDIA CHANGE REQUESTED
;	ABRT:	ABORTED COMMAND
;	TK0NF:	TRACK 0 NOT FOUND
;	AMNF:	ADDRESS MARK NOT FOUND
;
;	=== DRIVE/HEAD / LBA3 REGISTER ===
;
;	    7       6       5       4       3       2       1       0
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;	|   1   |   L   |   1   |  DRV  |  HS3  |  HS2  |  HS1  |  HS0  |
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;
;	L:	0 = CHS ADDRESSING, 1 = LBA ADDRESSING
;	DRV:	0 = DRIVE 0 (PRIMARY) SELECTED, 1 = DRIVE 1 (SLAVE) SELECTED
;	HS:	CHS = HEAD ADDRESS (0-15), LBA = BITS 24-27 OF LBA
;
;	=== DEVICE CONTROL REGISTER ===
;
;	    7       6       5       4       3       2       1       0
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;	|   X   |   X   |   X   |   X   |   1   | SRST  |  ~IEN |   0   |
;	+-------+-------+-------+-------+-------+-------+-------+-------+
;
;	SRST:	SOFTWARE RESET
;	~IEN:	INTERRUPT ENABLE
;
; CONTROL VALUES TO USE WHEN ACCESSING THE VARIOUS IDE DEVICE REGISTERS
;
PPIDE_REG_DATA		.EQU	PPIDE_CTL_CS1FX | $00	; DATA INPUT/OUTPUT (R/W)
PPIDE_REG_ERR		.EQU 	PPIDE_CTL_CS1FX | $01	; ERROR REGISTER (R)
PPIDE_REG_FEAT		.EQU 	PPIDE_CTL_CS1FX | $01	; FEATURES REGISTER (W)
PPIDE_REG_COUNT		.EQU 	PPIDE_CTL_CS1FX | $02	; SECTOR COUNT REGISTER (R/W)
PPIDE_REG_SECT		.EQU 	PPIDE_CTL_CS1FX | $03	; SECTOR NUMBER REGISTER (R/W)
PPIDE_REG_CYLLO		.EQU 	PPIDE_CTL_CS1FX | $04	; CYLINDER NUM REGISTER (LSB) (R/W)
PPIDE_REG_CYLHI		.EQU 	PPIDE_CTL_CS1FX | $05	; CYLINDER NUM REGISTER (MSB) (R/W)
PPIDE_REG_DRVHD		.EQU 	PPIDE_CTL_CS1FX | $06	; DRIVE/HEAD REGISTER (R/W)
PPIDE_REG_LBA0		.EQU	PPIDE_CTL_CS1FX | $03	; LBA BYTE 0 (BITS 0-7) (R/W)
PPIDE_REG_LBA1		.EQU	PPIDE_CTL_CS1FX | $04	; LBA BYTE 1 (BITS 8-15) (R/W)
PPIDE_REG_LBA2		.EQU	PPIDE_CTL_CS1FX | $05	; LBA BYTE 2 (BITS 16-23) (R/W)
PPIDE_REG_LBA3		.EQU	PPIDE_CTL_CS1FX | $06	; LBA BYTE 3 (BITS 24-27) (R/W)
PPIDE_REG_STAT		.EQU 	PPIDE_CTL_CS1FX | $07	; STATUS REGISTER (R)
PPIDE_REG_CMD		.EQU 	PPIDE_CTL_CS1FX | $07	; COMMAND REGISTER (EXECUTE) (W)
PPIDE_REG_ALTSTAT	.EQU 	PPIDE_CTL_CS3FX | $06	; ALTERNATE STATUS REGISTER (R)
PPIDE_REG_CTRL		.EQU 	PPIDE_CTL_CS3FX | $06	; DEVICE CONTROL REGISTER (W)
PPIDE_REG_DRVADR	.EQU 	PPIDE_CTL_CS3FX | $07	; DRIVE ADDRESS REGISTER (R)
;
#IF (PPIDETRACE >= 3)
#DEFINE		DCALL	CALL
#ELSE
#DEFINE		DCALL	\;
#ENDIF
;
; UNIT MAPPING IS AS FOLLOWS:
;   PPIDE0:	PRIMARY MASTER
;   PPIDE1:	PRIMARY SLAVE
;   PPIDE2:	SECONDARY MASTER
;   PPIDE3:	SECONDARY SLAVE
;
PPIDE_UNITCNT		.EQU	2	; ASSUME ONLY PRIMARY INTERFACE
;
; COMMAND BYTES
;
PPIDE_CMD_RECAL		.EQU	$10
PPIDE_CMD_READ		.EQU	$20
PPIDE_CMD_WRITE		.EQU	$30
PPIDE_CMD_IDDEV		.EQU	$EC
PPIDE_CMD_SETFEAT	.EQU	$EF
;
; FEATURE BYTES
;
PPIDE_FEAT_ENABLE8BIT	.EQU	$01
PPIDE_FEAT_DISABLE8BIT	.EQU	$81
;
; PPIDE DEVICE TYPES
;
PPIDE_TYPEUNK	.EQU	0
PPIDE_TYPEATA	.EQU	1
PPIDE_TYPEATAPI	.EQU	2
;
; PPIDE DEVICE STATUS
;
PPIDE_STOK	.EQU	0
PPIDE_STINVUNIT	.EQU	-1
PPIDE_STNOMEDIA	.EQU	-2
PPIDE_STCMDERR	.EQU	-3
PPIDE_STIOERR	.EQU	-4
PPIDE_STRDYTO	.EQU	-5
PPIDE_STDRQTO	.EQU	-6
PPIDE_STBSYTO	.EQU	-7
;
; DRIVE SELECTION BYTES (FOR USE IN DRIVE/HEAD REGISTER)
;
PPIDE_DRVSEL:
PPIDE_DRVMASTER	.DB	%11100000	; LBA, MASTER DEVICE
PPIDE_DRVSLAVE	.DB	%11110000	; LBA, SLAVE DEVICE
;
; PER UNIT DATA OFFSETS (CAREFUL NOT TO EXCEED PER UNIT SPACE IN PPIDE_UNITDATA)
; SEE PPIDE_UNITDATA IN DATA STORAGE BELOW
;
PPIDE_STAT	.EQU	0		; LAST STATUS (1 BYTE)
PPIDE_TYPE	.EQU	1		; DEVICE TYPE (1 BYTE)
PPIDE_CAPACITY	.EQU	2		; DEVICE CAPACITY (1 DWORD/4 BYTES)
;
; THE IDE_WAITXXX FUNCTIONS ARE BUILT TO TIMEOUT AS NEEDED SO DRIVER WILL
; NOT HANG IF DEVICE IS UNRESPONSIVE.  DIFFERENT TIMEOUTS ARE USED DEPENDING
; ON THE SITUATION.  GENERALLY, THE FAST TIMEOUT IS USED TO PROBE FOR DEVICES
; USING FUNCTIONS THAT PERFORM NO I/O.  OTHERWISE THE NORMAL TIMEOUT IS USED.
; IDE SPEC ALLOWS FOR UP TO 30 SECS MAX TO RESPOND.  IN PRACTICE, THIS IS WAY
; TOO LONG, BUT IF YOU ARE USING A VERY OLD DEVICE, THESE TIMEOUTS MAY NEED TO
; BE ADJUSTED.  NOTE THAT THESE ARE BYTE VALUES, SO YOU CANNOT EXCEED 255.
; THE TIMEOUTS ARE IN UNITS OF .05 SECONDS.
;
PPIDE_TONORM	.EQU	200		; NORMAL TIMEOUT IS 10 SECS
PPIDE_TOFAST	.EQU	10		; FAST TIMEOUT IS 0.5 SECS
;
; MACRO TO RETURN POINTER TO FIELD WITHIN UNIT DATA
;
#DEFINE PPIDE_DPTR(FIELD)	CALL PPIDE_DPTRIMP \ .DB FIELD
;
;=============================================================================
; INITIALIZATION ENTRY POINT
;=============================================================================
;
PPIDE_INIT:
	PRTS("PPIDE: IO=0x$")		; LABEL FOR IO ADDRESS
;
	; COMPUTE CPU SPEED COMPENSATED TIMEOUT SCALER
	; AT 1MHZ, THE SCALER IS 961 (50000US / 52TS = 961)
	; SCALER IS THEREFORE 961 * CPU SPEED IN MHZ
	LD	DE,961			; LOAD SCALER FOR 1MHZ
	LD	A,(HCB + HCB_CPUMHZ)	; LOAD CPU SPEED IN MHZ
	CALL	MULT8X16		; HL := DE * A
	LD	(PPIDE_TOSCALER),HL	; SAVE IT
;
	LD	A,PPIDEIOB
	CALL	PRTHEXBYTE
#IF (PPIDE8BIT)
	PRTS(" 8BIT$")
#ENDIF
	PRTS(" UNITS=$")
	LD	A,PPIDE_UNITCNT
	CALL	PRTDECB
;
	; INITIALIZE THE PPIDE INTERFACE NOW
	CALL	PPIDE_RESET		; DO HARDWARE SETUP/INIT
	RET	NZ			; ABORT IF RESET FAILS
;
	; DEVICE DISPLAY LOOP
	LD	B,PPIDE_UNITCNT		; LOOP ONCE PER UNIT
	LD	C,0			; C IS UNIT INDEX
PPIDE_INIT1:
	LD	A,C			; UNIT NUM TO ACCUM
	PUSH	BC			; SAVE LOOP CONTROL
	CALL	PPIDE_INIT2		; DISPLAY UNIT INFO
	POP	BC			; RESTORE LOOP CONTROL
	INC	C			; INCREMENT UNIT INDEX
	DJNZ	PPIDE_INIT1		; LOOP UNTIL DONE
	RET				; DONE
;
PPIDE_INIT2:
	LD	(PPIDE_UNIT),A		; SET CURRENT UNIT
;
	; CHECK FOR BAD STATUS
	PPIDE_DPTR(PPIDE_STAT)		; GET STATUS ADR IN HL, AF TRASHED
	LD	A,(HL)
	OR	A
	JP	NZ,PPIDE_PRTSTAT
;
	CALL	PPIDE_PRTPREFIX		; PRINT DEVICE PREFIX
;
#IF (PPIDE8BIT)
	PRTS(" 8BIT$")
#ENDIF
;
	; PRINT LBA/NOLBA
	CALL	PC_SPACE		; FORMATTING
	LD	HL,HB_TMPBUF		; POINT TO BUFFER START
	LD	DE,98+1			; OFFSET OF BYTE CONTAINING LBA FLAG
	ADD	HL,DE			; POINT TO FINAL BUFFER ADDRESS
	LD	A,(HL)			; GET THE BYTE
	BIT	1,A			; CHECK THE LBA BIT
	LD	DE,PPIDE_STR_NO		; POINT TO "NO" STRING
	CALL	Z,WRITESTR		; PRINT "NO" BEFORE "LBA" IF LBA NOT SUPPORTED
	PRTS("LBA$")			; PRINT "LBA" REGARDLESS
;
	; PRINT STORAGE CAPACITY (BLOCK COUNT)
	PRTS(" BLOCKS=0x$")		; PRINT FIELD LABEL
	PPIDE_DPTR(PPIDE_CAPACITY)	; SET HL TO ADR OF DEVICE CAPACITY
	CALL	LD32			; GET THE CAPACITY VALUE
	CALL	PRTHEX32		; PRINT HEX VALUE
;
	; PRINT STORAGE SIZE IN MB
	PRTS(" SIZE=$")			; PRINT FIELD LABEL
	LD	B,11			; 11 BIT SHIFT TO CONVERT BLOCKS --> MB
	CALL	SRL32			; RIGHT SHIFT
	CALL	PRTDEC			; PRINT LOW WORD IN DECIMAL (HIGH WORD DISCARDED)
	PRTS("MB$")			; PRINT SUFFIX
;
	XOR	A			; SIGNAL SUCCESS
	RET				; RETURN WITH A=0, AND Z SET
;
;=============================================================================
; FUNCTION DISPATCH ENTRY POINT
;=============================================================================
;
PPIDE_DISPATCH:
	; VERIFY AND SAVE THE TARGET DEVICE/UNIT LOCALLY IN DRIVER
	LD	A,C			; DEVICE/UNIT FROM C
	AND	$0F			; ISOLATE UNIT NUM
	CP	PPIDE_UNITCNT
	CALL	NC,PANIC		; PANIC IF TOO HIGH
	LD	(PPIDE_UNIT),A		; SAVE IT
;
	; DISPATCH ACCORDING TO DISK SUB-FUNCTION
	LD	A,B		; GET REQUESTED FUNCTION
	AND	$0F		; ISOLATE SUB-FUNCTION
	JP	Z,PPIDE_STATUS	; SUB-FUNC 0: STATUS
	DEC	A
	JP	Z,PPIDE_RESET	; SUB-FUNC 1: RESET
	DEC	A
	JP	Z,PPIDE_SEEK	; SUB-FUNC 2: SEEK
	DEC	A
	JP	Z,PPIDE_READ	; SUB-FUNC 3: READ SECTORS
	DEC	A
	JP	Z,PPIDE_WRITE	; SUB-FUNC 4: WRITE SECTORS
	DEC	A
	JP	Z,PPIDE_VERIFY	; SUB-FUNC 5: VERIFY SECTORS
	DEC	A
	JP	Z,PPIDE_FORMAT	; SUB-FUNC 6: FORMAT TRACK
	DEC	A
	JP	Z,PPIDE_SENSE	; SUB-FUNC 7: SENSE MEDIA
	DEC	A
	JP	Z,PPIDE_CAP	; SUB-FUNC 8: GET DISK CAPACITY
	DEC	A
	JP	Z,PPIDE_GEOM	; SUB-FUNC 9: GET DISK GEOMETRY
	DEC	A
	JP	Z,PPIDE_GETPAR	; SUB-FUNC 10: GET DISK PARAMETERS
	DEC	A
	JP	Z,PPIDE_SETPAR	; SUB-FUNC 11: SET DISK PARAMETERS
;
PPIDE_VERIFY:
PPIDE_FORMAT:
PPIDE_GETPAR:
PPIDE_SETPAR:
	CALL	PANIC		; INVALID SUB-FUNCTION
;
;
;
PPIDE_READ:
	LD	(PPIDE_DSKBUF),HL	; SAVE DISK BUFFER ADDRESS
#IF (PPIDETRACE == 1)
	LD	HL,PPIDE_PRTERR		; SET UP PPIDE_PRTERR
	PUSH	HL			; ... TO FILTER ALL EXITS
#ENDIF
	CALL	PPIDE_SELUNIT		; HARDWARE SELECTION OF TARGET UNIT
	JP	PPIDE_RDSEC
;
;
;
PPIDE_WRITE:
	LD	(PPIDE_DSKBUF),HL	; SAVE DISK BUFFER ADDRESS
#IF (PPIDETRACE == 1)
	LD	HL,PPIDE_PRTERR		; SET UP PPIDE_PRTERR
	PUSH	HL			; ... TO FILTER ALL EXITS
#ENDIF
	CALL	PPIDE_SELUNIT		; HARDWARE SELECTION OF TARGET UNIT
	JP	PPIDE_WRSEC
;
;
;
PPIDE_STATUS:
	; RETURN UNIT STATUS
	PPIDE_DPTR(PPIDE_STAT)		; HL := ADR OF STATUS, AF TRASHED
	LD	A,(HL)			; GET STATUS OF SELECTED UNIT
	OR	A			; SET FLAGS
	RET				; AND RETURN
;
; PPIDE_SENSE
;
PPIDE_SENSE:
	; THE ONLY WAY TO RESET AN IDE DEVICE IS TO RESET
	; THE ENTIRE INTERFACE.  SO, TO HANDLE POSSIBLE HOT
	; SWAP WE DO THAT, THEN RESELECT THE DESIRED UNIT AND
	; CONTINUE.
	CALL	PPIDE_RESET		; RESET ALL DEVICES ON BUS
;
	PPIDE_DPTR(PPIDE_STAT)		; POINT TO UNIT STATUS
	LD	A,(HL)			; GET STATUS
	OR	A			; SET FLAGS
#IF (PPIDETRACE == 1)
	CALL	PPIDE_PRTERR		; PRINT ANY ERRORS
#ENDIF
	LD	E,MID_HD		; ASSUME WE ARE OK
	RET	Z			; RETURN IF GOOD INIT
	LD	E,MID_NONE		; SIGNAL NO MEDA
	RET				; AND RETURN
;
;
;
PPIDE_SEEK:
	BIT	7,D		; CHECK FOR LBA FLAG
	CALL	Z,HB_CHS2LBA	; CLEAR MEANS CHS, CONVERT TO LBA
	RES	7,D		; CLEAR FLAG REGARDLESS (DOES NO HARM IF ALREADY LBA)
	LD	BC,HSTLBA	; POINT TO LBA STORAGE
	CALL	ST32		; SAVE LBA ADDRESS
	XOR	A		; SIGNAL SUCCESS
	RET			; AND RETURN
;
;
;
PPIDE_CAP:
	PPIDE_DPTR(PPIDE_CAPACITY)	; POINT HL TO CAPACITY OF CUR UNIT
	CALL	LD32			; GET THE CURRENT CAPACITY DO DE:HL
	LD	BC,512			; 512 BYTES PER BLOCK
	XOR	A			; SIGNAL SUCCESS
	RET				; AND DONE
;
;
;
PPIDE_GEOM:
	; FOR LBA, WE SIMULATE CHS ACCESS USING 16 HEADS AND 16 SECTORS
	; RETURN HS:CC -> DE:HL, SET HIGH BIT OF D TO INDICATE LBA CAPABLE
	CALL	PPIDE_CAP		; GET TOTAL BLOCKS IN DE:HL, BLOCK SIZE TO BC
	LD	L,H			; DIVPPIDE BY 256 FOR # TRACKS
	LD	H,E			; ... HIGH BYTE DISCARDED, RESULT IN HL
	LD	D,16 | $80		; HEADS / CYL = 16, SET LBA CAPABILITY BIT
	LD	E,16			; SECTORS / TRACK = 16
	XOR	A			; SIGNAL SUCCESS
	RET
;
;=============================================================================
; FUNCTION SUPPORT ROUTINES
;=============================================================================
;
;
;
PPIDE_SETFEAT:
	PUSH	AF
#IF (PPIDETRACE >= 3)
	CALL	PPIDE_PRTPREFIX
	PRTS(" SETFEAT$")
#ENDIF
	LD	A,(PPIDE_DRVHD)
	;OUT	(PPIDE_REG_DRVHD),A
	CALL	PPIDE_OUT
	.DB	PPIDE_REG_DRVHD
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	POP	AF
	;OUT	(PPIDE_REG_FEAT),A	; SET THE FEATURE VALUE
	CALL	PPIDE_OUT
	.DB	PPIDE_REG_FEAT
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	LD	A,PPIDE_CMD_SETFEAT	; CMD = SETFEAT
	LD	(PPIDE_CMD),A		; SAVE IT
	JP	PPIDE_RUNCMD		; RUN COMMAND AND EXIT
;
;
;
PPIDE_IDENTIFY:
#IF (PPIDETRACE >= 3)
	CALL	PPIDE_PRTPREFIX
	PRTS(" IDDEV$")
#ENDIF
	LD	A,(PPIDE_DRVHD)
	;OUT	(PPIDE_REG_DRVHD),A
	CALL	PPIDE_OUT
	.DB	PPIDE_REG_DRVHD
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	LD	A,PPIDE_CMD_IDDEV
	LD	(PPIDE_CMD),A
	CALL	PPIDE_RUNCMD
	RET	NZ
	LD	HL,HB_TMPBUF
	JP	PPIDE_GETBUF		; EXIT THRU BUFRD
;
;
;
PPIDE_RDSEC:
	CALL	PPIDE_CHKDEVICE
	RET	NZ
;
#IF (PPIDETRACE >= 3)
	CALL	PPIDE_PRTPREFIX
	PRTS(" READ$")
#ENDIF
	LD	A,(PPIDE_DRVHD)
	;OUT	(PPIDE_REG_DRVHD),A
	CALL	PPIDE_OUT
	.DB	PPIDE_REG_DRVHD
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	CALL	PPIDE_SETADDR		; SETUP CYL, TRK, HEAD
	LD	A,PPIDE_CMD_READ
	LD	(PPIDE_CMD),A
	CALL	PPIDE_RUNCMD
	RET	NZ
	LD	HL,(PPIDE_DSKBUF)
	JP	PPIDE_GETBUF
;
;
;
PPIDE_WRSEC:
	CALL	PPIDE_CHKDEVICE
	RET	NZ
;
#IF (PPIDETRACE >= 3)
	CALL	PPIDE_PRTPREFIX
	PRTS(" WRITE$")
#ENDIF
	LD	A,(PPIDE_DRVHD)
	OUT	(PPIDE_REG_DRVHD),A
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	CALL	PPIDE_SETADDR		; SETUP CYL, TRK, HEAD
	LD	A,PPIDE_CMD_WRITE
	LD	(PPIDE_CMD),A
	CALL	PPIDE_RUNCMD
	RET	NZ
	LD	HL,(PPIDE_DSKBUF)
	JP	PPIDE_PUTBUF
;
;
;
PPIDE_SETADDR:
	; XXX
	; SEND 3 LOWEST BYTES OF LBA IN REVERSE ORDER
	; IDE_IO_LBA3 HAS ALREADY BEEN SET
	; HSTLBA2-0 --> IDE_IO_LBA2-0
	LD	A,(HSTLBA + 2)
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	CALL	PPIDE_OUT
	.DB	PPIDE_REG_LBA2

	LD	A,(HSTLBA + 1)
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	CALL	PPIDE_OUT
	.DB	PPIDE_REG_LBA1

	LD	A,(HSTLBA + 0)
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	CALL	PPIDE_OUT
	.DB	PPIDE_REG_LBA0

	LD	A,1
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	CALL	PPIDE_OUT
	.DB	PPIDE_REG_COUNT
;
#IF (DSKYENABLE)
	CALL	PPIDE_DSKY
#ENDIF
;
	RET
;
;=============================================================================
; COMMAND PROCESSING
;=============================================================================
;
PPIDE_RUNCMD:
	CALL	PPIDE_WAITRDY		; WAIT FOR DRIVE READY
	RET	NZ			; BAIL OUT ON TIMEOUT
;
	LD	A,(PPIDE_CMD)		; GET THE COMMAND
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	;OUT	(PPIDE_REG_CMD),A	; SEND IT (STARTS EXECUTION)
	CALL	PPIDE_OUT
	.DB	PPIDE_REG_CMD
#IF (PPIDETRACE >= 3)
	PRTS(" -->$")
#ENDIF
;
	CALL	PPIDE_WAITBSY		; WAIT FOR DRIVE READY (COMMAND DONE)
	RET	NZ			; BAIL OUT ON TIMEOUT
;
	CALL	PPIDE_GETRES
	JP	NZ,PPIDE_CMDERR
	RET
;
;
;
PPIDE_GETBUF:
#IF (PPIDETRACE >= 3)
	PRTS(" GETBUF$")
#ENDIF
;
	; WAIT FOR BUFFER
	CALL	PPIDE_WAITDRQ		; WAIT FOR BUFFER READY
	RET	NZ			; BAIL OUT IF TIMEOUT
;
	; SETUP PPI TO READ
	LD	A,PPIDE_DIR_READ	; SET DATA BUS DIRECTION TO READ
	OUT	(PPIDE_IO_PPI),A	; DO IT
;
	; SELECT READ/WRITE IDE REGISTER
	LD	A,PPIDE_REG_DATA	; DATA REGISTER
	OUT	(PPIDE_IO_CTL),A	; DO IT
	LD	E,A			; E := READ UNASSERTED
	XOR	PPIDE_CTL_DIOR		; SWAP THE READ LINE BIT
	LD	D,A			; D := READ ASSERTED
;
	; LOOP SETUP
	;LD	HL,(PPIDE_DSKBUF)	; LOCATION OF BUFFER
	LD	B,0			; 256 ITERATIONS
	LD	C,PPIDE_IO_DATALO	; SETUP C WITH IO PORT (LSB)
;
#IF (!PPIDE8BIT)
	INC	C			; PRE-INCREMENT C
#ENDIF
;
	CALL	PPIDE_GETBUF1		; FIRST PASS (FIRST 256 BYTES)
	CALL	PPIDE_GETBUF1		; SECOND PASS (LAST 256 BYTES)
;
	;; CLEAN UP
	;XOR	A			; ZERO A
	;OUT	(PPIDE_IO_CTL),A	; RELEASE ALL BUS SIGNALS
;
	CALL	PPIDE_WAITRDY		; PROBLEMS IF THIS IS REMOVED!
	RET	NZ
	CALL	PPIDE_GETRES
	JP	NZ,PPIDE_IOERR
	RET
;
PPIDE_GETBUF1:	; START OF READ LOOP
	LD	A,D			; ASSERT READ
	OUT	(PPIDE_IO_CTL),A	; DO IT
#IF (!PPIDE8BIT)
	DEC	C
	INI				; GET AND SAVE NEXT BYTE
	INC	C			; LSB -> MSB
#ENDIF
	INI				; GET AND SAVE NEXT BYTE
	LD	A,E			; DEASSERT READ
	OUT	(PPIDE_IO_CTL),A	; DO IT
;
	JR	NZ,PPIDE_GETBUF1	; LOOP UNTIL DONE
	RET
;
;
;
PPIDE_PUTBUF:
#IF (PPIDETRACE >= 3)
	PRTS(" PUTBUF$")
#ENDIF

	; WAIT FOR BUFFER
	CALL	PPIDE_WAITDRQ		; WAIT FOR BUFFER READY
	RET	NZ			; BAIL OUT IF TIMEOUT
;
	; SETUP PPI TO WRITE
	LD	A,PPIDE_DIR_WRITE	; SET DATA BUS DIRECTION TO WRITE
	OUT	(PPIDE_IO_PPI),A	; DO IT
;
	; SELECT READ/WRITE IDE REGISTER
	LD	A,PPIDE_REG_DATA	; DATA REGISTER
	OUT	(PPIDE_IO_CTL),A	; DO IT
	LD	E,A			; E := WRITE UNASSERTED
	XOR	PPIDE_CTL_DIOW		; SWAP THE READ LINE BIT
	LD	D,A			; D := WRITE ASSERTED
;
	; LOOP SETUP
	;LD	HL,(PPIDE_DSKBUF)	; LOCATION OF BUFFER
	LD	B,0			; 256 ITERATIONS
	LD	C,PPIDE_IO_DATALO	; SETUP C WITH IO PORT (LSB)
;
#IF (!PPIDE8BIT)
	INC	C			; PRE-INCREMENT C
#ENDIF
;
	CALL	PPIDE_PUTBUF1		; FIRST PASS (FIRST 256 BYTES)
	CALL	PPIDE_PUTBUF1		; SECOND PASS (LAST 256 BYTES)
;
	;; CLEAN UP
	;XOR	A			; ZERO A
	;OUT	(PPIDE_IO_CTL),A	; RELEASE ALL BUS SIGNALS
;
	CALL	PPIDE_WAITRDY		; PROBLEMS IF THIS IS REMOVED!
	RET	NZ
	CALL	PPIDE_GETRES
	JP	NZ,PPIDE_IOERR
	RET
;
PPIDE_PUTBUF1:	; START OF READ LOOP
#IF (!PPIDE8BIT)
	DEC	C
	OUTI				; PUT NEXT BYTE ON THE BUS (LSB)
	INC	C
#ENDIF
	OUTI
	LD	A,D			; ASSERT WRITE
	OUT	(PPIDE_IO_CTL),A	; DO IT
	LD	A,E			; DEASSERT WRITE
	OUT	(PPIDE_IO_CTL),A	; DO IT
;
	JR	NZ,PPIDE_PUTBUF1	; LOOP UNTIL DONE
	RET
;
;
;
PPIDE_GETRES:
	;IN	A,(PPIDE_REG_STAT)	; READ STATUS
	CALL	PPIDE_IN
	.DB	PPIDE_REG_STAT
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	AND	%00000001		; ERROR BIT SET?
	RET	Z			; NOPE, RETURN WITH ZF
;
	;IN	A,(PPIDE_REG_ERR)	; READ ERROR REGISTER
	CALL	PPIDE_IN
	.DB	PPIDE_REG_ERR
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	OR	$FF			; FORCE NZ TO SIGNAL ERROR
	RET				; RETURN
;
;=============================================================================
; HARDWARE INTERFACE ROUTINES
;=============================================================================
;
; SOFT RESET OF ALL DEVICES ON BUS
;
PPIDE_RESET:
;
	; SETUP PPI TO READ
	LD	A,PPIDE_DIR_READ	; SET DATA BUS DIRECTION TO READ
	OUT	(PPIDE_IO_PPI),A	; DO IT
;
	LD	A,PPIDE_CTL_RESET
	OUT	(PPIDE_IO_CTL),A
	LD	DE,2
	CALL	VDELAY
	XOR	A
	OUT	(PPIDE_IO_CTL),A
	LD	DE,2
	CALL	VDELAY
;
	LD	A,%00001010		; SET ~IEN, NO INTERRUPTS
	;OUT	(PPIDE_REG_CTRL),A
	CALL	PPIDE_OUT
	.DB	PPIDE_REG_CTRL
;
; SPEC ALLOWS UP TO 450MS FOR DEVICES TO ASSERT THEIR PRESENCE
; VIA -DASP.  I ENCOUNTER PROBLEMS LATER ON IF I DON'T WAIT HERE
; FOR THAT TO OCCUR.  THUS FAR, IT APPEARS THAT 150MS IS SUFFICIENT
; FOR ANY DEVICE ENCOUNTERED.  MAY NEED TO EXTEND BACK TO 500MS
; IF A SLOWER DEVICE IS ENCOUNTERED.
;
	;LD	DE,500000/16		; ~500MS
	LD	DE,150000/16		; ~???MS
	CALL	VDELAY
;
	; CLEAR OUT ALL DATA (FOR ALL UNITS)
	LD	HL,PPIDE_UDATA
	LD	BC,PPIDE_UDLEN
	XOR	A
	CALL	FILL
;
	LD	A,(PPIDE_UNIT)		; GET THE CURRENT UNIT SELECTION
	PUSH	AF			; AND SAVE IT
;
	; PROBE / INITIALIZE ALL UNITS
	LD	B,PPIDE_UNITCNT		; NUMBER OF UNITS TO TRY
	LD	C,0			; UNIT INDEX FOR LOOP
PPIDE_RESET1:
	LD	A,C			; UNIT NUMBER TO A
	PUSH	BC
	CALL	PPIDE_INITUNIT		; PROBE/INIT UNIT
	POP	BC
	INC	C			; NEXT UNIT
	DJNZ	PPIDE_RESET1		; LOOP AS NEEDED
;
	POP	AF			; RECOVER ORIGINAL UNIT NUMBER
	LD	(PPIDE_UNIT),A		; AND SAVE IT
;
	XOR	A			; SIGNAL SUCCESS
	RET				; AND DONE
;
;
;
PPIDE_INITUNIT:
	LD	(PPIDE_UNIT),A		; SET ACTIVE UNIT

	CALL	PPIDE_SELUNIT		; SELECT UNIT
	RET	NZ			; ABORT IF ERROR
	
	LD	HL,PPIDE_TIMEOUT	; POINT TO TIMEOUT
	LD	(HL),PPIDE_TOFAST	; USE FAST TIMEOUT DURING INIT
	
	CALL	PPIDE_PROBE		; DO PROBE
	RET	NZ			; ABORT IF ERROR
	
	CALL	PPIDE_INITDEV		; INIT DEVICE AND RETURN
;
	LD	HL,PPIDE_TIMEOUT	; POINT TO TIMEOUT
	LD	(HL),PPIDE_TONORM	; BACK TO NORMAL TIMEOUT
;
	RET
;
; TAKE ANY ACTIONS REQUIRED TO SELECT DESIRED PHYSICAL UNIT
; UNIT IS SPECIFIED IN A
;
PPIDE_SELUNIT:
	LD	A,(PPIDE_UNIT)		; GET UNIT
	CP	PPIDE_UNITCNT		; CHECK VALIDITY (EXCEED UNIT COUNT?)
	JP	NC,PPIDE_INVUNIT	; HANDLE INVALID UNIT
;
	PUSH	HL			; SAVE HL, IT IS DESTROYED BELOW
	LD	A,(PPIDE_UNIT)		; GET CURRENT UNIT
	AND	$01			; LS BIT DETERMINES MASTER/SLAVE
	LD	HL,PPIDE_DRVSEL
	CALL	ADDHLA
	LD	A,(HL)			; LOAD DRIVE/HEAD VALUE
	POP	HL			; RECOVER HL
	LD	(PPIDE_DRVHD),A		; SAVE IT
;
	XOR	A
	RET
;
;
;
PPIDE_PROBE:
#IF (PPIDETRACE >= 3)
	CALL	PPIDE_PRTPREFIX
	PRTS(" PROBE$")			; LABEL FOR IO ADDRESS
#ENDIF
;
	LD	A,(PPIDE_DRVHD)
	;OUT	(IDE_IO_DRVHD),A
	CALL	PPIDE_OUT
	.DB	PPIDE_REG_DRVHD
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE
	
	CALL	DELAY			; DELAY ~16US
;
	DCALL	PPIDE_REGDUMP
;
	;JR	PPIDE_PROBE1		; *DEBUG*
;
PPIDE_PROBE0:
	CALL	PPIDE_WAITBSY		; WAIT FOR BUSY TO CLEAR
	RET	NZ			; ABORT ON TIMEOUT
;
	DCALL	PPIDE_REGDUMP
;
	; CHECK STATUS
;	IN	A,(PPIDE_REG_STAT)	; GET STATUS
	CALL	PPIDE_IN
	.DB	PPIDE_REG_STAT
	DCALL	PC_SPACE
	DCALL	PRTHEXBYTE		; IF DEBUG, PRINT STATUS
	OR	A			; SET FLAGS TO TEST FOR ZERO
	JP	Z,PPIDE_NOMEDIA		; CONTINUE IF NON-ZERO
;
	; CHECK SIGNATURE
	DCALL	PC_SPACE
	;IN	A,(PPIDE_REG_COUNT)
	CALL	PPIDE_IN
	.DB	PPIDE_REG_COUNT
	DCALL	PRTHEXBYTE
	CP	$01
	JP	NZ,PPIDE_NOMEDIA
	DCALL	PC_SPACE
	;IN	A,(PPIDE_REG_SECT)
	CALL	PPIDE_IN
	.DB	PPIDE_REG_SECT
	DCALL	PRTHEXBYTE
	CP	$01
	JP	NZ,PPIDE_NOMEDIA
	DCALL	PC_SPACE
	;IN	A,(PPIDE_REG_CYLLO)
	CALL	PPIDE_IN
	.DB	PPIDE_REG_CYLLO
	DCALL	PRTHEXBYTE
	CP	$00
	JP	NZ,PPIDE_NOMEDIA
	DCALL	PC_SPACE
	;IN	A,(PPIDE_REG_CYLHI)
	CALL	PPIDE_IN
	.DB	PPIDE_REG_CYLHI
	DCALL	PRTHEXBYTE
	CP	$00
	JP	NZ,PPIDE_NOMEDIA
;
PPIDE_PROBE1:
	; SIGNATURE MATCHES ATA DEVICE, RECORD TYPE AND RETURN SUCCESS
	PPIDE_DPTR(PPIDE_TYPE)		; POINT HL TO UNIT TYPE FIELD, A IS TRASHED
	LD	(HL),PPIDE_TYPEATA	; SET THE DEVICE TYPE
	XOR	A			; SIGNAL SUCCESS
	RET				; DONE, NOTE THAT A=0 AND Z IS SET
;
; (RE)INITIALIZE DEVICE
;
PPIDE_INITDEV:
;
	PPIDE_DPTR(PPIDE_TYPE)		; POINT HL TO UNIT TYPE FIELD, A IS TRASHED
	LD	A,(HL)			; GET THE DEVICE TYPE
	OR	A			; SET FLAGS
	JP	Z,PPIDE_NOMEDIA		; EXIT SETTING NO MEDIA STATUS
;
	; CLEAR OUT UNIT SPECIFIC DATA, BUT PRESERVE THE EXISTING
	; VALUE OF THE UNIT TYPE WHICH WAS ESTABLISHED BY THE DEVICE
	; PROBES WHEN THE PPIDE BUS WAS RESET
	PUSH	AF			; SAVE UNIT TYPE VALUE FROM ABOVE
	PUSH	HL			; SAVE UNIT TYPE FIELD POINTER
	PPIDE_DPTR(0)			; SET HL TO START OF UNIT DATA
	LD	BC,PPIDE_UDLEN
	XOR	A
	CALL	FILL
	POP	HL			; RECOVER UNIT TYPE FIELD POINTER
	POP	AF			; RECOVER UNIT TYPE VALUE
	LD	(HL),A			; AND PUT IT BACK
;
#IF (PPIDE8BIT)
	LD	A,PPIDE_FEAT_ENABLE8BIT	; FEATURE VALUE = ENABLE 8-BIT PIO
#ELSE
	LD	A,PPIDE_FEAT_DISABLE8BIT	; FEATURE VALUE = DISABLE 8-BIT PIO
#ENDIF
	CALL	PPIDE_SETFEAT		; SET FEATURE
	RET	NZ			; BAIL OUT ON ERROR
;
	CALL	PPIDE_IDENTIFY		; EXECUTE PPIDENTIFY COMMAND
	RET	NZ			; BAIL OUT ON ERROR
;
	LD	DE,HB_TMPBUF		; POINT TO BUFFER
	DCALL	DUMP_BUFFER		; DUMP IT IF DEBUGGING
;
	; GET DEVICE CAPACITY AND SAVE IT
	PPIDE_DPTR(PPIDE_CAPACITY)		; POINT HL TO UNIT CAPACITY FIELD
	PUSH	HL			; SAVE POINTER
	LD	HL,HB_TMPBUF		; POINT TO BUFFER START
	LD	A,120			; OFFSET OF SECTOR COUNT
	CALL	ADDHLA			; POINT TO ADDRESS OF SECTOR COUNT
	CALL	LD32			; LOAD IT TO DE:HL
	POP	BC			; RECOVER POINTER TO CAPACITY ENTRY
	CALL	ST32			; SAVE CAPACITY
;
	; RESET CARD STATUS TO 0 (OK)
	PPIDE_DPTR(PPIDE_STAT)		; HL := ADR OF STATUS, AF TRASHED
	XOR	A			; A := 0 (STATUS = OK)
	LD	(HL),A			; SAVE IT
;
	RET				; RETURN, A=0, Z SET
;
;
;
PPIDE_CHKDEVICE:
	PPIDE_DPTR(PPIDE_STAT)
	LD	A,(HL)
	OR	A
	RET	Z			; RETURN IF ALL IS WELL
;
	; ATTEMPT TO REINITIALIZE HERE???
	JP	PPIDE_ERR
	RET
;
;
;
PPIDE_WAITRDY:
	LD	A,(PPIDE_TIMEOUT)		; GET TIMEOUT IN 0.05 SECS
	LD	B,A			; PUT IN OUTER LOOP VAR
PPIDE_WAITRDY1:
	LD	DE,(PPIDE_TOSCALER)	; CPU SPPED SCALER TO INNER LOOP VAR
PPIDE_WAITRDY2:
	;IN	A,(PPIDE_REG_STAT)	; READ STATUS
	CALL	PPIDE_IN
	.DB	PPIDE_REG_STAT
	LD	C,A			; SAVE IT
	AND	%11000000		; ISOLATE BUSY AND RDY BITS
	XOR	%01000000		; WE WANT BUSY(7) TO BE 0 AND RDY(6) TO BE 1
	RET	Z			; ALL SET, RETURN WITH Z SET
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,PPIDE_WAITRDY2	; INNER LOOP RETURN
	DJNZ	PPIDE_WAITRDY1		; OUTER LOOP RETURN
	JP	PPIDE_RDYTO		; EXIT WITH RDYTO ERR
;
;
;
PPIDE_WAITDRQ:
	LD	A,(PPIDE_TIMEOUT)		; GET TIMEOUT IN 0.05 SECS
	LD	B,A			; PUT IN OUTER LOOP VAR
PPIDE_WAITDRQ1:
	LD	DE,(PPIDE_TOSCALER)	; CPU SPPED SCALER TO INNER LOOP VAR
PPIDE_WAITDRQ2:
	;IN	A,(PPIDE_REG_STAT)	; READ STATUS
	CALL	PPIDE_IN
	.DB	PPIDE_REG_STAT
	LD	C,A			; SAVE IT
	AND	%10001000		; TO FILL (OR READY TO FILL)
	XOR	%00001000
	RET	Z
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,PPIDE_WAITDRQ2
	DJNZ	PPIDE_WAITDRQ1
	JP	PPIDE_DRQTO		; EXIT WITH BUFTO ERR
;
;
;
PPIDE_WAITBSY:
	LD	A,(PPIDE_TIMEOUT)		; GET TIMEOUT IN 0.05 SECS
	LD	B,A			; PUT IN OUTER LOOP VAR
PPIDE_WAITBSY1:
	LD	DE,(PPIDE_TOSCALER)	; CPU SPPED SCALER TO INNER LOOP VAR
PPIDE_WAITBSY2:
	;IN	A,(PPIDE_REG_STAT)	; READ STATUS
	CALL	PPIDE_IN
	.DB	PPIDE_REG_STAT
	LD	C,A			; SAVE IT
	AND	%10000000		; TO FILL (OR READY TO FILL)
	RET	Z
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,PPIDE_WAITBSY2
	DJNZ	PPIDE_WAITBSY1
	JP	PPIDE_BSYTO		; EXIT WITH BSYTO ERR
;
;
;
PPIDE_IN:
	LD	A,PPIDE_DIR_READ	; SET DATA BUS DIRECTION TO READ
	OUT	(PPIDE_IO_PPI),A	; DO IT
	EX	(SP),HL			; GET PARM POINTER
	PUSH	BC			; SAVE INCOMING BC
	LD	B,(HL)			; GET CTL PORT VALUE
	LD	C,PPIDE_IO_CTL		; SETUP PORT TO WRITE
	OUT	(C),B                   ; SET ADDRESS LINES
	SET	6,B                     ; TURN ON WRITE BIT
	OUT	(C),B                   ; ASSERT WRITE LINE
	IN	A,(PPIDE_IO_DATALO)	; GET DATA VALUE FROM DEVICE
	RES	6,B                     ; CLEAR WRITE BIT
	OUT	(C),B                   ; DEASSERT WRITE LINE
	POP	BC			; RECOVER INCOMING BC
	INC	HL			; POINT PAST PARM
	EX	(SP),HL			; RESTORE STACK
	RET
;
;
;
PPIDE_OUT:
	PUSH	AF			; PRESERVE INCOMING VALUE
	LD	A,PPIDE_DIR_WRITE	; SET DATA BUS DIRECTION TO WRITE
	OUT	(PPIDE_IO_PPI),A	; DO IT
	POP	AF			; RECOVER VALUE TO WRITE
	EX	(SP),HL			; GET PARM POINTER
	PUSH	BC			; SAVE INCOMING BC
	LD	B,(HL)			; GET IDE ADDRESS VALUE
	LD	C,PPIDE_IO_CTL		; SETUP PORT TO WRITE
	OUT	(C),B			; SET ADDRESS LINES
	SET	5,B			; TURN ON WRITE BIT
	OUT	(C),B			; ASSERT WRITE LINE
	OUT	(PPIDE_IO_DATALO),A	; SEND DATA VALUE TO DEVICE
	RES	5,B			; CLEAR WRITE BIT
	OUT	(C),B			; DEASSERT WRITE LINE
	POP	BC			; RECOVER INCOMING BC
	INC	HL			; POINT PAST PARM
	EX	(SP),HL			; RESTORE STACK
	RET
;
;=============================================================================
; ERROR HANDLING AND DIAGNOSTICS
;=============================================================================
;
; ERROR HANDLERS
;
PPIDE_INVUNIT:
	LD	A,PPIDE_STINVUNIT
	JR	PPIDE_ERR2		; SPECIAL CASE FOR INVALID UNIT
;
PPIDE_NOMEDIA:
	LD	A,PPIDE_STNOMEDIA
	JR	PPIDE_ERR
;
PPIDE_CMDERR:
	LD	A,PPIDE_STCMDERR
	JR	PPIDE_ERR
;
PPIDE_IOERR:
	LD	A,PPIDE_STIOERR
	JR	PPIDE_ERR
;
PPIDE_RDYTO:
	LD	A,PPIDE_STRDYTO
	JR	PPIDE_ERR
;
PPIDE_DRQTO:
	LD	A,PPIDE_STDRQTO
	JR	PPIDE_ERR
;
PPIDE_BSYTO:
	LD	A,PPIDE_STBSYTO
	JR	PPIDE_ERR
;
PPIDE_ERR:
	PUSH	HL			; IS THIS NEEDED?
	PUSH	AF			; SAVE INCOMING STATUS
	PPIDE_DPTR(PPIDE_STAT)		; GET STATUS ADR IN HL, AF TRASHED
	POP	AF			; RESTORE INCOMING STATUS
	LD	(HL),A			; UPDATE STATUS
	POP	HL			; IS THIS NEEDED?
PPIDE_ERR2:
#IF (PPIDETRACE >= 2)
	CALL	PPIDE_PRTSTAT
	CALL	PPIDE_REGDUMP
#ENDIF
	OR	A			; SET FLAGS
	RET
;
;
;
PPIDE_PRTERR:
	RET	Z			; DONE IF NO ERRORS
	; FALL THRU TO PPIDE_PRTSTAT
;
; PRINT STATUS STRING (STATUS NUM IN A)
;
PPIDE_PRTSTAT:
	PUSH	AF
	PUSH	DE
	PUSH	HL
	OR	A
	LD	DE,PPIDE_STR_STOK
	JR	Z,PPIDE_PRTSTAT1
	INC	A
	LD	DE,PPIDE_STR_STINVUNIT
	JR	Z,PPIDE_PRTSTAT2	; INVALID UNIT IS SPECIAL CASE
	INC	A
	LD	DE,PPIDE_STR_STNOMEDIA
	JR	Z,PPIDE_PRTSTAT1
	INC	A
	LD	DE,PPIDE_STR_STCMDERR
	JR	Z,PPIDE_PRTSTAT1
	INC	A
	LD	DE,PPIDE_STR_STIOERR
	JR	Z,PPIDE_PRTSTAT1
	INC	A
	LD	DE,PPIDE_STR_STRDYTO
	JR	Z,PPIDE_PRTSTAT1
	INC	A
	LD	DE,PPIDE_STR_STDRQTO
	JR	Z,PPIDE_PRTSTAT1
	INC	A
	LD	DE,PPIDE_STR_STBSYTO
	JR	Z,PPIDE_PRTSTAT1
	LD	DE,PPIDE_STR_STUNK
PPIDE_PRTSTAT1:
	CALL	PPIDE_PRTPREFIX		; PRINT UNIT PREFIX
	JR	PPIDE_PRTSTAT3
PPIDE_PRTSTAT2:
	CALL	NEWLINE
	PRTS("PPIDE:$")			; NO UNIT NUM IN PREFIX FOR INVALID UNIT
PPIDE_PRTSTAT3:
	CALL	PC_SPACE		; FORMATTING
	CALL	WRITESTR
	POP	HL
	POP	DE
	POP	AF
	RET
;
; PRINT ALL REGISTERS DIRECTLY FROM DEVICE
; DEVICE MUST BE SELECTED PRIOR TO CALL
;
PPIDE_REGDUMP:
	PUSH	AF
	PUSH	BC
	CALL	PC_SPACE
	CALL	PC_LBKT
	LD	A,PPIDE_DIR_READ	; SET DATA BUS DIRECTION TO READ
	OUT	(PPIDE_IO_PPI),A	; DO IT
	LD	C,PPIDE_REG_CMD
	LD	B,7
PPIDE_REGDUMP1:
	LD	A,C			; REGISTER ADDRESS
	OUT	(PPIDE_IO_CTL),A	; SET IT
	XOR	PPIDE_CTL_DIOR		; SET BIT TO ASSERT READ LINE
	OUT	(PPIDE_IO_CTL),A	; ASSERT READ
	IN	A,(PPIDE_IO_DATALO)	; GET VALUE
	CALL	PRTHEXBYTE		; DISPLAY IT
	LD	A,C			; RELOAD ADDRESS W/ READ UNASSERTED
	OUT	(PPIDE_IO_CTL),A	; AND SET IT
	DEC	C			; NEXT LOWER REGISTER
	DEC	B			; DEC LOOP COUNTER
	CALL	NZ,PC_SPACE		; FORMATTING
	JR	NZ,PPIDE_REGDUMP1	; LOOP AS NEEDED
	CALL	PC_RBKT			; FORMATTING
	POP	BC
	POP	AF
	RET
;
; PRINT DIAGNONSTIC PREFIX
;
PPIDE_PRTPREFIX:
	PUSH	AF
	CALL	NEWLINE
	PRTS("PPIDE$")
	LD	A,(PPIDE_UNIT)
	ADD	A,'0'
	CALL	COUT
	CALL	PC_COLON
	POP	AF
	RET
;
;
;
#IF (DSKYENABLE)
PPIDE_DSKY:
	LD	HL,DSKY_HEXBUF		; POINT TO DSKY BUFFER
	IN	A,(PPIDE_REG_DRVHD)	; GET DRIVE/HEAD
	LD	(HL),A			; SAVE IN BUFFER
	INC	HL			; INCREMENT BUFFER POINTER
	IN	A,(PPIDE_REG_CYLHI)	; GET DRIVE/HEAD
	LD	(HL),A                  ; SAVE IN BUFFER
	INC	HL                      ; INCREMENT BUFFER POINTER
	IN	A,(PPIDE_REG_CYLLO)	; GET DRIVE/HEAD
	LD	(HL),A                  ; SAVE IN BUFFER
	INC	HL                      ; INCREMENT BUFFER POINTER
	IN	A,(PPIDE_REG_SECT)	; GET DRIVE/HEAD
	LD	(HL),A                  ; SAVE IN BUFFER
	CALL	DSKY_HEXOUT             ; SEND IT TO DSKY
	RET
#ENDIF
;
;=============================================================================
; STRING DATA
;=============================================================================
;
PPIDE_STR_STOK		.TEXT	"OK$"
PPIDE_STR_STINVUNIT	.TEXT	"INVALID UNIT$"
PPIDE_STR_STNOMEDIA	.TEXT	"NO MEDIA$"
PPIDE_STR_STCMDERR	.TEXT	"COMMAND ERROR$"
PPIDE_STR_STIOERR	.TEXT	"IO ERROR$"
PPIDE_STR_STRDYTO	.TEXT	"READY TIMEOUT$"
PPIDE_STR_STDRQTO	.TEXT	"DRQ TIMEOUT$"
PPIDE_STR_STBSYTO	.TEXT	"BUSY TIMEOUT$"
PPIDE_STR_STUNK		.TEXT	"UNKNOWN ERROR$"
;
PPIDE_STR_NO		.TEXT	"NO$"
;
;=============================================================================
; DATA STORAGE
;=============================================================================
;
PPIDE_TIMEOUT	.DB	PPIDE_TONORM		; WAIT FUNCS TIMEOUT IN TENTHS OF SEC
PPIDE_TOSCALER	.DW	CPUMHZ * 961		; WAIT FUNCS SCALER FOR CPU SPEED
;
PPIDE_CMD	.DB	0			; PENDING COMMAND TO PROCESS
PPIDE_DRVHD	.DB	0			; CURRENT DRIVE/HEAD MASK
;
PPIDE_UNIT	.DB	0			; ACTIVE UNIT, DEFAULT TO ZERO
PPIDE_DSKBUF	.DW	0			; ACTIVE DISK BUFFER
;
; UNIT SPECIFIC DATA STORAGE
;
PPIDE_UDATA	.FILL	PPIDE_UNITCNT*8,0	; PER UNIT DATA, 8 BYTES
PPIDE_DLEN	.EQU	$ - PPIDE_UDATA		; LENGTH OF ENTIRE DATA STORAGE FOR ALL UNITS
PPIDE_UDLEN	.EQU	PPIDE_DLEN / PPIDE_UNITCNT	; LENGTH OF PER UNIT DATA
;
;=============================================================================
; HELPER ROUTINES
;=============================================================================
;
; IMPLEMENTATION FOR MACRO PPIDE_DPTR
; SET HL TO ADDRESS OF FIELD WITHIN PER UNIT DATA
;   HL := ADR OF PPIDE_UNITDATA[(PPIDE_UNIT)][(SP)]
; ENTER WITH TOP-OF-STACK = ADDRESS OF FIELD OFFSET
; AF IS TRASHED
;
PPIDE_DPTRIMP:
	LD	HL,PPIDE_UDATA		; POINT TO START OF UNIT DATA ARRAY
	LD	A,(PPIDE_UNIT)		; GET CURRENT UNIT NUM
	RLCA				; MULTIPLY BY
	RLCA				; ... SIZE OF PER UNIT DATA
	RLCA				; ... (8 BYTES)
	EX	(SP),HL			; GET PTR TO FIELD OFFSET VALUE FROM TOS
	ADD	A,(HL)			; ADD IT TO START OF UNIT DATA IN ACCUM
	INC	HL			; BUMP HL TO NEXT REAL INSTRUCTION
	EX	(SP),HL			; AND PUT IT BACK ON STACK, HL GETS ADR OF START OF DATA
	JP	ADDHLA			; CALC FINAL ADR IN HL AND RETURN
