; =============================================================================
; SHOWNXI - ZX Spectrum Next dot command
; Credit: Shrek/MB Maniax 2026
; Build:  sjasmplus --raw=shownxi shownxi.asm
; =============================================================================

    ORG $2000

NEXTREG_SEL      EQU $243B
NEXTREG_DAT      EQU $253B

NR_LAYER2_PAGE   EQU $12
NR_DISPLAY_CTRL1 EQU $69
NR_LAYER2_CTRL   EQU $70
NR_MMU2          EQU $52
NR_MMU3          EQU $53
NR_PALETTE_IDX   EQU $40
NR_PALETTE_VAL   EQU $41
NR_PALETTE_VAL9  EQU $44
NR_PALETTE_CTRL  EQU $43

F_OPEN           EQU $9A
F_CLOSE          EQU $9B
F_READ           EQU $9D
FA_READ          EQU $01

SIZE_IMAGE       EQU 49152
SIZE_PALETTE     EQU 512
CHUNK            EQU 256

; =============================================================================
MAIN:
; =============================================================================
    ld      (arg_ptr), hl

    ld      hl, (arg_ptr)
    call    EXTRACT_FILENAME
    jp      c, SHOW_HELP

    ld      a, (filename_buf)
    or      a
    jp      z, SHOW_HELP

    cp      '-'
    jr      nz, .not_help
    ld      a, (filename_buf+1)
    and     $DF
    cp      'H'
    jp      z, SHOW_HELP
.not_help:

    ; Uloz puvodni MMU2/MMU3 a zjisti startovni 16K banku Layer 2
    call    SAVE_MMU_SLOTS
    call    GET_L2_BASE_BANK

    ; Otevri soubor
    ld      hl, filename_buf
    ld      a, '*'
    ld      b, FA_READ
    rst     $08
    defb    F_OPEN
    jp      c, .err_open

    ld      (file_handle), a

    ; Priprav Layer 2 rezim 256x192
    call    L2_INIT_256

    ; Nacti 3x16K obraz do aktualnich Layer 2 bank
    ld      a, (l2_base_bank)
    call    READ_16K_TO_L2
    jp      c, .err_read

    ld      a, (l2_base_bank)
    inc     a
    call    READ_16K_TO_L2
    jp      c, .err_read

    ld      a, (l2_base_bank)
    add     a, 2
    call    READ_16K_TO_L2
    jp      c, .err_read

    ; Obnov MMU, aby byl videt palette_buf
    call    RESTORE_MMU_SLOTS

    ; Pokus o doceteni 512B palety
    ld      a, (file_handle)
    ld      hl, palette_buf
    ld      bc, SIZE_PALETTE
    rst     $08
    defb    F_READ
    jr      c, .no_palette

    ; BC = bytes actually read, paleta je volitelna
    ld      a, b
    cp      2
    jr      nz, .no_palette
    ld      a, c
    or      a
    jr      nz, .no_palette

    call    UPLOAD_PALETTE

.no_palette:
    ld      a, (file_handle)
    rst     $08
    defb    F_CLOSE

    call    L2_SHOW
    ld      bc, 0
    ret

.err_open:
    push    af
    ld      hl, msg_err_open
    call    PRINT_MSG
    ld      hl, filename_buf
    call    PRINT_ASCIIZ_SAFE
    call    PRINT_NL
    ld      hl, msg_errcode
    call    PRINT_MSG
    pop     af
    call    PRINT_HEX8
    call    PRINT_NL
    call    DECODE_ERRCODE
    ld      bc, 0
    ret

.err_read:
    push    af
    call    RESTORE_MMU_SLOTS
    ld      a, (file_handle)
    rst     $08
    defb    F_CLOSE
    ld      hl, msg_err_read
    call    PRINT_MSG
    pop     af
    call    PRINT_HEX8
    call    PRINT_NL
    ld      bc, 0
    ret

; =============================================================================
; SAVE / RESTORE MMU2, MMU3
; =============================================================================
SAVE_MMU_SLOTS:
    ld      bc, NEXTREG_SEL
    ld      a, NR_MMU2
    out     (c), a
    ld      bc, NEXTREG_DAT
    in      a, (c)
    ld      (saved_mmu2), a

    ld      bc, NEXTREG_SEL
    ld      a, NR_MMU3
    out     (c), a
    ld      bc, NEXTREG_DAT
    in      a, (c)
    ld      (saved_mmu3), a
    ret

RESTORE_MMU_SLOTS:
    ld      bc, NEXTREG_SEL
    ld      a, NR_MMU2
    out     (c), a
    ld      bc, NEXTREG_DAT
    ld      a, (saved_mmu2)
    out     (c), a

    ld      bc, NEXTREG_SEL
    ld      a, NR_MMU3
    out     (c), a
    ld      bc, NEXTREG_DAT
    ld      a, (saved_mmu3)
    out     (c), a
    ret

; =============================================================================
; GET_L2_BASE_BANK
; nacte startovni 16K banku Layer 2 z NextReg $12
; =============================================================================
GET_L2_BASE_BANK:
    ld      bc, NEXTREG_SEL
    ld      a, NR_LAYER2_PAGE
    out     (c), a
    ld      bc, NEXTREG_DAT
    in      a, (c)
    and     $7F
    ld      (l2_base_bank), a
    ret

; =============================================================================
; READ_16K_TO_L2
; In: A = 16K banka Layer 2
; =============================================================================
READ_16K_TO_L2:
    ; prepocet 16K banky na dve 8K MMU pages
    add     a, a
    ld      (page_lo), a
    inc     a
    ld      (page_hi), a

    ld      hl, $4000
    ld      (dest_ptr), hl

    ld      b, 64                       ; 64 * 256 = 16K

.loop:
    push    bc

    ; vrat MMU do puvodniho stavu kvuli F_READ do scratch_buf
    call    RESTORE_MMU_SLOTS

    ld      a, (file_handle)
    ld      hl, scratch_buf
    ld      bc, CHUNK
    rst     $08
    defb    F_READ
    jr      c, .err

    ; BC = bytes actually read, musi byt presne 256
    ld      a, b
    cp      1
    jr      nz, .short_read
    ld      a, c
    or      a
    jr      nz, .short_read

    ; namapuj cilovou 16K L2 banku do $4000-$7FFF
    ld      bc, NEXTREG_SEL
    ld      a, NR_MMU2
    out     (c), a
    ld      bc, NEXTREG_DAT
    ld      a, (page_lo)
    out     (c), a

    ld      bc, NEXTREG_SEL
    ld      a, NR_MMU3
    out     (c), a
    ld      bc, NEXTREG_DAT
    ld      a, (page_hi)
    out     (c), a

    ; kopie 256B do aktualne namapovane L2 RAM
    ld      hl, scratch_buf
    ld      de, (dest_ptr)
    ld      bc, CHUNK
    ldir

    ; posun write pointer
    ld      hl, (dest_ptr)
    ld      bc, CHUNK
    add     hl, bc
    ld      (dest_ptr), hl

    pop     bc
    djnz    .loop

    or      a
    ret

.short_read:
    pop     bc
    scf
    ret

.err:
    pop     bc
    scf
    ret

; =============================================================================
; Layer 2 setup / show
; =============================================================================
L2_INIT_256:
    ; $70 bits 1..0 = 00 => 256x192x8
    ld      bc, NEXTREG_SEL
    ld      a, NR_LAYER2_CTRL
    out     (c), a
    ld      bc, NEXTREG_DAT
    xor     a
    out     (c), a
    ret

L2_SHOW:
    ; Display Control 1, bit 7 = Layer 2 visible
    ld      bc, NEXTREG_SEL
    ld      a, NR_DISPLAY_CTRL1
    out     (c), a
    ld      bc, NEXTREG_DAT
    in      a, (c)
    or      %10000000
    out     (c), a
    ret

; =============================================================================
; UPLOAD_PALETTE
; 256 entries * 2 bytes
; BC se uvnitr smycky pouziva na porty, takze loop counter nesmi byt v B
; =============================================================================
UPLOAD_PALETTE:
    ; vyber paletu Layer 2, first palette
    ld      bc, NEXTREG_SEL
    ld      a, NR_PALETTE_CTRL
    out     (c), a
    ld      bc, NEXTREG_DAT
    ld      a, %00010000
    out     (c), a

    ; index = 0
    ld      bc, NEXTREG_SEL
    ld      a, NR_PALETTE_IDX
    out     (c), a
    ld      bc, NEXTREG_DAT
    xor     a
    out     (c), a

    ld      hl, palette_buf
    ld      d, 0                        ; 256 iteraci

.loop:
    ; prvni byte barvy -> $44
    ld      bc, NEXTREG_SEL
    ld      a, NR_PALETTE_VAL9
    out     (c), a
    ld      bc, NEXTREG_DAT
    ld      a, (hl)
    inc     hl
    out     (c), a

    ; druhy byte barvy -> $41
    ld      bc, NEXTREG_SEL
    ld      a, NR_PALETTE_VAL
    out     (c), a
    ld      bc, NEXTREG_DAT
    ld      a, (hl)
    inc     hl
    out     (c), a

    dec     d
    jr      nz, .loop
    ret

; =============================================================================
; EXTRACT_FILENAME
; =============================================================================
EXTRACT_FILENAME:
    ld      de, filename_buf
    ld      b, 63

.skip:
    ld      a, (hl)
    or      a
    jr      z, .empty
    cp      $0D
    jr      z, .empty
    cp      ' '
    jr      z, .next
    cp      $0E
    jr      nz, .chk_tok
    inc     hl
    inc     hl
    inc     hl
    inc     hl
    inc     hl
    inc     hl
    jr      .skip

.chk_tok:
    cp      $A5
    jr      nc, .next
    jr      .first_char

.next:
    inc     hl
    jr      .skip

.empty:
    scf
    ret

.first_char:
    cp      '"'
    jr      z, .quoted

.plain:
    ld      a, (hl)
    or      a
    jr      z, .done
    cp      $0D
    jr      z, .done
    cp      ' '
    jr      z, .done
    cp      $A5
    jr      nc, .done
    cp      $20
    jr      c, .plain_skip
    ld      (de), a
    inc     de
    dec     b
    jr      z, .done
.plain_skip:
    inc     hl
    jr      .plain

.quoted:
    inc     hl
.qloop:
    ld      a, (hl)
    or      a
    jr      z, .done
    cp      $0D
    jr      z, .done
    cp      '"'
    jr      z, .done
    ld      (de), a
    inc     de
    inc     hl
    dec     b
    jr      nz, .qloop

.done:
    xor     a
    ld      (de), a
    ld      a, (filename_buf)
    or      a
    jr      z, .empty
    ret

; =============================================================================
; SHOW_HELP
; =============================================================================
SHOW_HELP:
    ld      hl, msg_help
    call    PRINT_MSG
    ld      bc, 0
    ret

; =============================================================================
; DECODE_ERRCODE
; =============================================================================
DECODE_ERRCODE:
    ld      hl, msg_err_prefix
    call    PRINT_MSG
    cp      2
    jr      z, .e2
    cp      3
    jr      z, .e3
    cp      5
    jr      z, .e5
    cp      7
    jr      z, .e7
    cp      8
    jr      z, .e8
    ld      hl, msg_eunk
    call    PRINT_MSG
    ret

.e2:
    ld      hl, msg_e2
    call    PRINT_MSG
    ret
.e3:
    ld      hl, msg_e3
    call    PRINT_MSG
    ret
.e5:
    ld      hl, msg_e5
    call    PRINT_MSG
    ret
.e7:
    ld      hl, msg_e7
    call    PRINT_MSG
    ret
.e8:
    ld      hl, msg_e8
    call    PRINT_MSG
    ret

; =============================================================================
; Print rutiny
; =============================================================================
PRINT_MSG:
    ld      a, (hl)
    or      a
    ret     z
    rst     $10
    inc     hl
    jr      PRINT_MSG

PRINT_NL:
    ld      a, 13
    rst     $10
    ret

PRINT_HEX8:
    push    af
    rrca
    rrca
    rrca
    rrca
    call    .nib
    pop     af
.nib:
    and     $0F
    add     a, '0'
    cp      '9'+1
    jr      c, .ok
    add     a, 7
.ok:
    rst     $10
    ret

PRINT_ASCIIZ_SAFE:
    ld      b, 40
.loop:
    ld      a, (hl)
    or      a
    ret     z
    cp      13
    ret     z
    rst     $10
    inc     hl
    djnz    .loop
    ret

; =============================================================================
; Data
; =============================================================================
arg_ptr:        defw    0
file_handle:    defb    0
page_lo:        defb    0
page_hi:        defb    0
dest_ptr:       defw    0
saved_mmu2:     defb    0
saved_mmu3:     defb    0
l2_base_bank:   defb    0

msg_errcode:    defm    " ErrCode=", 0
msg_err_prefix: defm    "esxDOS: ", 0
msg_e2:         defm    "File not found", 13, 0
msg_e3:         defm    "Path not found", 13, 0
msg_e5:         defm    "Access denied", 13, 0
msg_e7:         defm    "Invalid filename", 13, 0
msg_e8:         defm    "Invalid drive", 13, 0
msg_eunk:       defm    "Unknown error", 13, 0
msg_err_open:   defm    "Cannot open: ", 0
msg_err_read:   defm    "Read error or short file", 0

msg_help:
    defm    "SHOWNXI v1.4 - NXI Layer 2 viewer", 13
    defm    "Credit: Shrek/MB Maniax 2026", 13
    defb    13
    defm    "Usage:", 13
    defm    "  .shownxi screen.nxi", 13
    defm    "  .shownxi ", 34, "screen.nxi", 34, 13
    defm    "  .shownxi -h   (this help)", 13
    defb    13
    defm    "Supported NXI sizes:", 13
    defm    "  49152 B  image only (256x192)", 13
    defm    "  49664 B  image + 512 B palette", 13
    defb    0

filename_buf:   defs    64, 0
palette_buf:    defs    512, 0
scratch_buf:    defs    256, 0

    END     MAIN
