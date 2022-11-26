;==================================================================================================
;	ECB USB-FIFO DRIVER FOR WILL SOWERBUTTS ADAFRUIT BASED FT232H ECB-FIFO BOARD
;	REFER https://www.retrobrewcomputers.org/doku.php?id=boards:ecb:usb-fifo:start
;	PHIL SUMMERS (b1ackmai1er)
;==================================================================================================
;
;	BASE PORT IS SET IN CFG_SBC.INC
;	INTERRUPTS ARE NOT USED.
;	ONLY ONE BOARD SUPPORTED.
;
;	HBIOS CALLS:
;
;	UF_PREINIT	SETUP THE DISPATCH TABLE ENTRY AND INITIALIZE HARDWARE	
;	UF_INIT		ANNOUNCE DEVICE DESCRIPTION AND PORT
;
THIS_DRV	.SET	DRV_ID_UF
;
FIFO_DATA       .EQU	(UFBASE+0)	; READ/WRITE DATA
FIFO_STATUS     .EQU	(UFBASE+1)	; READ/WRITE STATUS
FIFO_SEND_IMM   .EQU	(UFBASE+2)	; WRITE PORT TO FORCE BUFFER FLUSH
FIFO_BUFFER	.EQU	FALSE		; OPTION TO BUFFER OUTPUT FOR 17ms
;
UF_USB_ACTIVE	.DB	0		; USB CABLE CONNECTED STATUS FLAG
;
; DEVICE DESCRIPTION TABLE
;
UF_CFG:	.DW	SER_9600_8N1		; DUMMY CONFIGURATION
;
; SETUP THE DISPATCH TABLE ENTRY AND INITIALIZE HARDWARE
;
UF_PREINIT:
	LD	HL,UF_CFG		; POINT TO START OF CFG TABLE
	PUSH	HL			; COPY CFG DATA PTR
	PUSH	HL
	POP	IY			; ... TO IY
	CALL	UF_INITUNIT		; HAND OFF TO GENERIC INIT CODE
	LD	(UF_USB_ACTIVE),A	; SAVE USB CONNECTION STATUS
	POP	DE			; GET ENTRY ADDRESS BACK, BUT PUT IN DE
;	JR	Z,UF_FAIL		; EXIT IF NO USB CONNECTION
	LD	BC,UF_FNTBL		; BC := FUNCTION TABLE ADDRESS
	CALL	CIO_ADDENT		; ADD ENTRY IF FOUND, BC:DE
	XOR	A			; SIGNAL SUCCESS
UF_FAIL:
	RET				; AND RETURN
;
; INITIALIZATION ROUTINE
;
UF_INITUNIT:
	CALL	UF_DETECT		; DETERMINE TYPE
	OR	A			; SET FLAGS
	RET	Z			; ABORT IF NOTHING THERE

	; SET DEFAULT CONFIG
	LD	DE,-1			; LEAVE CONFIG ALONE
	JR	UF_INITDEV		; IMPLEMENT IT AND RETURN
;
; ANNOUNCE DEVICE DESCRIPTION AND PORT
;
UF_INIT:
	CALL	NEWLINE			; PRINT DEVICE
	CALL	PRTSTRD
	.TEXT	"USB-FIFO: IO=0x$")
	LD	A,UFBASE		; PRINT PORT
	CALL	PRTHEXBYTE
	LD	A,(UF_USB_ACTIVE)	; PRINT CONNECTION STATUS
	OR	A			; REQUIRES TERMINAL PROGRAM
	RET	NZ			; TO HAVE INITIALIZED PORT
	CALL	PRTSTRD			; ON PC SIDE.
	.TEXT	" NO CONNECTION$"
	RET
;
; INPUT A CHARACTER AND RETURN IT IN E
;
UF_IN:
	CALL	UF_IST			; CHAR WAITING?
	JR	Z,UF_IN			; LOOP IF NOT
	LD	C,FIFO_DATA		; C := INPUT PORT
	IN	E,(C)			; GET CHAR
	XOR	A			; SIGNAL SUCCESS
	RET
;
; OUTPUT THE CHARACTER IN E
;
UF_OUT:
	CALL	UF_OST			; READY FOR CHAR?
	JR	Z,UF_OUT		; LOOP IF NOT
	LD	C,FIFO_DATA
	OUT	(C),E			; WRITE TO FIFO
#IF (FIFO_BUFFER)
	OUT	(FIFO_SEND_IMM),A	; SEND IMMEDIATE
#ENDIF
	XOR	A			; SIGNAL SUCCESS
	RET
;
; INPUT STATUS - CAN WE RECEIVE A CHARACTER
;
UF_IST:
	IN	A,(FIFO_STATUS)		; IS THE QUEUE EMPTY?
	RLCA				; SET BIT 1 : 0 = DATA AVAIL. 1 = NO DATA AVAIL
	CPL				; INVERT BIT 1 : 1 = DATA AVAIL. 0 = NO DATA AVAIL
	AND	00000001B		; SET BYTE PENDING, 0 OR 1 AND STATUS
	RET
;
; OUTPUT STATUS - CAN WE OUTPUT A CHARACTER
;
UF_OST:
	IN	A,(FIFO_STATUS)		; IS THE SEND BUFFER FULL?
	CPL
	AND	00000001B
	RET	
;
; INITIALIZATION THE SETUP PARAMETER WORD AND INITIALIZE DEVICE
; SAVE NEW SPW IF NOT A RE-INIT. ALWAYS INITIALIZE DEVICE.
; SPW IS NOT VALIDATED BUT IT IS NOT USED FOR ANYTHING.
;
UF_INITDEV:
;
	; TEST FOR -1 WHICH MEANS USE CURRENT CONFIG (JUST REINIT)
	LD	A,D			; TEST DE FOR
	AND	E			; ... VALUE OF -1
	INC	A			; ... SO Z SET IF -1
	JR	NZ,UF_INITDEV1		; IF DE == -1, REINIT CURRENT CONFIG
;
	; GET CURRENT SPW. WE ALWAYS RESAVE AT END
	LD	E,(IY+0)		; LOW BYTE
	LD	D,(IY+1)		; HIGH BYTE	
;
UF_INITDEV1:
	XOR	A			; INTERRUPTS OFF
	OUT	(FIFO_STATUS),A
;
UF_FLUSH:
	IN	A,(FIFO_STATUS)		; IS THERE ANY DATA
	RLCA				; IN THE BUFFER ?
	JR	C,UFBUFEMPTY		; EXIT IF EMPTY
;
	IN	A,(FIFO_DATA)		; CLEAR BUFFER BY READING
	JR	UF_FLUSH		; ALL THE DATA
UFBUFEMPTY:
	LD	(IY+0),E		; SAVE LOW WORD
	LD	(IY+1),D		; SAVE HI WORD
	XOR	A
	RET				; NZ STATUS HERE INDICATES FAIL.
;
;	USB-FIFO WILL APPEAR AS A SERIAL DEVICE AT DEFAULT SERIAL MODE
;
UF_QUERY:
	LD	E,(IY+0)		; FIRST CONFIG BYTE TO E
	LD	D,(IY+1)		; SECOND CONFIG BYTE TO D
	XOR	A			; SIGNAL SUCCESS
	RET				; DONE
;
;	USB-FIFO WILL APPEAR AS A SERIAL DEVICE
;
UF_DEVICE:
	LD	D,CIODEV_UF		; D := DEVICE TYPE
	XOR	A			; SIGNAL SUCCESS
	LD	E,A			; E := PHYSICAL UNIT, ALWAYS 0
	LD	C,A			; C := DEVICE TYPE, 0x00 IS RS-232
	LD	H,0			; H := 0, DRIVER HAS NO MODES
	LD	L,UFBASE		; L := BASE I/O ADDRESS
	RET
;
; USB-FIFO DETECTION ROUTINE
;
UF_DETECT:
	IN	A,(FIFO_STATUS)
	AND	10000001B
	SUB	10000001B		; A=0 CABLE DISCONNECTED
	RET	Z			; OR PC PORT CLOSED
	LD	A,1			; A=1 CABLE CONNECTED
	RET				; AND PC PORT OPEN
;
; DRIVER FUNCTION TABLE
;
UF_FNTBL:
	.DW	UF_IN
	.DW	UF_OUT
	.DW	UF_IST
	.DW	UF_OST
	.DW	UF_INITDEV
	.DW	UF_QUERY
	.DW	UF_DEVICE
#IF (($ - UF_FNTBL) != (CIO_FNCNT * 2))
	.ECHO	"*** INVALID USB-FIFO FUNCTION TABLE ***\n"
#ENDIF
;
