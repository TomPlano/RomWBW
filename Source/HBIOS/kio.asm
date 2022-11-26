;___KIO________________________________________________________________________________________________________________
;
; Z80 KIO
;
;   DISPLAY CONFIGURATION DETAILS
;______________________________________________________________________________________________________________________
;
THIS_DRV	.SET	DRV_ID_KIO
;
KIO_PIOADAT	.EQU	KIOBASE + $00
KIO_PIOACMD	.EQU	KIOBASE + $01
KIO_PIOBDAT	.EQU	KIOBASE + $02
KIO_PIOBCMD	.EQU	KIOBASE + $03
KIO_CTC0	.EQU	KIOBASE + $04
KIO_CTC1	.EQU	KIOBASE + $05
KIO_CTC2	.EQU	KIOBASE + $06
KIO_CTC3	.EQU	KIOBASE + $07
KIO_SIOADAT	.EQU	KIOBASE + $08
KIO_SIOACMD	.EQU	KIOBASE + $09
KIO_SIOBDAT	.EQU	KIOBASE + $0A
KIO_SIOBCMD	.EQU	KIOBASE + $0B
KIO_PIACDAT	.EQU	KIOBASE + $0C
KIO_PIACCMD	.EQU	KIOBASE + $0D
KIO_KIOCMD	.EQU	KIOBASE + $0E
KIO_KIOCMDB	.EQU	KIOBASE + $0F
;
;
;
KIO_PREINIT:
	CALL	KIO_DETECT
	RET	NZ
;
	; RECORD PRESENCE
	LD	A,$FF
	LD	(KIO_EXISTS),A
	; INITIALIZE KIO
	LD	A,%11111001	; RESET ALL DEVICES, SET DAISYCHAIN
	OUT	(KIO_KIOCMD),A	; DO IT
;
	XOR	A
	RET
;
;
;
KIO_INIT:
	; ANNOUNCE PORT
	CALL	NEWLINE			; FORMATTING
	PRTS("KIO:$")			; FORMATTING
;
	PRTS(" IO=0x$")			; FORMATTING
	LD	A,KIOBASE		; GET BASE PORT
	CALL	PRTHEXBYTE		; PRINT BASE PORT
;
	LD	A,(KIO_EXISTS)
	OR	A
	JR	Z,KIO_INIT2
;	
	PRTS(" ENABLED$")		; DISPLAY ENABLED
	XOR	A			; SIGNAL SUCCESS
	RET				; DONE
;
KIO_INIT2:
	PRTS(" NOT PRESENT$")		; NOT ZERO, H/W NOT PRESENT
	OR	$FF			; SIGNAL FAILURE
	RET				; BAIL OUT
;
;
;
KIO_DETECT:
	LD	C,KIO_SIOBCMD	; USE SIOB COMMAND PORT
	LD	B,2		; SIO REG 2
;
	OUT	(C),B
	XOR	A		; ZERO
	OUT	(C),A		; WRITE IT
	OUT	(C),B
	IN	A,(C)
	AND	$F0		; TOP NIBBLE ONLY
	RET	NZ		; FAIL IF NOT ZERO
;	
	OUT	(C),B
	LD	A,$FF		; $FF
	OUT	(C),A		; WRITE IT
	OUT	(C),B
	IN	A,(C)
	AND	$F0		; TOP NIBBLE ONLY
	CP	$F0		; COMPARE
	RET			; DONE, Z IF FOUND, NZ IF MISCOMPARE
;
;
;
KIO_EXISTS	.DB	0
