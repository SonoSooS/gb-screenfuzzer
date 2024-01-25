INCLUDE "hardware.inc"

DEF SUPPORT_DMG EQU 1
DEF SUPPORT_CGB EQU 0
DEF IS_RAMIMAGE EQU 0

DEF stack_main EQU $FFFF
DEF stack_one EQU stack_main - 2

SECTION "HRAM Data", HRAM[_HRAM]

IF IS_RAMIMAGE
HRAM_LFSR:
    DS 3
ENDC

LFSR_seed:
    DS 2

data_buffer:
    DS 3

VRAM_PTR:
    DS 2

SECTION "Main", ROM0[$150]
    
_start::
    ; A == 0 at this point
    ; C == 0 too (equivalent to $FF00 JOYP)
    
    LD SP, stack_main           ; just in case it's not in HRAM already (needed for T2)
    
    LDH [rLCDC], A              ; turn off LCD if on (A==0)
    LDH [rNR52], A              ; turn off APU if on to save power
    
    DEC A
    LDH [C], A                  ; deselect all button lines (unused, A==$FF)
    
    
    LD HL, _VRAM
    
    ; detect CGB or DMG
IF SUPPORT_CGB
IF SUPPORT_DMG
    LDH A, [rKEY1]
    INC A                       ; $FF on DMG, test if equals to that
    JR z, detect_dmg
ELSE
    RRA                         ; turn $FF into $7F
ENDC
    
    ; detected CGB instead of DMG
    LDH [rVBK], A               ; switch to VRAM1, only bit0 matters, guaranteed to be 1
    
    INC A                       
    LDH [rBGPI], A              ; should be A == $80 here
    
    XOR A                       ; clear VRAM1 eventually
    
VRAM_CLR_loop:
    LD [HL+], A
    BIT 1, H                    ; if HL > $9FFF
    JR z, VRAM_CLR_loop         ; loop until HL becomes $A000
    
    LDH [rVBK], A               ; reset VBK back to 0 so the rest of the program works
    
    LD C, LOW(rBGPD)
    
    ; clear first palette of BGP (works because VRAM1 is clear)
    ; loop unrolling uses less bytes here due to not having to reload loop counter
    
    DEC A                       ; A = $FF
    LDH [C], A
    LDH [C], A
    LDH [C], A
    LDH [C], A
    
    INC A                       ; A = $00
    LDH [C], A
    LDH [C], A
    LDH [C], A
    LDH [C], A
    
    ; fallthrough, doesn't hurt to take DMG path as well
detect_dmg:
    LD C, A                     ; C = 0
    
    ; the fun starts here, set up VRAM
    LD H, HIGH(_VRAM)           ; L is already $00
    
ENDC
    
IF SUPPORT_DMG
    LD A, $F0
    LDH [rBGP], A
ENDC
    
VRAM_fill_loop_outter:
    LD B, 8                     ; block row counter (8x lines in a tile)
    LD A, C                     ; pattern start = tile index
    
VRAM_fill_loop_inner:
    LD [HL+], A
    LD [HL+], A
    INC A
    DEC B
    JR nz, VRAM_fill_loop_inner
    
    INC C
    JR nz, VRAM_fill_loop_outter
    
    
IF IS_RAMIMAGE
    ; set up PC-relative hell, LFSR, and others
    LD A, $C9                   ; RET
    LDH [_HRAM], A
    CALL _HRAM
PC_relative::
    
    ; retrieve PC
    LD HL, SP - 2
    LD A, [HL+]
    LD H, [HL]
    LD L, A
    
    LD DE, ROM_LFSR - PC_relative
    ADD HL, DE                  ; HL should point to ROM_LFSR
    
    LD A, $C3                   ; JP n16
    LDH [HRAM_LFSR+0], A
    LD A, L
    LDH [HRAM_LFSR+1], A
    LD A, H
    LDH [HRAM_LFSR+2], A
ELSE
DEF HRAM_LFSR EQUS "ROM_LFSR"
ENDC
    
    ; everything else is set up, ready to set up the state before the main loop
    LD A, STATF_MODE00
    LDH [rSTAT], A
    LD A, LCDCF_ON | LCDCF_BGON | LCDCF_BG8000
    LDH [rLCDC], A
    
    LD A, IEF_STAT | IEF_VBLANK
    LDH [rIE], A
    
    XOR A
    LDH [rIF], A
    
    LD H, $FF                   ; HL = $FFxx
    
    LD E, H                     ; set DE to anything but zero
    
reset_screen:
    LD B, HIGH(_SCRN0)          ; dst ptr
    
main_loop:
    LD L, LOW(rIF)
    DB $76, $00                 ; HALT with NOP due to weird HALT bug
    
    BIT 0, [HL]                 ; is VBlank instead of anything else?
    JR nz, handle_VBL
    
    ; anything but VBlank (only HBlank currently)
handle_CC:
    ; timing-sensitive!
    
    LD [HL], C                  ; reset IF here back to (C ==) 0 so VBlank can fire without being discarded
    
    LDH A, [data_buffer+0]
    LDH [rSCY], A
    
    LD L, LOW(VRAM_PTR)
    LD C, [HL]
    LDH A, [data_buffer+1]
    LD [BC], A
    LDH [rSCX], A
    
    INC BC
    LD [HL], C
    BIT 2, B                    ; BC > $9BFF
    JR nz, reset_screen
    
    LD L, LOW(data_buffer)
    LD C, 3
    CALL HRAM_LFSR              ; C will be 0 after this call
    
    JR main_loop
    
handle_VBL:
    LD [HL], C                  ; C is always 0 here
    
    JR main_loop
    
ROM_LFSR:: ; DE = seed, HL = dst, C = count
    LD A, D                     ; 1c
.loop:
    RRA                         ; 1c
    LD A, E                     ; 1c
    RRA                         ; 1c
    XOR D                       ; 1c 
    LD D, A                     ; 1c
    LD A, E                     ; 1c
    RRA                         ; 1c
    LD A, D                     ; 1c
    RRA                         ; 1c
    XOR E                       ; 1c
    LD E, A                     ; 1c
    
    LD [HL+], A                 ; 2c 1b
    
    XOR D                       ; 1c
    
    DEC C                       ; 1c
    JR nz, .loop                ; 2c/3c 2b
    
    LD D, A                     ; 1c
    RET                         ; 4c 1b
    
    ; inner loop:   20c (80dot)
    
    ; w/ extra:     +5c
    ; w/ JP:        +4c
    ; w/ CALL:      +6c
    ; total cost:   +15c
    
    ; one line:     114c    (456dot)
    ; VRAM access:  71c
    
    ; 1:            35c     (140dot)
    ; 2:            55c     (220dot)
    ; 8:            175c
    ; 20:           415c
    
    ; total ROM:    20b
.end:
    
