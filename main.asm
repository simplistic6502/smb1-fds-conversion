;-------------------------------------------------------------------------------------
;DEFINES

PPU_CTRL              = $2000
PPU_MASK              = $2001
PPU_STATUS            = $2002
PPU_SCROLL            = $2005
PPU_ADDR              = $2006
PPU_DATA              = $2007

DMC_FREQ              = $4010
APU_STATUS            = $4015
JOY1                  = $4016
JOY2_FRAME            = $4017

;-------------------------------------------------------------------------------------
;DIRECTIVES

;iNES header
  .db $4E,$45,$53,$1A                           ;  magic signature
  .db 4                                         ;  PRG ROM size in 16384 byte units
  .db 0                                         ;  CHR
  .db $11                                       ;  mirroring type and mapper number lower nibble
  .db $00                                       ;  mapper number upper nibble
  .db $00,$00,$00,$00,$00,$00,$00,$00           ;  padding

.fillvalue $ff

;-------------------------------------------------------------------------------------
;BANK 0
;contents are written to PRG-RAM and CHR-RAM

.org $8000
	.incbin "prg.bin",$0,$2000	;$6000-$7FFF from FDS version
	.incbin "conversion.chr"    ;CHR data

;-------------------------------------------------------------------------------------
;BANK 1
;empty bank

.pad $fff3
	sei             ;reset stub in case MMC1 defaults to PRG-ROM bank mode 0 or 1
	inc ResetStub+1 ;reset MMC1
	jmp Reset
	.dw NMI         ;nmi
    .dw ResetStub   ;reset
    .dw $fff0       ;unused

;-------------------------------------------------------------------------------------
;BANKS 2 & 3
;game code and init routine

.base $8000
	.incbin "prg.bin",$2000	;$6000-$7FFF from FDS version
.pad $e000,$ff

Reset:
	lda #%00001110			;init MMC1 mapper (vertical mirroring & PRG-ROM bank mode 3)
	sta $8000
	lsr
	sta $8000
	lsr
	sta $8000
	lsr
	sta $8000
	lsr
	sta $8000

	lda #$10				;replicate init code present in FDS BIOS
	sta PPU_CTRL
	cld
	lda #$06
	sta PPU_MASK
	ldx #$02
VBlank:
	lda PPU_STATUS
	bpl VBlank
	dex
	bne VBlank
	stx JOY1
	stx DMC_FREQ
	lda #$c0
	sta JOY2_FRAME
	lda #$0f
	sta APU_STATUS
	ldx #$ff
	txs

	lda #$c0
	sta $0100              ;PC action on NMI
	lda #$80
	sta $0101              ;PC action on IRQ
	lda $0102              ;mimic warm boot check in FDS BIOS
	cmp #$35
	bne ColdBoot           ;$0102 must be $35 for a warm boot
	lda $0103
	cmp #$53
	beq WarmBoot           ;$0103 will be $53 if game was soft-reset
	cmp #$ac
	bne ColdBoot           ;$0103 will be $ac if first boot of game
	lda #$53               ;if $0103 is $ac, change to $53 to indicate
	sta $0103              ;that the user did a soft-reset
	bne WarmBoot           ;unconditional branch to run the game

ColdBoot:
    lda #$35               ;cold boot, must init PRG-RAM and CHR-RAM
	sta $0102              ;PC action on reset
	lda #$ac
	sta $0103              ;PC action on reset
	lda #$00               ;load bank 0
	jsr SelectBank
	sta $00                ;low byte of CHR offset
	sta $02                ;low byte of PRG-RAM
	lda #$80
	sta $01                ;high byte of CHR offset
	lda #$60
	sta $03                ;high byte of PRG-RAM
	ldx #32                ;number of pages
PRGLoop:
	lda ($00),y            ;copy byte from ROM
	sta ($02),y            ;store in PRG-RAM
	iny
	bne PRGLoop            ;loop until page is finished
	inc $01                ;increment for next page
	inc $03
	dex
	bne PRGLoop            ;loop until all of $6000-$7fff is stored
	lda #$a0               ;now load offset for CHR data
	sta $01                ;high byte of CHR offset
	sty PPU_MASK           ;turn off rendering for good measure
	sty PPU_ADDR           ;load destination address into PPU
	sty PPU_ADDR
	ldx #32                ;number of pages
CHRLoop:
	lda ($00),y            ;copy byte from ROM
	sta PPU_DATA           ;store to PPU
	iny
	bne CHRLoop            ;loop until page is finished
	inc $01                ;increment for next page
	dex
	bne CHRLoop            ;loop until all CHR data is stored
WarmBoot:	
	lda #$02               ;load game bank
	jsr SelectBank
	lda PPU_STATUS         ;FDS BIOS stuff
	lda #$00
	sta PPU_SCROLL
	sta PPU_SCROLL
	lda #$10
	sta PPU_STATUS
	cli
	jmp ($dffc)            ;run game

;-------------------------------------------------------------------------------------

.org $e149

Delay132:
	pha
	lda #$16
	sec
DelayLoop:
	sbc #$01
	bcs DelayLoop
	pla
	rts

;-------------------------------------------------------------------------------------

.org $e18b

NMI:
	bit $0100
	bpl prg_e198
	bvc prg_e195
	jmp ($dffa)
prg_e195:
	jmp ($dff8)
prg_e198:
	bvc prg_e19d
	jmp ($dff6)
prg_e19d:
	lda $ff
	and #$7f
	sta $ff
	sta PPU_CTRL
	lda PPU_STATUS
	pla
	pla
	pla
	pla
	sta $0100
	pla
	rts

;-------------------------------------------------------------------------------------

.org $e1c7

IRQ:
	bit $0101	;we shouldn't end up here, but why not?
	bmi prg_e1ea
	bvc prg_e1d9
	ldx $4031
	ldx $4024
	pla
	pla
	pla
	txa
	rts
prg_e1d9:
	pha
	lda $0101
	sec
	sbc #$01
	bcc prg_e1e8
	sta $0101
	lda $4031
prg_e1e8:
	pla
	rti
prg_e1ea:
	bvc prg_e1ef
	jmp ($dffe)
prg_e1ef:
	pha
	lda $4030
	jsr Delay132
	pla
	rti

;-------------------------------------------------------------------------------------

.org $ffdf,$ff
SelectBank:
	sta $e000
	lsr
	sta $e000
	lsr
	sta $e000
	lsr
	sta $e000
	lsr
	sta $e000
	rts	

ResetStub:
	sei             ;reset stub
	inc ResetStub+1 ;reset MMC1
	jmp Reset
	.dw NMI         ;nmi
    .dw ResetStub   ;reset
    .dw IRQ         ;unused