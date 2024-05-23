;======================================================================
;	NABU KEYBOARD DRIVER
;
;	CREATED BY: LES BIRD
;
;======================================================================
;
; NABU KEYBOARD CODES:
;
;  $00-$7F	STANDARD ASCII CODES
;  $80-$8F	JOYSTICK PREFIXES ($80 = JS1, $81 = JS2)
;  $90-$9F	KEYBOARD ERROR CODES
;  $A0-$BF	JOYSTICK DATA
;  $C0-$DF	UNUSED
;  $E0-$EF	SPECIAL KEYS
;
; NOTE THAT THE ERROR CODE $94 IS A WATCHDOG TIMER THAT WILL BE
; SENT BY THE KEYBOARD EVERY 3.7 SECONDS.
;
; THE CODE BELOW WILL IGNORE (SWALLOW) THE ERROR CODES ($90-$9F) AND
; WILL TRANSLATE SPECIAL KEYS ($E0-$FF) TO ROMWBW EQUIVALENTS.  ALL
; OTHER KEYS WILL BE PASSED THROUGH AS IS.
;
;
NABUKB_IODAT	.EQU	$90		; KEYBOARD DATA (READ)
NABUKB_IOSTAT	.EQU	$91		; STATUS (READ), CMD (WRITE)
;
	DEVECHO	"NABUKB: IO="
	DEVECHO	NABUKB_IODAT
	DEVECHO	"\n"
;
; INITIALZIZE THE KEYBOARD CONTROLLER.
;
NABUKB_INIT:
	CALL	NEWLINE
	PRTS("NABUKB: IO=0x$")
	LD	A,NABUKB_IODAT
	CALL	PRTHEXBYTE
;
	XOR	A
	CALL	NABUKB_PUT
	CALL	NABUKB_PUT
	CALL	NABUKB_PUT
	CALL	NABUKB_PUT
	CALL	NABUKB_PUT
	LD	A,$40		; RESET 8251
	CALL	NABUKB_PUT
	LD	A,$4E		; 1 STOP BIT, 8 BITS, 64X CLK
	CALL	NABUKB_PUT
	LD	A,$04		; ENABLE RECV
	CALL	NABUKB_PUT
;
#IF (INTMODE == 1)
	; ADD TO INTERRUPT CHAIN
	LD	HL,NABUKB_INT
	CALL	HB_ADDIM1		; ADD TO IM1 CALL LIST
#ENDIF
;
#IF (INTMODE == 2)
	; INSTALL VECTOR
	LD	HL,NABUKB_INT
	LD	(IVT(INT_NABUKB)),HL	; IVT INDEX
#ENDIF
;
	; ENABLE KEYBOARD INTERRUPTS ON NABU INTERRUPT CONTROLLER
	LD	A,14			; PSG R14 (PORT A DATA)
	OUT	(NABU_RSEL),A		; SELECT IT
	LD	A,(NABU_CTLVAL)		; GET NABU CTL PORT SHADOW REG
	SET	5,A			; ENABLE VDP INTERRUPTS
	LD	(NABU_CTLVAL),A		; UPDATE SHADOW REG
	OUT	(NABU_RDAT),A		; WRITE TO HARDWARE
;
	XOR	A
	RET
;
#IF (INTMODE > 0)
;
; INTERRUPT HANDLER FOR NABU KEYBOARD.  HANDLES INTERRUPTS FOR EITHER
; INT MODE 1 OR INT MODE 2.  THE KEYBOARD BUFFER IS JUST A SINGLE CHAR
; AT THIS POINT.  NEW CHARACTERS ARRIVING WHEN THE BUFFER IS FULL WILL
; BE DISCARDED.
;
NABUKB_INT:
	IN	A,(NABUKB_IOSTAT)	; GET KBD STATUS
	AND	$02			; CHECK DATA RDY BIT
	RET	Z			; ABORT W/ Z (INT NOT HANDLED)
;
	;CALL	PC_LT			; *DEBUG*
	IN	A,(NABUKB_IODAT)	; GET THE KEY
	LD	E,A			; STASH IN REG E
	;CALL	PRTHEXBYTE		; *DEBUG*
	;CALL	PC_GT			; *DEBUG*
;
	LD	A,(NABUKB_KSTAT)	; GET KEY BUFFER STAT
	OR	A			; SET FLAGS
	RET	NZ			; BUFFER FULL, BAIL OUT W/ NZ (INT HANDLED), KEY DISCARDED
;
	LD	A,E			; RECOVER THE KEY CODE
	CALL	NABUKB_XB		; TRANSLATE AND BUFFER KEY
	OR	$FF			; SIGNAL INT HANDLED
	RET				; DONE
;
#ENDIF
;
; NORMAL HBIOS CHAR INPUT STATUS.  IF INTERRUPTS ARE NOT ACTIVE, THEN
; KEYBOARD POLLING IS IMPLEMENTED HERE.
;
NABUKB_STAT:
	LD	A,(NABUKB_KSTAT)	; GET KEY WAITING STATUS
	OR	A			; SET FLAGS
#IF (INTMODE > 0)
	JR	Z,NABUKB_STATX		; BAIL OUT W/ Z (NO KEY)
	RET				; KEY WAITING, ALL SET
#ELSE
	RET	NZ			; KEY WAITING, ALL SET
	IN	A,(NABUKB_IOSTAT)	; GET KBD STATUS
	AND	$02			; CHECK DATA RDY BIT
	JR	Z,NABUKB_STATX		; BAIL OUT W/ Z (NO KEY)
	IN	A,(NABUKB_IODAT)	; GET THE KEY
	CALL	NABUKB_XB		; TRANSLATE AND BUFFER KEY
	LD	A,(NABUKB_KSTAT)	; GET NEW KEY WAITING STATUS
	OR	A			; SET FLAGS
	RET				; DONE
#ENDIF
;
NABUKB_STATX:
	XOR	A			; SIGNAL NO CHAR READY
	JP	CIO_IDLE		; RETURN VIA IDLE PROCESSOR
;
; ROUTINE TO TRANSLATE AND BUFFER INCOMING NABU KEYBOARD KEYCODES
;
NABUKB_XB:
	BIT	7,A			; HIGH BIT IS SPECIAL CHAR
	JR	Z,NABUKB_XB2		; IF NORMAL CHAR, BUFFER IT
	CP	$90			; START OF ERR CODES
	JR	C,NABUKB_XB1		; NOT ERR CODE, CONTINUE
	CP	$A0			; END OF ERR CODES
	JR	NC,NABUKB_XB1		; NOT ERR CODE, CONTINUE
	RET				; DISCARD ERR CODE AND RETURN
NABUKB_XB1:
	CP	$E0			; SPECIAL CHARACTER?
	JR	C,NABUKB_XB2		; IF NOT, SKIP XLAT, BUFFER KEY
	CALL	NABUKB_XLAT		; IF SO, TRANSLATE IT
	RET	C			; CF INDICATES INVALID, DISCARD AND RETURN
NABUKB_XB2:
	LD	(NABUKB_KEY),A		; BUFFER IT
	LD	A,1			; SIGNAL KEY WAITING
	LD	(NABUKB_KSTAT),A	; SAVE IT
	RET				; DONE
;
; ROUTINE TO TRANSLATE SPECIAL NABU KEYBOARD KEY CODES
;
NABUKB_XLAT:
	; NABU KEYBOARD USES $E0-$FF FOR SPECIAL KEYS
	; HERE WE TRANSLATE TO ROMWBW SPECIAL KEYS AS BEST WE CAN
	; CF IS SET ON RETURN IF KEY IS INVALID (NO TRANSLATION)
	SUB	$E0			; ZERO OFFSET
	RET	C			; ABORT IF < $E0, CF SET!
	LD	HL,NABUKB_XTBL		; POINT TO XLAT TABLE
	CALL	ADDHLA			; OFFSET BY SPECIAL KEY VAL
	LD	A,(HL)			; GET TRANSLATED VALUE
	OR	A			; CHECK FOR N/A (0)
	RET	NZ			; XLAT OK, RET W/ CF CLEAR
	SCF				; SIGNAL INVALID
	RET				; DONE
;
NABUKB_XLAT1:
	SCF				; SIGNAL INVALID
	RET				; AND DONE
;
; FLUSH KEYBOARD BUFFER
;
NABUKB_FLUSH:
	XOR	A
	LD	(NABUKB_KSTAT),A
	RET
;
; WAIT FOR A KEY TO BE READY AND RETURN IT.
;
NABUKB_READ:
	CALL	NABUKB_STAT		; CHECK FOR KEY READY
	JR	Z,NABUKB_READ		; LOOP TIL ONE IS READY
	LD	A,(NABUKB_KEY)		; GET THE BUFFERED KEY
	LD	E,A			; PUT IN E FOR RETURN
	XOR	A			; ZERO TO ACCUM
	LD	C,A			; NO SCANCODE
	LD	D,A			; NO KEYSTATE
	LD	(NABUKB_KSTAT),A	; CLEAR KEY WAITING STATUS
	RET				; AND RETURN
;
; HELPER ROUTINE TO WRITE 
;
NABUKB_PUT:
	OUT	(NABUKB_IOSTAT),A
	NOP
	NOP
	NOP
	NOP
	NOP
	RET
;
;
;
NABUKB_KSTAT	.DB	0	; KEY STATUS
NABUKB_KEY	.DB	0	; KEY BUFFER
;
; THIS TABLE TRANSLATES THE NABU KEYBOARD SPECIAL CHARS INTO
; ANALOGOUS ROMWBW STANDARD SPECIAL CHARACTERS.  THE TABLE STARTS WITH
; NABU KEY CODE $E0 AND HANDLES $20 POSSIBLE VALUES ($E0-$FF)
; THE SPECIAL KEYS SEND A SPECIFIC KEYCODE TO INDICATE DOWN (KEY
; PRESSED) AND UP (KEY RELEASED).  WE WILL ARBITRARILY CHOOSE TO
; RESPOND TO KEY PRESSED.  a TRANSLATION VALUE OF $00 MEANS THAT THE
; KEY CODE SHOULD BE DISCARDED.
;
NABUKB_XTBL:
	.DB	$F9		; $E0, RIGHT ARROW (DN) -> RIGHT ARROW
	.DB	$F8		; $E1, LEFT ARROW (DN) -> LEFT ARROW
	.DB	$F6		; $E2, UP ARROW (DN) -> UP ARROW
	.DB	$F7		; $E3, DOWN ARROW (DN) -> DOWN ARROW
	.DB	$F5		; $E4, PAGE RIGHT (DN) -> PAGE DOWN
	.DB	$F4		; $E5, PAGE LEFT (DN) -> PAGE UP
	.DB	$F3		; $E6, NO (DN) -> END
	.DB	$F2		; $E7, YES (DN) -> HOME
	.DB	$EE		; $E8, SYM (DN) -> SYSRQ
	.DB	$EF		; $E9, PAUSE (DN) -> PAUSE
	.DB	$00		; $EA, TV/NABU (DN) -> APP
	.DB	$00		; $EB, N/A
	.DB	$00		; $EC, N/A
	.DB	$00		; $ED, N/A
	.DB	$00		; $EE, N/A
	.DB	$00		; $EF, N/A
	.DB	$00		; $F0, RIGHT ARROW (UP)
	.DB	$00		; $F1, LEFT ARROW (UP)
	.DB	$00		; $F2, UP ARROW (UP)
	.DB	$00		; $F3, DOWN ARROW (UP)
	.DB	$00		; $F4, PAGE RIGHT (UP)
	.DB	$00		; $F5, PAGE LEFT (UP)
	.DB	$00		; $F6, NO (UP)
	.DB	$00		; $F7, YES (UP)
	.DB	$00		; $F8, SYM (UP)
	.DB	$00		; $F9, PAUSE (UP)
	.DB	$00		; $FA, TV/NABU (UP)
	.DB	$00		; $FB, N/A
	.DB	$00		; $FC, N/A
	.DB	$00		; $FD, N/A
	.DB	$00		; $FE, N/A
	.DB	$00		; $FF, N/A
