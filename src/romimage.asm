SECTION "ROM start", ROM0[$0]
    DS $100, 0 ; fill with NOP sled so it's compatible with T2 mode

SECTION "ROM Header", ROM0[$104]
    DS $143 - @, $00
    DB $80 ; compatible with CGB
    DS $150 - @, $00

    STATIC_ASSERT @ == $150, "Somehow the header got misaligned"
