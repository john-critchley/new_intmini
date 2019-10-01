;==================================================================================
; Contents of this file are copyright Grant Searle
;
; You have permission to use this for NON COMMERCIAL USE ONLY
; If you wish to use it elsewhere, please include an acknowledgement to myself.
;
; http://searle.hostei.com/grant/index.html
;
; eMail: home.micros01@btinternet.com
;
; If the above don't work, please perform an Internet search to see if I have
; updated the web page hosting service.
;
;==================================================================================

; Minimum 6850 ACIA interrupt driven serial I/O to run modified NASCOM Basic 4.7
; Full input buffering with incoming data hardware handshaking
; Handshake shows full before the buffer is totally filled to allow run-on from the sender

SER_BUFSIZE:      EQU     3FH
SER_FULLSIZE:     EQU     30H
SER_EMPTYSIZE:    EQU     5

RTS_HIGH:         EQU     0D6H
RTS_LOW:          EQU     096H

serBuf:           EQU     $8000
serInPtr:         EQU     serBuf+SER_BUFSIZE
serRdPtr:         EQU     serInPtr+2
serBufUsed:       EQU     serRdPtr+2
basicStarted:     EQU     serBufUsed+1
TEMPSTACK:        EQU     $80ED ; Top of BASIC line input buffer so is "free ram" when BASIC resets

CR:               EQU     0DH
LF:               EQU     0AH
CS:               EQU     0CH             ; Clear screen

fill:          	EQU        $FF
RST00:         	EQU        $0000
RST08:         	EQU        $0008
RST10:         	EQU        $0010
RST18:         	EQU        $0018
RST20:         	EQU        $0020
RST28:         	EQU        $0028
RST30:         	EQU        $0030
RST38:         	EQU        $0038
NMI:		EQU	   $0066
R20:		EQU	$FFD0
R28:		EQU	$FFE0
RN:		EQU	$fff0

StartBASICCOLD:EQU       $0150

               ORG        RST00
;------------------------------------------------------------------------------
; Reset

                DS      RST00-$, fill
;               DI                       ;Disable interrupts
                JP       INIT            ;Initialize Hardware and go

;------------------------------------------------------------------------------
; TX a character over RS232 

                DS      RST08-$, fill
                ORG     RST08
                JR      TXA

;------------------------------------------------------------------------------
; RX a character over RS232 Channel A [Console], hold here until char ready.

                DS      RST10-$, fill
                ORG     RST10
                JP      RXA

;------------------------------------------------------------------------------
; Check serial status

                DS      RST18-$, fill
                ORG     RST18
;------------------------------------------------------------------------------
CKINCHAR:       LD       A,(serBufUsed)
                CP       $0
                RET


                DS      RST20-$, fill
                ORG     RST20
		JR	R20

                DS      RST28-$, fill
                ORG     RST28
		JR	R28

                DS      RST30-$, fill
                ORG     RST30
PRINT:          LD       A,(HL)          ; Get character
                OR       A               ; Is it $00 ?
                RET      Z               ; Then RETurn on terminator
                RST      08H             ; Print it
                INC      HL              ; Next Character
                JR       PRINT           ; Continue until $00
                RET

                DS      RST38-$, fill
;------------------------------------------------------------------------------
; RST 38 - INTERRUPT VECTOR [ for IM 1 ]

                ORG     RST38
;                JR      serialInt       

;------------------------------------------------------------------------------
serialInt:      PUSH     AF
                PUSH     HL

                IN       A,($80)
                AND      $01             ; Check if interupt due to read buffer full
                JR       Z,rts0          ; if not, ignore

                IN       A,($81)
                PUSH     AF
                LD       A,(serBufUsed)
                CP       SER_BUFSIZE     ; If full then ignore
                JR       NZ,notFull
                POP      AF
                JR       rts0
;------------------------------------------------------------------------------
TXA:            PUSH     AF              ; Store character
conout1:        IN       A,($80)         ; Status byte       
                BIT      1,A             ; Set Zero flag if still transmitting character       
                JR       Z,conout1       ; Loop until flag signals ready
                POP      AF              ; Retrieve character
                OUT      ($81),A         ; Output the character
                RET

;------------------------------------------------------------------------------


SIGNON3:       DB     "& John C",CR,LF,0

		DS	 NMI-$,fill
		PUSH     AF
                LD       A,(basicStarted)
		CP	 'y'
		CALL	 Z,RN
                POP      AF
                RETI
 
notFull:        LD       HL,(serInPtr)
                INC      HL
                LD       A,L             ; Only need to check low byte becasuse buffer<256 bytes
                CP       (serBuf+SER_BUFSIZE) & $FF
                JR       NZ, notWrap
                LD       HL,serBuf
notWrap:        LD       (serInPtr),HL
                POP      AF
                LD       (HL),A
                LD       A,(serBufUsed)
                INC      A
                LD       (serBufUsed),A
                CP       SER_FULLSIZE
                JR       C,rts0
                LD       A,RTS_HIGH
                OUT      ($80),A
rts0:           POP      HL
                POP      AF
                EI
                RETI

;------------------------------------------------------------------------------
RXA:
waitForChar:    LD       A,(serBufUsed)
                CP       $00
                JR       Z, waitForChar
                PUSH     HL
                LD       HL,(serRdPtr)
                INC      HL
                LD       A,L             ; Only need to check low byte becasuse buffer<256 bytes
                CP       (serBuf+SER_BUFSIZE) & $FF
                JR       NZ, notRdWrap
                LD       HL,serBuf
notRdWrap:      DI
                LD       (serRdPtr),HL
                LD       A,(serBufUsed)
                DEC      A
                LD       (serBufUsed),A
                CP       SER_EMPTYSIZE
                JR       NC,rts1
                LD       A,RTS_LOW
                OUT      ($80),A
rts1:
                LD       A,(HL)
                EI	; XXX Whats this EI for?
                POP      HL
                RET                      ; Char ready in A

;------------------------------------------------------------------------------
INIT:
               LD        SP,TEMPSTACK    ; Set up a temporary stack
               LD        HL,serBuf
               LD        (serInPtr),HL
               LD        (serRdPtr),HL
               XOR       A               ;0 to accumulator
               LD        (serBufUsed),A
               LD        A,RTS_LOW
               OUT       ($80),A         ; Initialise ACIA
               IM        1
               EI
               LD        HL,SIGNON1      ; Sign-on message
               RST       PRINT           ; Output string
               LD        HL,SIGNON3      ; Sign-on message
               RST       PRINT           ; Output string
               LD        A,(basicStarted); Check the BASIC STARTED flag
               AND       $DF
               CP        'Y'             ; to see if this is power-up
               JR        NZ,COLDSTART    ; If not BASIC started then always do cold start
               LD        HL,SIGNON2      ; Cold/warm message
               RST       PRINT           ; Output string
CORW:
               RST	 RST10
               AND       %11011111       ; lower to uppercase
               CP        'C'
               JR        NZ, CHECKWARM
               RST       08H
               LD        A,$0D
               RST       08H
               LD        A,$0A
               RST       08H
COLDSTART:     LD        A,'Y'           ; Set the BASIC STARTED flag
               LD        (basicStarted),A
               JR        StartBASICCOLD
CHECKWARM:     CP        'W'
               JR        NZ, CORW
               RST       08H
               LD        A,$0D
               RST       08H
               LD        A,$0A
               RST       08H
               JR        $0153           ; Start BASIC WARM
              
SIGNON1:       DB     CS, "Z80 SBC By Grant Searle",CR,LF,0
SIGNON2:       DB     CR,LF,"Cold or warm start (C or W)? ",0
              
               DS      StartBASICCOLD-$, fill
