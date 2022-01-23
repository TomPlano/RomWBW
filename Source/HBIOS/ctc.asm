;___CTC________________________________________________________________________________________________________________
;
; Z80 CTC
;
;   DISPLAY CONFIGURATION DETAILS
;______________________________________________________________________________________________________________________
;
CTC_DEFCFG	.EQU	%01010011	; CTC DEFAULT CONFIG
CTC_CTRCFG	.EQU	%01010111	; CTC COUNTER MODE CONFIG
CTC_TIM16CFG	.EQU	%00010111	; CTC TIMER/16 MODE CONFIG
CTC_TIM256CFG	.EQU	%00110111	; CTC TIMER/256 MODE CONFIG
CTC_TIMCFG	.EQU	%11010111	; CTC TIMER CHANNEL CONFIG
		;	 |||||||+-- CONTROL WORD FLAG
		;	 ||||||+--- SOFTWARE RESET
		;	 |||||+---- TIME CONSTANT FOLLOWS
		;	 ||||+----- AUTO TRIGGER WHEN TIME CONST LOADED
		;	 |||+------ RISING EDGE TRIGGER
		;	 ||+------- TIMER MODE PRESCALER (0=16, 1=256)
		;	 |+-------- COUNTER MODE
		;	 +--------- INTERRUPT ENABLE
;
#IF (INTMODE != 2)
	.ECHO	"*** WARNING: CTC TIMER DISABLED -- INTMODE 2 REQUIRED!!!\n"
#ENDIF
;
#IF (CTCTIMER & (INTMODE == 2))
;
  #IF (INT_CTC0A % 4)
  
	.ECHO	INT_CTC0A
	.ECHO	"\n"
	.ECHO	(INT_CTC0A % 4)
	.ECHO	"\n"
  
	.ECHO	"*** ERROR: CTC BASE VECTOR NOT /4 ALIGNED!!!\n"
	!!!	; FORCE AN ASSEMBLY ERROR
  #ENDIF
;
; ONLY IM2 IMPLEMENTED BELOW.  I DON'T SEE ANY REASONABLE WAY TO
; IMPLEMENT AN IM1 TIMER BECAUSE THE CTC PROVIDES NO WAY TO
; DETERMINE IF IT WAS THE CAUSE OF AN INTERRUPT OR A WAY TO
; DETERMINE WHICH CHANNEL CAUSED AN INTERRUPT.
;  
CTC_PREIO	.EQU	CTCBASE + CTCPRECH
CTC_SCLIO	.EQU	CTCBASE + CTCTIMCH
;
  #IF (CTCMODE == CTCMODE_CTR)
CTC_PRECFG	.EQU	CTC_CTRCFG
CTC_PRESCL	.EQU	1
  #ENDIF
  #IF (CTCMODE == CTCMODE_TIM16)
CTC_PRECFG	.EQU	CTC_TIM16CFG
CTC_PRESCL	.EQU	16
  #ENDIF
  #IF (CTCMODE == CTCMODE_TIM256)
CTC_PRECFG	.EQU	CTC_TIM256CFG
CTC_PRESCL	.EQU	256
  #ENDIF
;
CTC_DIV		.EQU	CTCOSC / CTC_PRESCL / TICKFREQ
;
CTC_DIVHI	.EQU	CTCPRE
CTC_DIVLO	.EQU	(CTC_DIV / CTC_DIVHI)
;
	.ECHO "CTC DIVISOR: "
	.ECHO CTC_DIV
	.ECHO ", HI: "
	.ECHO CTC_DIVHI
	.ECHO ", LO: "
	.ECHO CTC_DIVLO
	.ECHO "\n"
;
  #IF ((CTC_DIV == 0) | (CTC_DIV > $FFFF))
	.ECHO "COMPUTED CTC DIVISOR IS UNUSABLE!\n"
	!!!
  #ENDIF
;
  #IF ((CTC_DIVHI > $100) | (CTC_DIVLO > $100))
	.ECHO "COMPUTED CTC DIVISOR IS UNUSABLE!\n"
	!!!
  #ENDIF
;
  #IF ((CTC_DIVHI * CTC_DIVLO * CTC_PRESCL * TICKFREQ) != CTCOSC)
	.ECHO "COMPUTED CTC DIVISOR IS UNUSABLE!\n"
	!!!
  #ENDIF
;
CTCTIVT		.EQU	INT_CTC0A + CTCTIMCH
;
#ENDIF
;
;
;
CTC_PREINIT:
	CALL	CTC_DETECT		; DO WE HAVE ONE?
	LD	(CTC_EXIST),A		; SAVE IT
	RET	NZ			; ABORT IF NONE
;
	; RESET ALL CTC CHANNELS
	LD	B,4			; 4 CHANNELS
	LD	C,CTCBASE		; FIRST CHANNEL PORT
CTC_PREINIT1:
	LD	A,CTC_DEFCFG		; CTC DEFAULT CONFIG
	OUT	(C),A			; CTC COMMAND
	INC	C			; NEXT CHANNEL PORT
	DJNZ	CTC_PREINIT1
;
#IF (CTCTIMER & (INTMODE == 2))
	; SETUP TIMER INTERRUPT IVT SLOT
	LD	HL,HB_TIMINT		; TIMER INT HANDLER ADR
	LD	(IVT(CTCTIVT)),HL	; IVT ENTRY FOR TIMER CHANNEL
;
	; CTC USES 4 CONSECUTIVE VECTOR POSITIONS, ONE FOR
	; EACH CHANNEL.  BELOW WE SET THE BASE VECTOR TO THE
	; START OF THE IVT, SO THE FIRST FOUR ENTIRES OF THE
	; IVT CORRESPOND TO CTC CHANNELS A-D.
	LD	A,INT_CTC0A * 2
	OUT	(CTCBASE),A		; SETUP CTC BASE INT VECTOR
;
	; IN ORDER TO DIVIDE THE CTC INPUT CLOCK DOWN TO THE
	; DESIRED PERIODIC INTERRUPT, WE NEED TO CONFIGURE ONE
	; CTC CHANNEL AS A PRESCALER AND ANOTHER AS THE ACTUAL
	; TIMER INTERRUPT.  THE PRESCALE CHANNEL OUTPUT MUST BE WIRED
	; TO THE TIMER CHANNEL TRIGGER INPUT VIA HARDWARE.
	LD	A,CTC_PRECFG		; PRESCALE CHANNEL CONFIGURATION
	OUT	(CTC_PREIO),A		; SETUP PRESCALE CHANNEL
	LD	A,CTC_DIVHI & $FF	; PRESCALE CHANNEL CONSTANT
	OUT	(CTC_PREIO),A		; SET PRESCALE CONSTANT
;
	LD	A,CTC_TIMCFG		; TIMER CHANNEL CONTROL WORD VALUE
	OUT	(CTC_SCLIO),A		; SETUP TIMER CHANNEL
	LD	A,CTC_DIVLO & $FF	; TIMER CHANNEL CONSTANT
	OUT	(CTC_SCLIO),A		; SET TIMER CONSTANT
;
#ENDIF
;
	XOR	A
	RET
;
;
;
CTC_INIT:				; MINIMAL INIT
CTC_PRTCFG:
	; ANNOUNCE PORT
	CALL	NEWLINE			; FORMATTING
	PRTS("CTC:$")			; FORMATTING
;
	PRTS(" IO=0x$")			; FORMATTING
	LD	A,CTCBASE		; GET BASE PORT
	CALL	PRTHEXBYTE		; PRINT BASE PORT
;
	LD	A,(CTC_EXIST)		; IS IT THERE?
	OR	A			; 0 MEANS YES
	JR	Z,CTC_PRTCFG1		; IF SO, CONTINUE
;
	; NOTIFY NO CTC HARDWARE
	PRTS(" NOT PRESENT$")
	OR	$FF
	RET
;
CTC_PRTCFG1:
;
#IF (CTCTIMER & (INTMODE == 2))
;
	PRTS(" TIMER MODE=$")			; FORMATTING
  #IF (CTCMODE == CTCMODE_CTR)
	PRTS("CTR$")
  #ENDIF
  #IF (CTCMODE == CTCMODE_TIM16)
	PRTS("TIM16$")
  #ENDIF
  #IF (CTCMODE == CTCMODE_TIM256)
	PRTS("TIM256$")
  #ENDIF
;
	PRTS(" DIVHI=$")
	LD	A,CTC_DIVHI & $FF
	CALL	PRTHEXBYTE
;
	PRTS(" DIVLO=$")
	LD	A,CTC_DIVLO & $FF
	CALL	PRTHEXBYTE
;
  #IF (CTCDEBUG)
	PRTS(" PREIO=$")
	LD	A,CTC_PREIO
	CALL	PRTHEXBYTE
;
	PRTS(" SCLIO=$")
	LD	A,CTC_SCLIO
	CALL	PRTHEXBYTE
;
	PRTS(" DIV=$")
	LD	BC,CTC_DIV
	CALL	PRTHEXWORD
  #ENDIF
;
#ENDIF
;
	XOR	A
	RET
;
;
;
CTC_DETECT:
	LD	A,CTC_TIM256CFG
	OUT	(CTCBASE),A
	XOR	A
	OUT	(CTCBASE),A
	; CTC SHOULD NOW BE RUNNING WITH TIME CONSTANT 0
	LD	A,CTC_TIM256CFG		; RESET
	OUT	(CTCBASE),A
	IN	A,(CTCBASE)		; SHOULD READ 0 NOW
	CP	0
	JR	NZ,CTC_NO
	LD	A,$FF			; TIME CONSTANT $FF
	OUT	(CTCBASE),A
	IN	A,(CTCBASE)		; SHOULD NOT BE 0 NOW
	CP	0
	JR	Z,CTC_NO
	XOR	A
	RET
CTC_NO:
	OR	$FF
	RET
;
;
;
CTC_EXIST	.DB	$FF	
